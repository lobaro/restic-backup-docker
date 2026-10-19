"""Feature-gated tests, ported from test/features.sh.

Each class is guarded by `@pytest.mark.feature(<gate>)`: it runs as soon as the built
image ships the feature (detected in conftest.py) and is skipped before that. A gate
listed in tests/required-features.txt turns the skip into a failure. Each docstring is
the name of the matching Bash test.

Scenario fixtures request `feature_gate_class` first, so a gated class never starts a
container on an image without the feature.
"""

from __future__ import annotations

from collections.abc import Iterator
from types import SimpleNamespace

import pytest
from conftest import LABELS
from helpers import Container, run_once

STREAM_ENV = {
    "RESTIC_STREAM": "1",
    "RESTIC_STREAM_CMD": "echo hello-stream",
    "RESTIC_STREAM_FILENAME": "stream.txt",
}
BASH_HOOK = """#!/bin/bash
arr=(one two)
if [[ "${arr[1]}" == "two" ]]; then echo "BASH-HOOK-RAN"; fi
"""
MSMTP_CONFIG = "defaults\naccount default\nhost localhost\n"


def _running(container: Container) -> Container:
    if not container.started:
        pytest.fail(f"container did not start:\n{container.start_log}", pytrace=False)
    return container


# ---------------------------------------------------------------------------
# stream backup (PR #109)
# ---------------------------------------------------------------------------


@pytest.fixture(scope="class")
def stream_run(feature_gate_class, run_container) -> Iterator[SimpleNamespace]:
    with run_container("stream", env=STREAM_ENV) as c:
        _running(c)
        run = SimpleNamespace(container=c)
        run.backup = c.exec("/bin/backup")
        run.snapshots = c.snapshots()
        c.exec("restic", "restore", "latest", "--target", "/tmp/restore")
        run.restored = c.exec("cat", "/tmp/restore/stream.txt")
        yield run


@pytest.fixture(scope="class")
def stream_jobargs_run(feature_gate_class, run_container) -> Iterator[SimpleNamespace]:
    # --host is used because it is visible in the snapshot metadata of a stdin backup.
    with run_container(
        "stream-jobargs", env={**STREAM_ENV, "RESTIC_JOB_ARGS": "--host=jobargshost"}
    ) as c:
        _running(c)
        c.exec("/bin/backup")
        # restic's own --host filter only returns snapshots whose hostname equals the
        # value; both directions are checked so the filter is known to discriminate.
        yield SimpleNamespace(
            matching=c.restic_json("snapshots", "--host", "jobargshost") or [],
            unrelated=c.restic_json("snapshots", "--host", "some-other-host") or [],
        )


@pytest.fixture(scope="class")
def stream_misconfigured_run(feature_gate_class, run_container) -> Iterator[SimpleNamespace]:
    with run_container("stream-misconfigured", env={"RESTIC_STREAM": "1"}) as c:
        _running(c)
        backup = c.exec("/bin/backup")
        yield SimpleNamespace(backup=backup, snapshots=c.snapshots())


@pytest.fixture(scope="class")
def stream_disabled_run(feature_gate_class, run_container) -> Iterator[SimpleNamespace]:
    with run_container("stream-disabled") as c:
        _running(c)
        c.write_file("/data/hello.txt", "backup me")
        c.exec("/bin/backup")
        yield SimpleNamespace(snapshots=c.snapshots())


@pytest.mark.feature("stream")
class TestStream:
    def test_stream_backup_succeeds(self, stream_run):
        """stream backup succeeds"""
        assert "Backup Successful" in stream_run.backup.out

    def test_stream_backup_creates_one_snapshot(self, stream_run):
        """stream backup creates exactly one snapshot"""
        assert len(stream_run.snapshots) == 1

    def test_stream_content_stored_under_filename(self, stream_run):
        """stream content is stored under RESTIC_STREAM_FILENAME"""
        assert stream_run.restored.rc == 0, stream_run.restored.out
        assert stream_run.restored.out == "hello-stream\n"

    def test_job_args_set_host_of_stream_snapshot(self, stream_jobargs_run):
        """RESTIC_JOB_ARGS sets the host of the stream backup snapshot"""
        assert len(stream_jobargs_run.matching) == 1

    def test_host_filter_does_not_match_unrelated_host(self, stream_jobargs_run):
        """the host filter does not match an unrelated hostname"""
        assert stream_jobargs_run.unrelated == []

    def test_incomplete_stream_config_does_not_report_success(self, stream_misconfigured_run):
        """incomplete stream configuration does not report success"""
        assert "Backup Successful" not in stream_misconfigured_run.backup.out

    def test_incomplete_stream_config_creates_no_snapshot(self, stream_misconfigured_run):
        """incomplete stream configuration creates no snapshot"""
        assert stream_misconfigured_run.snapshots == []

    def test_file_backup_still_works_with_stream_feature(self, stream_disabled_run):
        """file backup still works while the stream feature is present"""
        assert len(stream_disabled_run.snapshots) == 1


# ---------------------------------------------------------------------------
# docker cli (PR #99)
# ---------------------------------------------------------------------------


@pytest.mark.feature("docker-cli")
def test_docker_cli_usable(docker_client, image):
    """docker cli is usable inside the image"""
    out = run_once(
        docker_client, image, entrypoint=["docker"], command=["--version"], labels=LABELS
    )
    assert "Docker version" in out


# ---------------------------------------------------------------------------
# bash in hooks (PR #99)
# ---------------------------------------------------------------------------


@pytest.fixture(scope="class")
def bash_hook_run(feature_gate_class, run_container) -> Iterator[SimpleNamespace]:
    with run_container("bash-hooks") as c:
        _running(c)
        c.write_file("/hooks/pre-backup.sh", BASH_HOOK, executable=True)
        c.write_file("/data/hello.txt", "backup me")
        yield SimpleNamespace(backup=c.exec("/bin/backup"))


@pytest.mark.feature("bash")
class TestBashHooks:
    def test_bash_hook_runs(self, bash_hook_run):
        """a hook with a bash shebang and bash syntax runs"""
        assert "BASH-HOOK-RAN" in bash_hook_run.backup.out


# ---------------------------------------------------------------------------
# msmtp mail relay (PR #84)
# ---------------------------------------------------------------------------


@pytest.fixture(scope="class")
def msmtp_config_run(feature_gate_class, run_container) -> Iterator[Container]:
    # entry.sh copies the config at startup, so it must exist before the container starts.
    with run_container("msmtp-config", files={"/config/msmtprc": MSMTP_CONFIG}) as c:
        yield _running(c)


@pytest.fixture(scope="class")
def msmtp_missing_config_run(feature_gate_class, run_container) -> Iterator[SimpleNamespace]:
    # Users who configured mail before msmtp existed must not lose their backups.
    env = {"MAILX_ARGS": "-r from@example.com -s subject to@example.com"}
    with run_container("msmtp-missing-config", env=env) as c:
        _running(c)
        c.write_file("/data/hello.txt", "backup me")
        backup = c.exec("/bin/backup")
        yield SimpleNamespace(backup=backup, snapshots=c.snapshots())


@pytest.mark.feature("msmtp")
class TestMsmtp:
    def test_sendmail_is_msmtp(self, docker_client, image):
        """sendmail is provided by msmtp"""
        target = run_once(
            docker_client,
            image,
            entrypoint=["sh", "-c", "readlink -f /usr/sbin/sendmail"],
            labels=LABELS,
        )
        assert "msmtp" in target

    def test_config_copied_to_etc(self, msmtp_config_run):
        """msmtp config from /config is copied to /etc/msmtprc"""
        assert msmtp_config_run.file_exists("/etc/msmtprc")

    def test_copied_config_not_world_readable(self, msmtp_config_run):
        """copied msmtp config is not world readable"""
        assert msmtp_config_run.run("stat", "-c", "%a", "/etc/msmtprc").strip() == "600"

    def test_backup_succeeds_without_msmtp_config(self, msmtp_missing_config_run):
        """backup succeeds with MAILX_ARGS set but no msmtp config"""
        assert "Backup Successful" in msmtp_missing_config_run.backup.out

    def test_snapshot_created_without_msmtp_config(self, msmtp_missing_config_run):
        """snapshot is created even when the mail relay is unconfigured"""
        assert len(msmtp_missing_config_run.snapshots) == 1
