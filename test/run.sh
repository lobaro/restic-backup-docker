#!/usr/bin/env bash
# Entry point for the test suites.
#
#   bash test/run.sh                 build the image and run every suite
#   bash test/run.sh --no-build      reuse an already built $IMAGE
#   bash test/run.sh --suite compat  run a single suite (compat|features|structure)
#   bash test/run.sh --sabotage      self test: break backup.sh on a throwaway
#                                    copy of the tree and prove the suite fails
#
# Requires bash and docker. container-structure-test is optional: without a
# local install the structure suite runs through the official tool image.

set -u

# Windows/Git-Bash: MSYS mangles POSIX-looking arguments on their way to the
# docker daemon, which breaks `docker exec` and `--config /test/structure.yml`.
# lib.sh exports the same two variables for the suites that source it; run.sh
# calls docker itself and starts the suites as separate processes, so it needs
# them as well. Both are ignored on Linux and macOS.
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL='*'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
IMAGE="${IMAGE:-restic-backup-docker:test}"
export IMAGE
# Pinned by digest-free tag on purpose: the structure test tool is only used to
# read the image under test, a floating tag cannot affect the product.
STRUCTURE_TEST_IMAGE="${STRUCTURE_TEST_IMAGE:-gcr.io/gcp-runtimes/container-structure-test:latest}"

BUILD=1
SABOTAGE=0
ONLY_SUITE=""

while [ $# -gt 0 ]; do
    case "$1" in
        --no-build) BUILD=0 ;;
        --sabotage) SABOTAGE=1 ;;
        --suite)
            # A missing value, or a following flag, must not be taken as one.
            case "${2:-}" in
                ""|-*) echo "--suite requires a value (compat|features|structure)" >&2; exit 2 ;;
            esac
            ONLY_SUITE="$2"; shift ;;
        --suite=*)
            ONLY_SUITE="${1#--suite=}"
            [ -n "$ONLY_SUITE" ] || { echo "--suite requires a value (compat|features|structure)" >&2; exit 2; } ;;
        -h|--help) sed -n '2,/^$/{/^#/p;}' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
    shift
done

if ! docker info >/dev/null 2>&1; then
    echo "docker is not available, cannot run the test suite" >&2
    exit 2
fi

# Docker on Windows does not understand the /c/... paths Git-Bash produces,
# so build contexts are translated when cygpath is around. No-op elsewhere.
host_path() {
    if command -v cygpath >/dev/null 2>&1; then
        cygpath -w "$1"
    else
        printf '%s' "$1"
    fi
}

build_image() {
    local context tag
    context="$(host_path "$1")"
    tag="$2"
    echo ">>> building ${tag}"
    if ! docker build --quiet -t "$tag" "$context" >/dev/null; then
        echo "image build failed" >&2
        return 1
    fi
}

# --sabotage proves the suite has teeth: it breaks the backup call on a copy of
# the tree and expects the compat suite to go red. If this mode ever passes,
# the tests are not actually testing anything.
if [ "$SABOTAGE" -eq 1 ]; then
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"; docker rmi -f restic-backup-docker:sabotage >/dev/null 2>&1 || true' EXIT
    tar -c -C "$ROOT_DIR" --exclude=.git --exclude=.intent . | tar -x -C "$tmp"
    # Silently turn the backup into a no-op, the nastiest kind of regression.
    # No `sed -i`: its argument differs between GNU and BSD (macOS) sed.
    sed 's|^restic backup |true |' "$tmp/backup.sh" > "$tmp/backup.sh.new" \
        && mv "$tmp/backup.sh.new" "$tmp/backup.sh"
    # mv keeps the mode of the new file (644); Dockerfile COPY has no chmod.
    chmod +x "$tmp/backup.sh"
    if ! grep -q '^true ' "$tmp/backup.sh"; then
        echo "sabotage patch did not apply, backup.sh changed shape" >&2
        exit 2
    fi
    if [ ! -x "$tmp/backup.sh" ]; then
        echo "SABOTAGE CHECK INVALID: sabotaged backup.sh is not executable" >&2
        exit 2
    fi
    build_image "$tmp" restic-backup-docker:sabotage || exit 2
    echo ">>> running compat suite against the sabotaged image (failure expected)"
    sabotage_log="${tmp}/compat.log"
    if IMAGE=restic-backup-docker:sabotage bash "${SCRIPT_DIR}/compat.sh" > "$sabotage_log" 2>&1; then
        cat "$sabotage_log"
        echo
        echo "SABOTAGE CHECK FAILED: the compat suite passed on a broken image" >&2
        exit 1
    fi
    cat "$sabotage_log"
    # Red for the wrong reason (e.g. a non-executable /bin/backup) proves nothing.
    if grep -qi 'permission denied' "$sabotage_log"; then
        echo "SABOTAGE CHECK INVALID: log contains 'permission denied', suite failed for the wrong reason" >&2
        exit 2
    fi
    # Any red test would do for "it failed"; a broken test environment is red too.
    # Demand the assertions that are about the backup itself.
    missing=0
    for name in \
        "exactly one snapshot exists after one backup" \
        "a second backup adds a second snapshot"; do
        if ! grep -qF "FAIL ${name}" "$sabotage_log"; then
            echo "SABOTAGE CHECK FAILED: expected assertion did not fail: ${name}" >&2
            missing=1
        fi
    done
    [ "$missing" -eq 0 ] || exit 1
    echo
    echo "sabotage check ok: the compat suite detects a broken backup"
    exit 0
fi

if [ "$BUILD" -eq 1 ]; then
    build_image "$ROOT_DIR" "$IMAGE" || exit 2
fi

rc=0

run_structure() {
    echo
    echo ">>> structure suite"
    if command -v container-structure-test >/dev/null 2>&1; then
        container-structure-test test --image "$IMAGE" --config "${SCRIPT_DIR}/structure.yml" || rc=1
    else
        # Not installed locally: fall back to the official image. It needs the
        # docker socket because it inspects and runs the image under test.
        echo "container-structure-test not installed, using the official image"
        # The config file is copied in with `docker cp` instead of bind mounted,
        # so this also works when DOCKER_HOST points at a remote daemon.
        local tool_cid tool_rc
        tool_cid="$(docker create \
            -v //var/run/docker.sock:/var/run/docker.sock \
            "$STRUCTURE_TEST_IMAGE" \
            test --image "$IMAGE" --config /structure.yml)" || { rc=1; return; }
        docker cp "$(host_path "${SCRIPT_DIR}")/structure.yml" "${tool_cid}:/structure.yml" \
            && docker start -a "$tool_cid"
        tool_rc=$?
        docker rm -f "$tool_cid" >/dev/null 2>&1 || true
        [ "$tool_rc" -eq 0 ] || rc=1
    fi
}

run_suite() {
    echo
    echo ">>> $1 suite"
    bash "${SCRIPT_DIR}/$1.sh" || rc=1
}

case "$ONLY_SUITE" in
    "")          run_structure; run_suite compat; run_suite features ;;
    structure)   run_structure ;;
    compat)      run_suite compat ;;
    features)    run_suite features ;;
    *) echo "unknown suite: ${ONLY_SUITE}" >&2; exit 2 ;;
esac

echo
if [ "$rc" -eq 0 ]; then
    echo "all suites passed"
else
    echo "at least one suite failed"
fi
exit "$rc"
