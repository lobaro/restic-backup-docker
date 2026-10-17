#!/usr/bin/env bash
# Backwards-compatibility suite.
#
# Everything in here describes behaviour the image has today and that users
# depend on. These tests always run, for every pull request. A change that
# turns one of them red is a breaking change, whether or not that was intended.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test/lib.sh
. "${SCRIPT_DIR}/lib.sh"

trap stop_container EXIT

echo "=== compat: repository bootstrap and default backup ==="

start_container default
wait_for_start || { fail "container starts with default configuration"; summary "compat"; exit 1; }
pass "container starts with default configuration"

startup_log="$(docker logs "$CONTAINER" 2>&1)"
assert_contains "$startup_log" "Running restic init" \
    "empty repository is initialised on first start"
assert_contains "$startup_log" "Repo init status 0" \
    "repository initialisation succeeds"

crontab="$(in_container cat /var/spool/cron/crontabs/root)"
assert_contains "$crontab" "/bin/backup" \
    "BACKUP_CRON is written to the crontab"
assert_contains "$crontab" "flock -n /var/run/backup.lock" \
    "backup cron job is guarded by flock"
assert_not_contains "$crontab" "/bin/check" \
    "no check cron job is installed while CHECK_CRON is unset"

write_file /data/hello.txt "backup me"

backup_log="$(in_container /bin/backup 2>&1)"
assert_contains "$backup_log" "Backup Successful" \
    "backup of /data succeeds"
assert_contains "$backup_log" "Pre-backup script not found" \
    "missing pre-backup hook is reported, not fatal"
assert_contains "$backup_log" "Post-backup script not found" \
    "missing post-backup hook is reported, not fatal"
assert_not_contains "$backup_log" "notification" \
    "no mail or Teams notification is attempted without configuration"
assert_eq "1" "$(snapshot_count)" \
    "exactly one snapshot exists after one backup"

snapshots="$(in_container restic snapshots --json 2>/dev/null)"
assert_contains "$snapshots" '"testtag"' \
    "snapshot carries the configured RESTIC_TAG"

in_container restic restore latest --target /tmp/restore >/dev/null 2>&1
restored="$(in_container cat /tmp/restore/data/hello.txt 2>&1)"
assert_eq "backup me" "$restored" \
    "restored file content matches the original"

logfile="$(in_container cat /var/log/backup-last.log 2>&1)"
assert_contains "$logfile" "RESTIC_REPOSITORY: /mnt/restic" \
    "backup-last.log records the run parameters"

in_container /bin/backup >/dev/null 2>&1
assert_eq "2" "$(snapshot_count)" \
    "a second backup adds a second snapshot"

echo
echo "=== compat: data integrity check ==="

check_log="$(in_container /bin/check 2>&1)"
assert_contains "$check_log" "Check Successful" \
    "restic check passes on a healthy repository"
assert_contains "$check_log" "Pre-check script not found" \
    "missing pre-check hook is reported, not fatal"

echo
echo "=== compat: pre- and post-backup hooks ==="

write_file /hooks/pre-backup.sh '#!/bin/sh
echo "PRE-HOOK-RAN"
'
write_file /hooks/post-backup.sh '#!/bin/sh
echo "POST-HOOK-RAN with rc=$1"
'
in_container chmod +x /hooks/pre-backup.sh /hooks/post-backup.sh

hook_log="$(in_container /bin/backup 2>&1)"
assert_contains "$hook_log" "PRE-HOOK-RAN" \
    "pre-backup hook is executed"
assert_contains "$hook_log" "POST-HOOK-RAN with rc=0" \
    "post-backup hook receives the backup return code"

stop_container

echo
echo "=== compat: a corrupted repository is reported as failed ==="
# The success path above is not enough: check.sh prints "Check Successful"
# whenever restic exits 0, so a `restic check` that does nothing at all would
# keep this suite green. Damage the repository and require the failure path.
# Runs in its own throwaway container, the repository stays broken afterwards.

start_container corrupt
wait_for_start || { fail "container starts for the corruption test"; summary "compat"; exit 1; }
write_file /data/hello.txt "backup me"
in_container /bin/backup >/dev/null 2>&1
assert_eq "1" "$(snapshot_count)" \
    "the repository to be corrupted has a snapshot"

in_container sh -c 'f=$(find /mnt/restic/data -type f | head -n1); chmod u+w "$f"; printf garbage > "$f"'
broken_check_log="$(in_container /bin/check 2>&1)"
assert_contains "$broken_check_log" "Check Failed with Status" \
    "restic check detects a corrupted repository"
assert_not_contains "$broken_check_log" "Check Successful" \
    "a corrupted repository is not reported as successful"
if in_container test -f /var/log/check-error-last.log; then
    pass "failing check writes check-error-last.log"
else
    fail "failing check writes check-error-last.log" "file is missing"
fi
stop_container

echo
echo "=== compat: RESTIC_FORGET_ARGS ==="

start_container forget -e "RESTIC_FORGET_ARGS=--keep-last 1"
wait_for_start || { fail "container starts with RESTIC_FORGET_ARGS"; summary "compat"; exit 1; }
write_file /data/hello.txt "backup me"
in_container /bin/backup >/dev/null 2>&1
forget_log="$(in_container /bin/backup 2>&1)"
assert_contains "$forget_log" "Forget Successful" \
    "forget runs after a successful backup when configured"
assert_eq "1" "$(snapshot_count)" \
    "--keep-last 1 leaves exactly one snapshot"
stop_container

echo
echo "=== compat: RESTIC_JOB_ARGS ==="
# backup-last.log only records the variable, it does not prove restic ever saw
# it. The arguments have to have a visible effect, otherwise a backup that
# silently drops RESTIC_JOB_ARGS still looks healthy.

start_container jobargs -e "RESTIC_JOB_ARGS=--exclude=/data/skipme.txt"
wait_for_start || { fail "container starts with RESTIC_JOB_ARGS"; summary "compat"; exit 1; }
write_file /data/keep.txt "keep"
write_file /data/skipme.txt "skip"
jobargs_log="$(in_container /bin/backup 2>&1)"
assert_contains "$jobargs_log" "Backup Successful" \
    "backup with RESTIC_JOB_ARGS succeeds"
in_container restic restore latest --target /tmp/restore >/dev/null 2>&1
assert_eq "keep" "$(in_container cat /tmp/restore/data/keep.txt 2>&1)" \
    "RESTIC_JOB_ARGS does not break a normal backup"
if in_container test -f /tmp/restore/data/skipme.txt; then
    fail "RESTIC_JOB_ARGS is passed to restic backup" \
        "the excluded file was backed up anyway"
else
    pass "RESTIC_JOB_ARGS is passed to restic backup"
fi
stop_container

echo
echo "=== compat: BACKUP_SOURCES ==="

start_container sources -e "BACKUP_SOURCES=/opt/custom"
wait_for_start || { fail "container starts with BACKUP_SOURCES"; summary "compat"; exit 1; }
write_file /opt/custom/custom.txt "custom source"
write_file /data/ignored.txt "should not be backed up"
in_container /bin/backup >/dev/null 2>&1
in_container restic restore latest --target /tmp/restore >/dev/null 2>&1
assert_eq "custom source" "$(in_container cat /tmp/restore/opt/custom/custom.txt 2>&1)" \
    "BACKUP_SOURCES overrides the default /data source"
if in_container test -f /tmp/restore/data/ignored.txt; then
    fail "BACKUP_SOURCES excludes /data" "/data was backed up although BACKUP_SOURCES was set"
else
    pass "BACKUP_SOURCES excludes /data"
fi
stop_container

echo
echo "=== compat: failure handling ==="

start_container failure
wait_for_start || { fail "container starts for failure test"; summary "compat"; exit 1; }
write_file /data/hello.txt "backup me"
# Point the run at a repository that does not exist. Deleting files inside the
# repository is not enough, restic happily recreates its directory structure.
fail_log="$(in_container_env RESTIC_REPOSITORY=/mnt/does-not-exist /bin/backup 2>&1)"
assert_contains "$fail_log" "Backup Failed with Status" \
    "a failing backup is reported as failed"
if in_container test -f /var/log/backup-error-last.log; then
    pass "failing backup writes backup-error-last.log"
else
    fail "failing backup writes backup-error-last.log" "file is missing"
fi
assert_eq "0" "$(snapshot_count)" \
    "a failed backup leaves no snapshot behind"
stop_container

echo
echo "=== compat: timezone ==="
# The base image already ships tzdata, so TZ works today. Pinned here so that
# neither a base image change nor a slimming effort silently breaks cron times
# for users who already rely on it.

tz_default="$(docker run --rm --entrypoint date "$IMAGE" +%Z 2>&1 | tr -d '\r')"
assert_eq "UTC" "$tz_default" \
    "the default timezone is UTC"

tz_berlin="$(docker run --rm -e TZ=Europe/Berlin --entrypoint date "$IMAGE" +%Z 2>&1 | tr -d '\r')"
if [ "$tz_berlin" = "CET" ] || [ "$tz_berlin" = "CEST" ]; then
    pass "TZ=Europe/Berlin changes the container timezone"
else
    fail "TZ=Europe/Berlin changes the container timezone" "got: ${tz_berlin}"
fi

echo
echo "=== compat: RESTIC_TAG handling ==="

start_container tag
wait_for_start || { fail "container starts for RESTIC_TAG test"; summary "compat"; exit 1; }
write_file /data/hello.txt "backup me"

# The Dockerfile declares RESTIC_TAG="", so in a normal container the variable
# is always set and an empty value means "no tag". Documented here because the
# `${RESTIC_TAG?...}` guard in backup.sh only triggers when it is truly unset.
emptytag_log="$(in_container_env RESTIC_TAG= /bin/backup 2>&1)"
assert_contains "$emptytag_log" "Backup Successful" \
    "an empty RESTIC_TAG creates an untagged backup"
assert_eq "1" "$(snapshot_count)" \
    "an empty RESTIC_TAG still produces a snapshot"

notag_log="$(in_container env -u RESTIC_TAG /bin/backup 2>&1)"
assert_contains "$notag_log" "Missing environment variable RESTIC_TAG" \
    "backup refuses to run when RESTIC_TAG is unset entirely"
assert_eq "1" "$(snapshot_count)" \
    "no extra snapshot is created when RESTIC_TAG is unset"
stop_container

summary "compat"
