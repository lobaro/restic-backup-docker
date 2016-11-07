#!/bin/sh

echo "Starting Backup"

restic backup /data --tag=${RESTIC_TAG?"Missing environment variable RESTIC_TAG"} >> /var/log/cron.log

if [ -n "${RESTIC_FORGET_ARGS}" ]; then
    echo "Forget about old snapshots based on RESTIC_FORGET_ARGS = ${RESTIC_FORGET_ARGS}"
    restic forget ${RESTIC_FORGET_ARGS}
fi
