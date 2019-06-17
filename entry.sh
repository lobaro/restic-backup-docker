#!bin/sh
set -e

echo "Starting container ..."

RESTIC_CMD=restic

if [ -n "${ROOT_CERT}" ]; then
	RESTIC_CMD="${RESTIC_CMD} --cert ${ROOT_CERT}"
fi

if [ -n "${NFS_TARGET}" ]; then
    echo "Mounting NFS based on NFS_TARGET: ${NFS_TARGET}"
    mount -o nolock -v ${NFS_TARGET} /mnt/restic
fi

restic -r ${RESTIC_REPOSITORY} \
${RESTIC_JOB_ARGS} \
-o rclone.program=rclone \
-o rclone.args=${RCLONE_ARGS} snapshots > /dev/null >> ${lastLogfile} 2>&1
test=$?

if [ [test != 0] ]; then
    echo "Restic repository '${RESTIC_REPOSITORY}' does not exists. Running restic init."
    restic -r ${RESTIC_REPOSITORY} \
     ${RESTIC_JOB_ARGS} \
    -o rclone.program=rclone \
    -o rclone.args=${RCLONE_ARGS} init
fi

echo "Setup backup cron job with cron expression BACKUP_CRON: ${BACKUP_CRON}"
echo "${BACKUP_CRON} /bin/backup >> /var/log/cron.log 2>&1" > /var/spool/cron/crontabs/root

# Make sure the file exists before we start tail
touch /var/log/cron.log

# start the cron deamon
crond

echo "Container started."

tail -fn0 /var/log/cron.log
