"""Shared fixtures and feature gating for the container test suite."""

from __future__ import annotations

import os
import subprocess
import uuid
from collections.abc import Iterator
from pathlib import Path

import docker
import pytest

ROOT = Path(__file__).resolve().parent.parent
IMAGE = os.environ.get("IMAGE", "restic-backup-docker:test")
REQUIRED_FEATURES_FILE = Path(
    os.environ.get("REQUIRED_FEATURES_FILE", Path(__file__).with_name("required-features.txt"))
)
RUN_ID = uuid.uuid4().hex[:8]

# Shell probe run once in a throwaway container; one line per detected feature.
FEATURE_PROBE = """
grep -q RESTIC_STREAM /bin/backup && echo stream
command -v docker >/dev/null && echo docker-cli
command -v bash >/dev/null && echo bash
command -v msmtp >/dev/null && echo msmtp
true
"""
KNOWN_FEATURES = ("stream", "docker-cli", "bash", "msmtp")


def required_features() -> set[str]:
    if not REQUIRED_FEATURES_FILE.is_file():
        return set()
    lines = (line.strip() for line in REQUIRED_FEATURES_FILE.read_text().splitlines())
    return {line for line in lines if line and not line.startswith("#")}


def pytest_addoption(parser: pytest.Parser) -> None:
    parser.addoption("--build", action="store_true", help="build the image before testing")


@pytest.fixture(scope="session")
def docker_client() -> Iterator[docker.DockerClient]:
    try:
        client = docker.from_env()
        client.ping()
    except docker.errors.DockerException as exc:
        pytest.exit(f"docker is not available: {exc}", returncode=2)
    yield client
    client.close()


@pytest.fixture(scope="session")
def image(request: pytest.FixtureRequest, docker_client: docker.DockerClient) -> str:
    """Tag of the image under test; built on demand with --build."""
    if request.config.getoption("--build"):
        subprocess.run(["docker", "build", "--quiet", "-t", IMAGE, str(ROOT)], check=True)
    try:
        docker_client.images.get(IMAGE)
    except docker.errors.ImageNotFound:
        pytest.exit(f"image {IMAGE} not found, run `task build` or pass --build", returncode=2)
    return IMAGE


@pytest.fixture(scope="session", autouse=True)
def _cleanup_leftovers(docker_client: docker.DockerClient) -> Iterator[None]:
    """Remove every container/volume this run created, even after failures."""
    yield
    for container in docker_client.containers.list(
        all=True, filters={"label": f"rbd-test-run={RUN_ID}"}
    ):
        container.remove(force=True, v=True)
    for volume in docker_client.volumes.list(filters={"label": f"rbd-test-run={RUN_ID}"}):
        volume.remove(force=True)


@pytest.fixture(scope="session")
def detected_features(docker_client: docker.DockerClient, image: str) -> set[str]:
    out = docker_client.containers.run(
        image, entrypoint=["sh", "-c", FEATURE_PROBE], remove=True, labels={"rbd-test-run": RUN_ID}
    )
    return set(out.decode().split())


def pytest_collection_modifyitems(items: list[pytest.Item]) -> None:
    for item in items:
        for marker in item.iter_markers("feature"):
            item.fixturenames.append("_feature_gate")
            if marker.args[0] not in KNOWN_FEATURES:
                raise pytest.UsageError(f"unknown feature gate: {marker.args[0]}")


@pytest.fixture
def _feature_gate(request: pytest.FixtureRequest, detected_features: set[str]) -> None:
    """Skip a feature test when the image lacks it; fail when it is required."""
    for marker in request.node.iter_markers("feature"):
        name = marker.args[0]
        if name in detected_features:
            continue
        if name in required_features():
            pytest.fail(
                f"feature '{name}' listed in {REQUIRED_FEATURES_FILE.name} "
                "but not present in the image",
                pytrace=False,
            )
        pytest.skip(f"feature '{name}' not in image yet")
