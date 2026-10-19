"""Run container-structure-test without leaking Docker volumes.

container-structure-test starts one container per test and never removes it. The image
declares `VOLUME /data`, so every container drags an anonymous volume along that outlives
`docker rm`. With `--save` the containers are kept, and this wrapper removes the ones the
run created, together with their volumes (`remove(v=True)`). Run with `task test:structure`.

Exit code: the one of container-structure-test.
"""

from __future__ import annotations

import os
import signal
import subprocess
import sys
from pathlib import Path

import docker

CONFIG = Path(__file__).with_name("structure.yml")


def _raise_interrupt(signum: int, _frame: object) -> None:
    raise KeyboardInterrupt(f"received {signal.Signals(signum).name}")


def main() -> int:
    image = os.environ.get("IMAGE", "restic-backup-docker:test")
    signal.signal(signal.SIGTERM, _raise_interrupt)
    client = docker.from_env()
    before = {c.id for c in client.containers.list(all=True)}
    try:
        return subprocess.run(
            [
                "container-structure-test",
                "test",
                "--save",
                "--image",
                image,
                "--config",
                str(CONFIG),
            ],
            check=False,
        ).returncode
    finally:
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        for container in client.containers.list(all=True):
            if container.id not in before:
                container.remove(v=True, force=True)
        signal.signal(signal.SIGINT, signal.default_int_handler)


if __name__ == "__main__":
    sys.exit(main())
