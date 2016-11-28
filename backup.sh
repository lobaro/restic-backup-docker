#!/bin/sh

echo "Starting Backup" >> /var/log/cron.log

restic backup /data --tag=${RESTIC_TAG?"Missing environment variable RESTIC_TAG"} > /var/log/backup-last.log 2>&1
rc=$?
if [[ $rc == 0 ]]; then
    echo "Backup Successfull" >> /var/log/cron.log
else
    echo "Backup Failed with Status ${rc}" >> /var/log/cron.log
    restic unlock >> /var/log/cron.log 2>&1
fi

if [ -n "${RESTIC_FORGET_ARGS}" ]; then
    echo "Forget about old snapshots based on RESTIC_FORGET_ARGS = ${RESTIC_FORGET_ARGS}" >> /var/log/cron.log
    restic forget ${RESTIC_FORGET_ARGS} >> /var/log/backup-last.log 2>&1

    if [[ $rc == 0 ]]; then
        echo "Forget Successfull" >> /var/log/cron.log
    else
        echo "Forget Failed with Status ${rc}" >> /var/log/cron.log
        restic unlock >> /var/log/cron.log 2>&1
    fi
fi
