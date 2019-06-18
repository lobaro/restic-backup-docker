#!bin/sh
set -e

restic ${RESTIC_JOB_ARGS} \
    -o rclone.program=rclone \
    -o rclone.args=${RCLONE_ARGS} init