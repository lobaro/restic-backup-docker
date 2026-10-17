#!/usr/bin/env bash
# Feature suite.
#
# Each block is guarded by a detection check against the built image. On master
# every block reports SKIP. As soon as the corresponding pull request is rebased
# onto master, the feature is detected and its tests start running - the PR
# author does not have to write test code for the basics.
#
# After merging a feature, add its gate name to test/required-features.txt.
# From then on a missing feature is a failure instead of a skip.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test/lib.sh
. "${SCRIPT_DIR}/lib.sh"

trap stop_container EXIT

echo "=== feature: stream backup (RESTIC_STREAM) ==="
# Pull request #109 - back up the output of a command via `restic backup --stdin`.

if require_feature stream "PR #109"; then
    start_container stream \
        -e RESTIC_STREAM=1 \
        -e "RESTIC_STREAM_CMD=echo hello-stream" \
        -e RESTIC_STREAM_FILENAME=stream.txt
    if wait_for_start; then
        stream_log="$(in_container /bin/backup 2>&1)"
        assert_contains "$stream_log" "Backup Successful" \
            "stream backup succeeds"
        assert_eq "1" "$(snapshot_count)" \
            "stream backup creates exactly one snapshot"
        in_container restic restore latest --target /tmp/restore >/dev/null 2>&1
        restored="$(in_container sh -c 'cat /tmp/restore/stream.txt 2>/dev/null' 2>&1)"
        assert_eq "hello-stream" "$(echo "$restored" | tr -d '\r')" \
            "stream content is stored under RESTIC_STREAM_FILENAME"
    else
        fail "stream backup container starts"
    fi
    stop_container

    # A half-configured stream must not look like a successful backup.
    start_container stream-misconfigured -e RESTIC_STREAM=1
    if wait_for_start; then
        misconfig_log="$(in_container /bin/backup 2>&1)"
        assert_not_contains "$misconfig_log" "Backup Successful" \
            "incomplete stream configuration does not report success"
        assert_eq "0" "$(snapshot_count)" \
            "incomplete stream configuration creates no snapshot"
    else
        fail "stream misconfiguration container starts"
    fi
    stop_container

    # The classic path must keep working while the feature is available.
    start_container stream-disabled
    if wait_for_start; then
        write_file /data/hello.txt "backup me"
        in_container /bin/backup >/dev/null 2>&1
        assert_eq "1" "$(snapshot_count)" \
            "file backup still works while the stream feature is present"
    else
        fail "stream-disabled container starts"
    fi
    stop_container
fi

echo
echo "=== feature: docker cli ==="
# Pull request #99 - talk to the host docker daemon from hooks.

if require_feature docker-cli "PR #99"; then
    docker_version="$(docker run --rm --entrypoint docker "$IMAGE" --version 2>&1)"
    assert_contains "$docker_version" "Docker version" \
        "docker cli is usable inside the image"
fi

echo
echo "=== feature: bash ==="
# Pull request #99 - allow bash syntax in pre/post hooks.

if require_feature bash "PR #99"; then
    start_container bash-hooks
    if wait_for_start; then
        write_file /hooks/pre-backup.sh '#!/bin/bash
arr=(one two)
if [[ "${arr[1]}" == "two" ]]; then echo "BASH-HOOK-RAN"; fi
'
        in_container chmod +x /hooks/pre-backup.sh
        write_file /data/hello.txt "backup me"
        bash_log="$(in_container /bin/backup 2>&1)"
        assert_contains "$bash_log" "BASH-HOOK-RAN" \
            "a hook with a bash shebang and bash syntax runs"
    else
        fail "bash hook container starts"
    fi
    stop_container
fi

echo
echo "=== feature: msmtp mail relay ==="
# Pull request #84 - send notification mails through msmtp.

if require_feature msmtp "PR #84"; then
    sendmail_target="$(docker run --rm --entrypoint sh "$IMAGE" -c \
        'readlink -f /usr/sbin/sendmail' 2>&1 | tr -d '\r')"
    assert_contains "$sendmail_target" "msmtp" \
        "sendmail is provided by msmtp"

    start_container msmtp-config
    if wait_for_start; then
        write_file /config/msmtprc 'defaults
account default
host localhost
'
        in_container /entry.sh true >/dev/null 2>&1
        if in_container test -f /etc/msmtprc; then
            pass "msmtp config from /config is copied to /etc/msmtprc"
            mode="$(in_container stat -c '%a' /etc/msmtprc 2>&1 | tr -d '\r')"
            assert_eq "600" "$mode" \
                "copied msmtp config is not world readable"
        else
            fail "msmtp config from /config is copied to /etc/msmtprc" "file is missing"
        fi
    else
        fail "msmtp config container starts"
    fi
    stop_container

    # Users who configured mail before msmtp existed must not lose their backups.
    start_container msmtp-missing-config \
        -e "MAILX_ARGS=-r from@example.com -s subject to@example.com"
    if wait_for_start; then
        write_file /data/hello.txt "backup me"
        mail_log="$(in_container /bin/backup 2>&1)"
        assert_contains "$mail_log" "Backup Successful" \
            "backup succeeds with MAILX_ARGS set but no msmtp config"
        assert_eq "1" "$(snapshot_count)" \
            "snapshot is created even when the mail relay is unconfigured"
    else
        fail "msmtp missing-config container starts"
    fi
    stop_container
fi

summary "features"
