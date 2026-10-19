"""Self test of the suite: prove that it goes red when the backup is broken.

Ported from `test/run.sh --sabotage`. Run with `task test:sabotage`.

A throwaway copy of the tree gets a backup.sh whose `restic backup` call is a no-op, the
nastiest kind of regression (the script still reports success). The compat tests run
against an image built from that copy. The check passes only if the assertions about the
backup itself fail by name. Red for another reason (an image that cannot start, a
non-executable /bin/backup) proves nothing and is reported as INVALID.

Exit codes: 0 sabotage detected, 1 suite did not detect it, 2 check invalid or broken.
Tracked files are never modified.
"""

from __future__ import annotations

import os
import shutil
import signal
import subprocess
import sys
import tempfile
import uuid
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
COPIED = ("Dockerfile", "backup.sh", "check.sh", "entry.sh")
# Tests about the backup itself; each must fail on the sabotaged image.
EXPECTED_RED = (
    "test_one_snapshot_after_one_backup",
    "test_second_backup_adds_snapshot",
)


class Invalid(Exception):
    """The check itself is broken; the suite result means nothing."""


def _raise_interrupt(signum: int, _frame: object) -> None:
    raise KeyboardInterrupt(f"received {signal.Signals(signum).name}")


def sabotage_tree(tmp: Path) -> None:
    for name in COPIED:
        shutil.copy2(ROOT / name, tmp / name)
    script = tmp / "backup.sh"
    lines = script.read_text().splitlines(keepends=True)
    patched = [
        ("true " + ln[len("restic backup ") :]) if ln.startswith("restic backup ") else ln
        for ln in lines
    ]
    if patched == lines:
        raise Invalid("sabotage patch did not apply, backup.sh changed shape")
    script.write_text("".join(patched))
    # Dockerfile COPY has no chmod: the image only works when the file is executable.
    script.chmod(script.stat().st_mode | 0o111)
    if not os.access(script, os.X_OK):
        raise Invalid("sabotaged backup.sh is not executable")


def failed_tests(report: Path) -> set[str]:
    cases = ET.parse(report).getroot().iter("testcase")
    return {
        c.get("name", "")
        for c in cases
        if c.find("failure") is not None or c.find("error") is not None
    }


def main() -> int:
    tag = f"rbd-sabotage:{uuid.uuid4().hex[:8]}"
    tmp = Path(tempfile.mkdtemp(prefix="rbd-sabotage-"))
    try:
        sabotage_tree(tmp)
        print(f">>> building {tag} from a sabotaged copy")
        build = subprocess.run(["docker", "build", "--quiet", "-t", tag, str(tmp)])
        if build.returncode != 0:
            raise Invalid("image build failed")
        print(">>> running the compat tests against the sabotaged image (failure expected)")
        report = tmp / "report.xml"
        proc = subprocess.run(
            [
                sys.executable,
                "-m",
                "pytest",
                "tests/test_compat.py",
                "-p",
                "no:cacheprovider",
                f"--junitxml={report}",
            ],
            cwd=ROOT,
            env={**os.environ, "IMAGE": tag},
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        print(proc.stdout)
        if proc.returncode == 0:
            print(
                "SABOTAGE CHECK FAILED: the compat tests passed on a broken image", file=sys.stderr
            )
            return 1
        if "permission denied" in proc.stdout.lower():
            raise Invalid("log contains 'permission denied', suite failed for the wrong reason")
        if not report.is_file():
            raise Invalid(f"pytest produced no report (exit code {proc.returncode})")
        red = failed_tests(report)
        missing = [name for name in EXPECTED_RED if name not in red]
        for name in missing:
            print(
                f"SABOTAGE CHECK FAILED: expected assertion did not fail: {name}", file=sys.stderr
            )
        if missing:
            return 1
        print("\nsabotage check ok: the compat tests detect a broken backup")
        return 0
    except Invalid as exc:
        print(f"SABOTAGE CHECK INVALID: {exc}", file=sys.stderr)
        return 2
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
        subprocess.run(["docker", "rmi", "-f", tag], capture_output=True)


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, _raise_interrupt)
    sys.exit(main())
