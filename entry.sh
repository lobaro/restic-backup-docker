#!bin/sh
set -e

echo "Starting container ..."

if [ -n "${NFS_TARGET}" ]; then
    echo "Mounting NFS based on NFS_TARGET"
    mount -o nolock -v ${NFS_TARGET} /mnt/restic
fi

if [ ! -f "$RESTIC_REPOSITORY/config" ]; then
    echo "Restic repository does not exists. Running restic init."
    restic init | true
fi

echo "Setup backup cron job with cron expression: ${BACKUP_CRON}"
echo "${BACKUP_CRON} /bin/backup >> /var/log/cron.log 2>&1" > /var/spool/cron/crontabs/root

# Make sure the file exists before we start tail
touch /var/log/cron.log

# start the cron deamon
crond

echo "Container started."

tail -fn0 /var/log/cron.log
