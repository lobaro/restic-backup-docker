"""Backwards-compatibility suite.

Everything here describes behaviour the image has today and that users depend on.
A change that turns one of these red is a breaking change, whether or not intended.

Layout: every scenario fixture starts one throwaway container, performs the actions
once and records the results; the tests only assert on what was recorded, so they do
not depend on each other. Each docstring is the name of the matching Bash test.
Tests run in a container with the image defaults: repository /mnt/restic, tag
`testtag`, cron far in the future.
"""

from __future__ import annotations

from collections.abc import Iterator
from dataclasses import dataclass
from types import SimpleNamespace

import docker
import pytest
from conftest import LABELS
from helpers import Container, run_once

HELLO = "backup me"
PRE_BACKUP_HOOK = '#!/bin/sh\necho "PRE-HOOK-RAN"\n'
POST_BACKUP_HOOK = '#!/bin/sh\necho "POST-HOOK-RAN with rc=$1"\n'
PRE_CHECK_HOOK = '#!/bin/sh\necho "PRE-CHECK-HOOK-RAN"\n'
POST_CHECK_HOOK = '#!/bin/sh\necho "POST-CHECK-HOOK-RAN with rc=$1"\n'


@pytest.fixture(scope="class")
def started(request: pytest.FixtureRequest, run_container) -> Iterator[Container]:
    """Container for the class, configured by `@pytest.mark.container(suffix, **env)`."""
    marker = request.node.get_closest_marker("container")
    with run_container(marker.args[0], env=marker.kwargs) as container:
        yield container


def _running(container: Container) -> Container:
    """Scenarios that act on the container need it started; the start tests do not."""
    if not container.started:
        pytest.fail(f"container did not start:\n{container.start_log}", pytrace=False)
    return container


def _crontab_lines(container: Container) -> list[str]:
    return container.read_file("/var/spool/cron/crontabs/root").splitlines()


# ---------------------------------------------------------------------------
# repository bootstrap and default backup
# ---------------------------------------------------------------------------


@pytest.fixture(scope="class")
def default_run(started: Container) -> SimpleNamespace:
    c = _running(started)
    c.write_file("/data/hello.txt", HELLO)
    run = SimpleNamespace(container=c)
    run.backup = c.exec("/bin/backup")
    run.snapshots_after_first = c.snapshots()
    run.restore = c.restore_latest("/tmp/restore")
    run.restored = c.exec("cat", "/tmp/restore/data/hello.txt")
    run.backup_last_log = c.read_file("/var/log/backup-last.log")
    c.run("/bin/backup")
    run.snapshots_after_second = c.snapshots()
    run.check = c.exec("/bin/check")
    c.write_file("/hooks/pre-backup.sh", PRE_BACKUP_HOOK, executable=True)
    c.write_file("/hooks/post-backup.sh", POST_BACKUP_HOOK, executable=True)
    run.hook_backup = c.exec("/bin/backup")
    return run


@pytest.mark.container("default")
class TestDefaultBackup:
    def test_container_starts(self, started):
        """container starts with default configuration"""
        assert started.started, started.start_log

    def test_repository_is_initialised(self, started):
        """empty repository is initialised on first start"""
        assert "Running restic init" in started.logs()

    def test_repository_init_succeeds(self, started):
        """repository initialisation succeeds"""
        assert "Repo init status 0" in started.logs()

    def test_backup_cron_in_crontab(self, started):
        """BACKUP_CRON is written to the crontab"""
        lines = _crontab_lines(started)
        assert any(line.startswith("0 0 31 2 *") and "/bin/backup" in line for line in lines)

    def test_backup_cron_guarded_by_flock(self, started):
        """backup cron job is guarded by flock"""
        line = next(line for line in _crontab_lines(started) if "/bin/backup" in line)
        assert "flock -n /var/run/backup.lock" in line

    def test_no_check_cron_by_default(self, started):
        """no check cron job is installed while CHECK_CRON is unset"""
        lines = _crontab_lines(started)
        assert any("/bin/backup" in line for line in lines)  # the crontab we looked at is real
        assert not any("/bin/check" in line for line in lines)

    def test_backup_succeeds(self, default_run):
        """backup of /data succeeds"""
        assert default_run.backup.rc == 0
        assert "Backup Successful" in default_run.backup.out

    def test_missing_pre_backup_hook_reported(self, default_run):
        """missing pre-backup hook is reported, not fatal"""
        assert "Pre-backup script not found" in default_run.backup.out
        assert default_run.backup.rc == 0

    def test_missing_post_backup_hook_reported(self, default_run):
        """missing post-backup hook is reported, not fatal"""
        assert "Post-backup script not found" in default_run.backup.out
        assert default_run.backup.rc == 0

    def test_no_notification_without_config(self, default_run):
        """no mail or Teams notification is attempted without configuration"""
        assert "Backup Successful" in default_run.backup.out
        assert "notification" not in default_run.backup.out

    def test_one_snapshot_after_one_backup(self, default_run):
        """exactly one snapshot exists after one backup"""
        assert len(default_run.snapshots_after_first) == 1

    def test_snapshot_carries_restic_tag(self, default_run):
        """snapshot carries the configured RESTIC_TAG"""
        assert [s["tags"] for s in default_run.snapshots_after_first] == [["testtag"]]

    def test_restore_exits_zero(self, default_run):
        """restic restore of the latest snapshot exits 0"""
        assert default_run.restore.rc == 0, default_run.restore.out

    def test_restored_content_matches(self, default_run):
        """restored file content matches the original"""
        assert default_run.restored.rc == 0, default_run.restored.out
        assert default_run.restored.out == HELLO

    def test_backup_last_log_records_parameters(self, default_run):
        """backup-last.log records the run parameters"""
        assert "RESTIC_REPOSITORY: /mnt/restic" in default_run.backup_last_log

    def test_second_backup_adds_snapshot(self, default_run):
        """a second backup adds a second snapshot"""
        ids = {s["id"] for s in default_run.snapshots_after_second}
        assert len(default_run.snapshots_after_second) == 2
        assert {s["id"] for s in default_run.snapshots_after_first} < ids

    def test_check_passes_on_healthy_repository(self, default_run):
        """restic check passes on a healthy repository"""
        assert default_run.check.rc == 0
        assert "Check Successful" in default_run.check.out

    def test_missing_pre_check_hook_reported(self, default_run):
        """missing pre-check hook is reported, not fatal"""
        assert "Pre-check script not found" in default_run.check.out
        assert "Check Successful" in default_run.check.out

    def test_pre_backup_hook_executed(self, default_run):
        """pre-backup hook is executed"""
        assert "PRE-HOOK-RAN" in default_run.hook_backup.out

    def test_post_backup_hook_gets_return_code(self, default_run):
        """post-backup hook receives the backup return code"""
        assert "POST-HOOK-RAN with rc=0" in default_run.hook_backup.out


# ---------------------------------------------------------------------------
# CHECK_CRON and check hooks
# ---------------------------------------------------------------------------


@pytest.fixture(scope="class")
def checkcron_run(started: Container) -> SimpleNamespace:
    c = _running(started)
    run = SimpleNamespace(container=c, crontab=_crontab_lines(c))
    c.write_file("/data/hello.txt", HELLO)
    c.run("/bin/backup")
    c.write_file("/hooks/pre-check.sh", PRE_CHECK_HOOK, executable=True)
    c.write_file("/hooks/post-check.sh", POST_CHECK_HOOK, executable=True)
    run.check = c.exec("/bin/check")
    return run


@pytest.mark.container("checkcron", CHECK_CRON="0 0 31 2 *")
class TestCheckCron:
    def test_check_cron_guarded_by_shared_lock(self, checkcron_run):
        """check cron job is guarded by the shared backup lock"""
        check_lines = [line for line in checkcron_run.crontab if "/bin/check" in line]
        assert len(check_lines) == 1
        assert "flock -n /var/run/backup.lock" in check_lines[0]

    def test_check_cron_adds_cron_job(self, checkcron_run):
        """CHECK_CRON adds a check cron job to the crontab"""
        assert any(
            line.startswith("0 0 31 2 *") and "/bin/check" in line for line in checkcron_run.crontab
        )

    def test_crontab_has_backup_and_check_line(self, checkcron_run):
        """crontab has a backup line and a check line"""
        assert len([line for line in checkcron_run.crontab if line.strip()]) == 2

    def test_check_cron_keeps_backup_cron(self, checkcron_run):
        """CHECK_CRON does not replace the backup cron job"""
        assert "/bin/backup" in checkcron_run.crontab[0]

    def test_pre_check_hook_executed(self, checkcron_run):
        """pre-check hook is executed"""
        assert "PRE-CHECK-HOOK-RAN" in checkcron_run.check.out

    def test_post_check_hook_gets_return_code(self, checkcron_run):
        """post-check hook receives the check return code"""
        assert "POST-CHECK-HOOK-RAN with rc=0" in checkcron_run.check.out


# ---------------------------------------------------------------------------
# a corrupted repository is reported as failed
#
# check.sh prints "Check Successful" whenever restic exits 0, so a `restic check`
# that does nothing would keep the success path green. Damage the repository and
# require the failure path. The container is throwaway; the repo stays broken.
# ---------------------------------------------------------------------------

CORRUPT_CMD = 'f=$(find /mnt/restic/data -type f | head -n1); chmod u+w "$f"; printf garbage > "$f"'


@pytest.fixture(scope="class")
def corrupt_run(started: Container) -> SimpleNamespace:
    c = _running(started)
    c.write_file("/data/hello.txt", HELLO)
    c.run("/bin/backup")
    run = SimpleNamespace(container=c, snapshots_before=c.snapshots())
    c.run("sh", "-c", CORRUPT_CMD)
    run.check = c.exec("/bin/check")
    run.error_log_exists = c.file_exists("/var/log/check-error-last.log")
    return run


@pytest.mark.container("corrupt")
class TestCorruptedRepository:
    def test_repository_to_corrupt_has_snapshot(self, corrupt_run):
        """the repository to be corrupted has a snapshot"""
        assert len(corrupt_run.snapshots_before) == 1

    def test_check_detects_corruption(self, corrupt_run):
        """restic check detects a corrupted repository"""
        assert "Check Failed with Status" in corrupt_run.check.out

    def test_corruption_not_reported_successful(self, corrupt_run):
        """a corrupted repository is not reported as successful"""
        assert "Check Successful" not in corrupt_run.check.out
        assert "Check Failed with Status" in corrupt_run.check.out  # the check did run and report

    def test_failing_check_writes_error_log(self, corrupt_run):
        """failing check writes check-error-last.log"""
        assert corrupt_run.error_log_exists


# ---------------------------------------------------------------------------
# RESTIC_FORGET_ARGS
# ---------------------------------------------------------------------------


@pytest.fixture(scope="class")
def forget_run(started: Container) -> SimpleNamespace:
    c = _running(started)
    c.write_file("/data/hello.txt", HELLO)
    c.run("/bin/backup")
    first = c.snapshots()
    run = SimpleNamespace(container=c, first=first)
    run.second_backup = c.exec("/bin/backup")
    run.snapshots = c.snapshots()
    return run


@pytest.mark.container("forget", RESTIC_FORGET_ARGS="--keep-last 1")
class TestForgetArgs:
    def test_forget_runs_after_backup(self, forget_run):
        """forget runs after a successful backup when configured"""
        assert "Forget Successful" in forget_run.second_backup.out

    def test_keep_last_leaves_one_snapshot(self, forget_run):
        """--keep-last 1 leaves exactly one snapshot"""
        # two backups ran: one snapshot left that is not the first one proves forget pruned
        assert len(forget_run.first) == 1
        assert len(forget_run.snapshots) == 1
        assert forget_run.snapshots[0]["id"] != forget_run.first[0]["id"]


# ---------------------------------------------------------------------------
# RESTIC_JOB_ARGS
#
# backup-last.log only records the variable, it does not prove restic ever saw it.
# The arguments need a visible effect, otherwise a backup that silently drops
# RESTIC_JOB_ARGS still looks healthy.
# ---------------------------------------------------------------------------


@pytest.fixture(scope="class")
def jobargs_run(started: Container) -> SimpleNamespace:
    c = _running(started)
    c.write_file("/data/keep.txt", "keep")
    c.write_file("/data/skipme.txt", "skip")
    run = SimpleNamespace(container=c, backup=c.exec("/bin/backup"))
    run.restore = c.restore_latest("/tmp/restore")
    run.restored_keep = c.exec("cat", "/tmp/restore/data/keep.txt")
    run.paths = c.backed_up_paths()
    return run


@pytest.mark.container("jobargs", RESTIC_JOB_ARGS="--exclude=/data/skipme.txt")
class TestJobArgs:
    def test_backup_with_job_args_succeeds(self, jobargs_run):
        """backup with RESTIC_JOB_ARGS succeeds"""
        assert "Backup Successful" in jobargs_run.backup.out

    def test_job_args_do_not_break_backup(self, jobargs_run):
        """RESTIC_JOB_ARGS does not break a normal backup"""
        assert jobargs_run.restore.rc == 0, jobargs_run.restore.out
        assert jobargs_run.restored_keep.out == "keep"

    def test_job_args_passed_to_restic(self, jobargs_run):
        """RESTIC_JOB_ARGS is passed to restic backup"""
        # keep.txt shows the snapshot is the one of this scenario, skipme.txt must be missing
        assert "/data/keep.txt" in jobargs_run.paths
        assert "/data/skipme.txt" not in jobargs_run.paths


# ---------------------------------------------------------------------------
# BACKUP_SOURCES
# ---------------------------------------------------------------------------


@pytest.fixture(scope="class")
def sources_run(started: Container) -> SimpleNamespace:
    c = _running(started)
    c.write_file("/opt/custom/custom.txt", "custom source")
    c.write_file("/data/ignored.txt", "should not be backed up")
    c.run("/bin/backup")
    run = SimpleNamespace(container=c, restore=c.restore_latest("/tmp/restore"))
    run.restored = c.exec("cat", "/tmp/restore/opt/custom/custom.txt")
    run.paths = c.backed_up_paths()
    return run


@pytest.mark.container("sources", BACKUP_SOURCES="/opt/custom")
class TestBackupSources:
    def test_sources_override_default(self, sources_run):
        """BACKUP_SOURCES overrides the default /data source"""
        assert sources_run.restore.rc == 0, sources_run.restore.out
        assert sources_run.restored.out == "custom source"

    def test_sources_exclude_data(self, sources_run):
        """BACKUP_SOURCES excludes /data"""
        assert "/opt/custom/custom.txt" in sources_run.paths
        assert not [p for p in sources_run.paths if p.startswith("/data")]


# ---------------------------------------------------------------------------
# failure handling
# ---------------------------------------------------------------------------


@pytest.fixture(scope="class")
def failure_run(started: Container) -> SimpleNamespace:
    c = _running(started)
    c.write_file("/data/hello.txt", HELLO)
    # Back up a source that does not exist. The repository stays the initialised
    # default one, so the snapshot list below is of the repo the run really used.
    run = SimpleNamespace(
        container=c, backup=c.exec("/bin/backup", env={"BACKUP_SOURCES": "/does-not-exist"})
    )
    run.error_log_exists = c.file_exists("/var/log/backup-error-last.log")
    run.snapshots = c.snapshots()
    return run


@pytest.mark.container("failure")
class TestFailureHandling:
    def test_failing_backup_reported(self, failure_run):
        """a failing backup is reported as failed"""
        assert "Backup Failed with Status" in failure_run.backup.out

    def test_failing_backup_writes_error_log(self, failure_run):
        """failing backup writes backup-error-last.log"""
        assert failure_run.error_log_exists

    def test_failed_backup_leaves_no_snapshot(self, failure_run):
        """a failed backup leaves no snapshot behind"""
        # snapshots() raises on a restic error, so [] means a readable, empty repository
        assert "Backup Failed with Status" in failure_run.backup.out
        assert failure_run.snapshots == []


# ---------------------------------------------------------------------------
# timezone
#
# The base image already ships tzdata, so TZ works today. Pinned here so that
# neither a base image change nor a slimming effort silently breaks cron times
# for users who already rely on it.
# ---------------------------------------------------------------------------


@dataclass
class TimezoneRunner:
    client: docker.DockerClient
    image: str

    def zone(self, env: dict[str, str] | None = None) -> str:
        out = run_once(
            self.client, self.image, entrypoint=["date", "+%Z"], environment=env, labels=LABELS
        )
        return out.strip()


@pytest.fixture(scope="module")
def timezone(docker_client, image) -> TimezoneRunner:
    return TimezoneRunner(docker_client, image)


class TestTimezone:
    def test_default_timezone_is_utc(self, timezone):
        """the default timezone is UTC"""
        assert timezone.zone() == "UTC"

    def test_tz_variable_changes_timezone(self, timezone):
        """TZ=Europe/Berlin changes the container timezone"""
        assert timezone.zone({"TZ": "Europe/Berlin"}) in ("CET", "CEST")


# ---------------------------------------------------------------------------
# RESTIC_TAG handling
#
# The Dockerfile declares RESTIC_TAG="", so in a normal container the variable is
# always set and an empty value means "no tag". The `${RESTIC_TAG?...}` guard in
# backup.sh only triggers when the variable is truly unset.
# ---------------------------------------------------------------------------


@pytest.fixture(scope="class")
def tag_run(started: Container) -> SimpleNamespace:
    c = _running(started)
    c.write_file("/data/hello.txt", HELLO)
    run = SimpleNamespace(container=c, empty=c.exec("/bin/backup", env={"RESTIC_TAG": ""}))
    run.snapshots_after_empty = c.snapshots()
    run.unset = c.exec("env", "-u", "RESTIC_TAG", "/bin/backup")
    run.snapshots_after_unset = c.snapshots()
    return run


@pytest.mark.container("tag")
class TestResticTag:
    def test_empty_tag_creates_untagged_backup(self, tag_run):
        """an empty RESTIC_TAG creates an untagged backup"""
        assert "Backup Successful" in tag_run.empty.out
        [snapshot] = tag_run.snapshots_after_empty
        assert not snapshot.get("tags")

    def test_empty_tag_still_produces_snapshot(self, tag_run):
        """an empty RESTIC_TAG still produces a snapshot"""
        assert len(tag_run.snapshots_after_empty) == 1

    def test_unset_tag_refuses_backup(self, tag_run):
        """backup refuses to run when RESTIC_TAG is unset entirely"""
        assert "Missing environment variable RESTIC_TAG" in tag_run.unset.out

    def test_unset_tag_creates_no_snapshot(self, tag_run):
        """no extra snapshot is created when RESTIC_TAG is unset"""
        assert len(tag_run.snapshots_after_empty) == 1  # there was something to not add to
        assert len(tag_run.snapshots_after_unset) == 1
