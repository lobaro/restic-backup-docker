"""Helpers around a running test container.

Rule for everything in here: a failing command is never turned into an empty or
zero result. Helpers that return parsed data raise on a non-zero exit, so a broken
restic call fails the test instead of looking like "no snapshots".
"""

from __future__ import annotations

import contextlib
import io
import json
import signal
import tarfile
import time
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import PurePosixPath
from typing import Any

import docker
import pytest
from docker.models.containers import Container as DockerContainer

START_TIMEOUT = 60
START_MARKER = "Container started."


@dataclass(frozen=True)
class ExecResult:
    rc: int
    out: str  # stdout and stderr, interleaved like `2>&1`


class CommandError(AssertionError):
    pass


def raise_interrupt(signum: int, _frame: object) -> None:
    """Signal handler: turn SIGTERM into KeyboardInterrupt so cleanup code runs."""
    raise KeyboardInterrupt(f"received {signal.Signals(signum).name}")


class StepFailed(Exception):
    """A scenario step could not run; not an assertion about the behaviour under test.

    Deliberately no AssertionError: sabotage.py tells it apart from a real assertion
    failure by the exception name in the JUnit report.
    """


class Scenario:
    """Results of the actions of one scenario fixture.

    `record(name, fn)` runs one step and stores its result or its error. Reading an
    attribute of a failed step raises, so only the tests that assert on that step fail;
    the other tests of the class still run against what the scenario did produce.
    """

    def __init__(self) -> None:
        self._steps: dict[str, tuple[Any, BaseException | None]] = {}

    def record(self, name: str, step: Callable[[], Any]) -> None:
        try:
            self._steps[name] = (step(), None)
        except Exception as exc:  # noqa: BLE001 - the error is re-raised on access
            self._steps[name] = (None, exc)

    def __getattr__(self, name: str) -> Any:
        try:
            value, error = self.__dict__["_steps"][name]
        except KeyError:
            raise AttributeError(name) from None
        if error is not None:
            raise StepFailed(f"scenario step '{name}' failed: {error}") from error
        return value


def running(container: Container) -> Container:
    """Scenarios that act on the container need it started; the start tests do not."""
    if not container.started:
        pytest.fail(f"container did not start:\n{container.start_log}", pytrace=False)
    return container


class Container:
    """A started image container with exec/file helpers."""

    def __init__(self, raw: DockerContainer, started: bool, start_log: str) -> None:
        self.raw = raw
        self.started = started
        self.start_log = start_log

    def exec(self, *cmd: str, env: dict[str, str] | None = None) -> ExecResult:
        """Run a command; the exit code is returned, not checked."""
        code, out = self.raw.exec_run(list(cmd), environment=env)
        return ExecResult(code, out.decode(errors="replace").replace("\r", ""))

    def run(self, *cmd: str, env: dict[str, str] | None = None) -> str:
        """Run a command that must succeed; return its output."""
        res = self.exec(*cmd, env=env)
        if res.rc != 0:
            raise CommandError(f"{' '.join(cmd)} exited {res.rc}:\n{res.out}")
        return res.out

    def write_file(self, path: str, content: str, *, executable: bool = False) -> None:
        """Create a file (and its directory) without a bind mount."""
        self.run("mkdir", "-p", str(PurePosixPath(path).parent))
        put_file(self.raw, path, content, executable=executable)

    def read_file(self, path: str) -> str:
        return self.run("cat", path)

    def file_exists(self, path: str) -> bool:
        res = self.exec("test", "-f", path)
        if res.rc not in (0, 1):
            raise CommandError(f"test -f {path} exited {res.rc}:\n{res.out}")
        return res.rc == 0

    def logs(self) -> str:
        return self.raw.logs().decode(errors="replace").replace("\r", "")

    # restic -------------------------------------------------------------

    def restic_json(self, *args: str) -> Any:
        """Run restic with --json and parse stdout; any failure raises."""
        code, (out, err) = self.raw.exec_run(["restic", *args, "--json"], demux=True)
        if code != 0:
            raise CommandError(f"restic {' '.join(args)} exited {code}:\n{(err or b'').decode()}")
        return json.loads((out or b"").decode())

    def snapshots(self) -> list[dict[str, Any]]:
        return self.restic_json("snapshots") or []

    def backed_up_paths(self, snapshot: str = "latest") -> set[str]:
        """Paths contained in a snapshot (`restic ls --json` emits one JSON object per line)."""
        code, (out, err) = self.raw.exec_run(["restic", "ls", snapshot, "--json"], demux=True)
        if code != 0:
            raise CommandError(f"restic ls {snapshot} exited {code}:\n{(err or b'').decode()}")
        lines = (out or b"").decode().splitlines()
        return {n["path"] for n in map(json.loads, lines) if n.get("struct_type") == "node"}

    def restore_latest(self, target: str) -> ExecResult:
        return self.exec("restic", "restore", "latest", "--target", target)


def _dir_exists(raw: DockerContainer, path: str) -> bool:
    """Ask the daemon with a HEAD request on the archive endpoint: stat only, no tar stream.

    A container that is not started cannot exec `test -d`, and `get_archive` would leave
    its streaming response open.
    """
    api = raw.client.api
    response = api.head(api._url("/containers/{0}/archive", raw.id), params={"path": path})
    try:
        if response.status_code == 404:
            return False
        response.raise_for_status()
        return True
    finally:
        response.close()


def put_file(raw: DockerContainer, path: str, content: str, *, executable: bool = False) -> None:
    """Copy a file into an existing (also not yet started) container via a tar archive.

    Missing parent directories are created (like `mkdir -p`); existing ones are left
    untouched, so their mode and owner stay as the image defines them.
    """
    target = PurePosixPath(path)
    missing = []
    for parent in target.parents:
        if _dir_exists(raw, str(parent)):
            break
        missing.append(parent)
    data = content.encode()
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w") as tar:
        for directory in reversed(missing):
            dir_info = tarfile.TarInfo(str(directory).lstrip("/"))
            dir_info.type = tarfile.DIRTYPE
            dir_info.mode = 0o755
            tar.addfile(dir_info)
        info = tarfile.TarInfo(str(target).lstrip("/"))
        info.size = len(data)
        info.mode = 0o755 if executable else 0o644
        tar.addfile(info, io.BytesIO(data))
    buf.seek(0)
    if not raw.put_archive("/", buf):
        raise CommandError(f"could not write {path}")


def start_container(
    client: docker.DockerClient,
    image: str,
    name: str,
    labels: dict[str, str],
    env: dict[str, str] | None = None,
    files: dict[str, str] | None = None,
) -> Container:
    """Start the image with a cron far in the future, so only explicit backups run.

    `files` (path in container -> content) are placed before entry.sh runs, without a
    bind mount, so tests can cover what the entrypoint does with them at startup.
    """
    environment = {
        "RESTIC_PASSWORD": "testpassword",
        "RESTIC_TAG": "testtag",
        "BACKUP_CRON": "0 0 31 2 *",
        **(env or {}),
    }
    if files:
        raw = client.containers.create(image, name=name, environment=environment, labels=labels)
        for path, content in files.items():
            put_file(raw, path, content)
        raw.start()
    else:
        raw = client.containers.run(
            image, detach=True, name=name, environment=environment, labels=labels
        )
    deadline = time.monotonic() + START_TIMEOUT
    while time.monotonic() < deadline:
        log = raw.logs().decode(errors="replace")
        if START_MARKER in log:
            return Container(raw, True, log)
        raw.reload()
        if raw.status != "running":
            return Container(raw, False, f"container exited early:\n{log}")
        time.sleep(0.5)
    return Container(raw, False, f"timeout waiting for start:\n{raw.logs().decode()}")


def remove_quietly(container: Container) -> None:
    with contextlib.suppress(docker.errors.NotFound):
        container.raw.remove(force=True, v=True)


def run_once(client: docker.DockerClient, image: str, **kwargs: Any) -> str:
    """Run a short-lived container and return its output.

    `containers.run(remove=True)` keeps the image's anonymous volumes (VOLUME /data),
    so run detached and remove the container together with its volumes.
    """
    container = client.containers.run(image, detach=True, **kwargs)
    try:
        result = container.wait()
        output = container.logs(stdout=True, stderr=False).decode()
        if result["StatusCode"] != 0:
            raise CommandError(f"container exited {result['StatusCode']}:\n{output}")
        return output
    finally:
        with contextlib.suppress(docker.errors.NotFound):
            container.remove(force=True, v=True)
