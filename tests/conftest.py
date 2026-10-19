"""Shared fixtures and feature gating for the container test suite."""

from __future__ import annotations

import contextlib
import os
import signal
import subprocess
import uuid
from collections.abc import Callable, Iterator
from pathlib import Path

import docker
import pytest
from helpers import Container, remove_quietly, run_once, start_container

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


def _raise_interrupt(signum: int, _frame: object) -> None:
    raise KeyboardInterrupt(f"received {signal.Signals(signum).name}")


def pytest_configure(config: pytest.Config) -> None:
    """Turn SIGTERM into KeyboardInterrupt so session teardown (cleanup) runs."""
    signal.signal(signal.SIGTERM, _raise_interrupt)


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


def _remove_leftovers(client: docker.DockerClient) -> None:
    """Remove containers, then volumes, labelled with this run; safe to call repeatedly."""
    flt = {"label": f"rbd-test-run={RUN_ID}"}
    try:
        for container in client.containers.list(all=True, filters=flt):
            with contextlib.suppress(docker.errors.NotFound):
                container.remove(force=True, v=True)
    finally:
        for volume in client.volumes.list(filters=flt):
            with contextlib.suppress(docker.errors.NotFound):
                volume.remove(force=True)


@pytest.fixture(scope="session", autouse=True)
def _cleanup_leftovers(docker_client: docker.DockerClient) -> Iterator[None]:
    """Remove every container/volume this run created, even after failures or Ctrl-C.

    A Ctrl-C in `task`/`uv` is forwarded as a second SIGINT while teardown runs, so
    SIGINT/SIGTERM are ignored until cleanup is finished.
    """
    try:
        yield
    finally:
        old = {sig: signal.signal(sig, signal.SIG_IGN) for sig in (signal.SIGINT, signal.SIGTERM)}
        try:
            _remove_leftovers(docker_client)
        finally:
            for sig, handler in old.items():
                signal.signal(sig, handler)


@pytest.fixture(scope="session")
def detected_features(docker_client: docker.DockerClient, image: str) -> set[str]:
    out = run_once(
        docker_client,
        image,
        entrypoint=["sh", "-c", FEATURE_PROBE],
        labels={"rbd-test-run": RUN_ID},
    )
    return set(out.split())


def pytest_collection_modifyitems(items: list[pytest.Item]) -> None:
    for item in items:
        for marker in item.iter_markers("feature"):
            item.fixturenames.append("_feature_gate")
            if marker.args[0] not in KNOWN_FEATURES:
                raise pytest.UsageError(f"unknown feature gate: {marker.args[0]}")


def _apply_feature_gate(node: pytest.Item | pytest.Class, detected: set[str]) -> None:
    for marker in node.iter_markers("feature"):
        name = marker.args[0]
        if name in detected:
            continue
        if name in required_features():
            pytest.fail(
                f"feature '{name}' listed in {REQUIRED_FEATURES_FILE.name} "
                "but not present in the image",
                pytrace=False,
            )
        pytest.skip(f"feature '{name}' not in image yet")


@pytest.fixture
def _feature_gate(request: pytest.FixtureRequest, detected_features: set[str]) -> None:
    """Skip a feature test when the image lacks it; fail when it is required."""
    _apply_feature_gate(request.node, detected_features)


@pytest.fixture(scope="class")
def feature_gate_class(request: pytest.FixtureRequest, detected_features: set[str]) -> None:
    """Same gate for class-scoped fixtures: request it first so no container starts when gated."""
    _apply_feature_gate(request.node, detected_features)


LABELS = {"rbd-test-run": RUN_ID}


@pytest.fixture(scope="session")
def run_container(
    docker_client: docker.DockerClient, image: str
) -> Callable[..., contextlib.AbstractContextManager[Container]]:
    """Factory: `with run_container("name", env={...}) as c:` starts, waits, always removes."""

    @contextlib.contextmanager
    def _run(
        suffix: str, env: dict[str, str] | None = None, files: dict[str, str] | None = None
    ) -> Iterator[Container]:
        container = start_container(
            docker_client, image, f"rbd-test-{suffix}-{RUN_ID}", LABELS, env, files
        )
        try:
            yield container
        finally:
            remove_quietly(container)

    return _run
