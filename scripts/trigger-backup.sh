#!bin/sh
set -e

restic backup /data \
 ${RESTIC_JOB_ARGS} \
 --tag=${RESTIC_TAG?"Missing environment variable RESTIC_TAG"}