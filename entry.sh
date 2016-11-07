#!bin/sh
set -e


if [ -n "${NFS_TARGET}" ]; then
    echo "Mounting NFS based on NFS_TARGET"
    mount -o nolock -v ${NFS_TARGET} /mnt/restic
fi

if [ ! -f "$RESTIC_REPOSITORY/config" ]; then
    echo "Restic repository does not exists. Running restic init."
    restic init
fi

echo "Setup backup cron job with cron expression: ${BACKUP_CRON}"
echo "${BACKUP_CRON} /bin/backup >> /var/log/cron.log 2>&1" > /var/spool/cron/crontabs/root

# start the cron deamon
crond
tail -f /var/log/cron.log
