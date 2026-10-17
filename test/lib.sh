#!/usr/bin/env bash
# Shared helpers for the restic-backup-docker test suites.
#
# Deliberately dependency-free: bash + docker only. No test framework, no
# host-side bind mounts (files are moved with `docker cp`) so the suites behave
# identically on Linux CI runners, macOS and Windows/Git-Bash.

IMAGE="${IMAGE:-restic-backup-docker:test}"

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
FAILED_TESTS=()
SKIPPED_TESTS=()

_c_red=''
_c_green=''
_c_yellow=''
_c_reset=''
if [ -t 1 ]; then
    _c_red=$'\033[31m'
    _c_green=$'\033[32m'
    _c_yellow=$'\033[33m'
    _c_reset=$'\033[0m'
fi

log() { echo "    $*"; }

pass() {
    PASS_COUNT=$((PASS_COUNT + 1))
    echo "${_c_green}PASS${_c_reset} $1"
}

fail() {
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAILED_TESTS+=("$1")
    echo "${_c_red}FAIL${_c_reset} $1"
    if [ -n "${2:-}" ]; then
        echo "$2" | sed 's/^/       /'
    fi
}

skip() {
    SKIP_COUNT=$((SKIP_COUNT + 1))
    SKIPPED_TESTS+=("$1")
    echo "${_c_yellow}SKIP${_c_reset} $1 (${2:-not applicable})"
}

# summary <suite name> -> exit code 0 when nothing failed
summary() {
    echo
    echo "--- $1: ${PASS_COUNT} passed, ${FAIL_COUNT} failed, ${SKIP_COUNT} skipped ---"
    if [ ${#FAILED_TESTS[@]} -gt 0 ]; then
        echo "Failed:"
        printf '  - %s\n' "${FAILED_TESTS[@]}"
    fi
    if [ ${#SKIPPED_TESTS[@]} -gt 0 ]; then
        echo "Skipped:"
        printf '  - %s\n' "${SKIPPED_TESTS[@]}"
    fi
    [ "${FAIL_COUNT}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# assertions
# ---------------------------------------------------------------------------

assert_eq() {
    local expected="$1" actual="$2" name="$3"
    if [ "$expected" = "$actual" ]; then
        pass "$name"
    else
        fail "$name" "expected: ${expected}
actual:   ${actual}"
    fi
}

assert_contains() {
    local haystack="$1" needle="$2" name="$3"
    case "$haystack" in
        *"$needle"*) pass "$name" ;;
        *) fail "$name" "expected to contain: ${needle}
actual:
$(echo "$haystack" | tail -n 25)" ;;
    esac
}

assert_not_contains() {
    local haystack="$1" needle="$2" name="$3"
    case "$haystack" in
        *"$needle"*) fail "$name" "unexpectedly contains: ${needle}" ;;
        *) pass "$name" ;;
    esac
}

# ---------------------------------------------------------------------------
# container helpers
#
# Every test gets its own throwaway container. The restic repository lives
# inside the container at the image default (/mnt/restic), so no host paths are
# involved and tests cannot pollute each other.
# ---------------------------------------------------------------------------

CONTAINER=""

# start_container <name suffix> [extra docker run args...]
# Starts the image with a cron expression far in the future so that the only
# backup that ever runs is the one a test triggers explicitly.
start_container() {
    local suffix="$1"
    shift
    CONTAINER="rbd-test-${suffix}-$$"
    docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
    docker run -d --name "$CONTAINER" \
        -e RESTIC_PASSWORD=testpassword \
        -e RESTIC_TAG=testtag \
        -e "BACKUP_CRON=0 0 31 2 *" \
        "$@" \
        "$IMAGE" >/dev/null
}

stop_container() {
    [ -n "$CONTAINER" ] || return 0
    docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
    CONTAINER=""
}

# wait_for_start -> fails if entry.sh did not finish within the timeout
wait_for_start() {
    local waited=0
    while [ "$waited" -lt 60 ]; do
        waited=$((waited + 1))
        if docker logs "$CONTAINER" 2>&1 | grep -q "Container started."; then
            return 0
        fi
        if [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null)" != "true" ]; then
            echo "container exited early:"
            docker logs "$CONTAINER" 2>&1 | sed 's/^/       /'
            return 1
        fi
        sleep 1
    done
    echo "timeout waiting for container start:"
    docker logs "$CONTAINER" 2>&1 | sed 's/^/       /'
    return 1
}

# in_container <cmd...> - run a command inside the running test container
in_container() {
    docker exec "$CONTAINER" "$@"
}

# in_container_env <KEY=VALUE> <cmd...> - run with one overridden variable
in_container_env() {
    local env_pair="$1"
    shift
    docker exec -e "$env_pair" "$CONTAINER" "$@"
}

# write_file <path in container> <content>
write_file() {
    local path="$1" content="$2"
    local dir
    dir="$(dirname "$path")"
    docker exec "$CONTAINER" mkdir -p "$dir"
    printf '%s' "$content" | docker exec -i "$CONTAINER" sh -c "cat > '$path'"
}

# snapshot_count -> number of snapshots in the repository
snapshot_count() {
    docker exec "$CONTAINER" sh -c \
        'restic snapshots --json 2>/dev/null | grep -o "\"short_id\"" | wc -l' | tr -d ' \r'
}

# ---------------------------------------------------------------------------
# feature gating
#
# A feature test only runs when the image actually ships the feature. That way
# this suite already covers the currently open pull requests: once such a PR is
# rebased onto master its feature is detected and its tests start running,
# without the PR author having to write any test code.
#
# test/required-features.txt lists features that MUST be present. A feature
# listed there that is not detected turns the skip into a hard failure, so a
# merged feature cannot silently disappear from the image again.
# ---------------------------------------------------------------------------

REQUIRED_FEATURES_FILE="${REQUIRED_FEATURES_FILE:-$(dirname "${BASH_SOURCE[0]}")/required-features.txt}"

feature_is_required() {
    local feature="$1"
    [ -f "$REQUIRED_FEATURES_FILE" ] || return 1
    grep -v '^[[:space:]]*#' "$REQUIRED_FEATURES_FILE" 2>/dev/null \
        | grep -qx "[[:space:]]*${feature}[[:space:]]*"
}

# has_feature <name> - detection runs against the built image, not the source
has_feature() {
    case "$1" in
        stream)
            docker run --rm --entrypoint sh "$IMAGE" -c \
                'grep -q RESTIC_STREAM /bin/backup' >/dev/null 2>&1
            ;;
        docker-cli)
            docker run --rm --entrypoint sh "$IMAGE" -c \
                'command -v docker' >/dev/null 2>&1
            ;;
        bash)
            docker run --rm --entrypoint sh "$IMAGE" -c \
                'command -v bash' >/dev/null 2>&1
            ;;
        msmtp)
            docker run --rm --entrypoint sh "$IMAGE" -c \
                'command -v msmtp' >/dev/null 2>&1
            ;;
        *)
            echo "unknown feature: $1" >&2
            return 1
            ;;
    esac
}

# require_feature <name> <pull request reference>
# Returns 0 when the feature tests should run. Otherwise records a skip, or a
# failure when the feature is listed in required-features.txt.
require_feature() {
    local feature="$1" ref="$2"
    if has_feature "$feature"; then
        return 0
    fi
    if feature_is_required "$feature"; then
        fail "feature '${feature}'" \
            "listed in $(basename "$REQUIRED_FEATURES_FILE") but not present in the image"
    else
        skip "feature '${feature}'" "not in image yet, see ${ref}"
    fi
    return 1
}
