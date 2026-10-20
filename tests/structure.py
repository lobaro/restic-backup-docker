"""Run container-structure-test without leaking Docker volumes.

container-structure-test starts one container per test and never removes it. The image
declares `VOLUME /data`, so every container drags an anonymous volume along that outlives
`docker rm`. With `--save` the containers are kept, and this wrapper removes the ones of
the image under test that the run created, together with their volumes (`remove(v=True)`);
containers of other images or of the compat suite (a parallel run, a compose stack) are left
alone.
Run with `task test:structure`.

A run longer than CST_TIMEOUT seconds (default 300) is killed: container-structure-test has
no timeout of its own and can block forever waiting for a container.

Exit code: the one of container-structure-test; 124 on timeout.
"""

from __future__ import annotations

import contextlib
import os
import signal
import subprocess
import sys
from pathlib import Path

import docker
from helpers import raise_interrupt

CONFIG = Path(__file__).with_name("structure.yml")
TIMEOUT_EXIT = 124


def _containers_of(client: docker.DockerClient, image_id: str) -> list:
    """Containers of the image that container-structure-test could have created.

    Containers of the compat suite carry the `rbd-test-run` label; their owner removes them.
    """
    found = client.containers.list(all=True, filters={"ancestor": image_id})
    return [c for c in found if "rbd-test-run" not in c.labels]


def main() -> int:
    image = os.environ.get("IMAGE", "restic-backup-docker:test")
    signal.signal(signal.SIGTERM, raise_interrupt)
    client = docker.from_env()
    image_id = client.images.get(image).id
    before = {c.id for c in _containers_of(client, image_id)}
    try:
        timeout = float(os.environ.get("CST_TIMEOUT", "300"))
        try:
            return subprocess.run(
                [
                    "container-structure-test",
                    "test",
                    "--save",
                    "--image",
                    image,
                    "--config",
                    os.environ.get("CST_CONFIG", str(CONFIG)),
                ],
                check=False,
                timeout=timeout,
            ).returncode
        except subprocess.TimeoutExpired:
            print(f"container-structure-test timed out after {timeout:g} s", file=sys.stderr)
            return TIMEOUT_EXIT
    finally:
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        for container in _containers_of(client, image_id):
            if container.id not in before:
                with contextlib.suppress(docker.errors.NotFound):
                    container.remove(v=True, force=True)
        signal.signal(signal.SIGINT, signal.default_int_handler)


if __name__ == "__main__":
    sys.exit(main())
