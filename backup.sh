#!/bin/sh

echo "Starting Backup"

# Do not save full backup log to logfile but to backup-last.log
restic backup /data --tag=${RESTIC_TAG?"Missing environment variable RESTIC_TAG"} > /var/log/backup-last.log 2>&1
rc=$?
echo "Finished backup at $(date)" >> /var/log/backup-last.log
if [[ $rc == 0 ]]; then
    echo "Backup Successfull" 
else
    echo "Backup Failed with Status ${rc}"
    restic unlock
fi

if [ -n "${RESTIC_FORGET_ARGS}" ]; then
    echo "Forget about old snapshots based on RESTIC_FORGET_ARGS = ${RESTIC_FORGET_ARGS}"
    restic forget ${RESTIC_FORGET_ARGS} >> /var/log/backup-last.log 2>&1
    rc=$?
    echo "Finished forget at $(date)" >> /var/log/backup-last.log
    if [[ $rc == 0 ]]; then
        echo "Forget Successfull"
    else
        echo "Forget Failed with Status ${rc}"
        restic unlock
    fi
fi
