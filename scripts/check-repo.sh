#!bin/sh
set -e

[ ! -f "$RESTIC_REPOSITORY/config" ] && exit 0 || exit 1