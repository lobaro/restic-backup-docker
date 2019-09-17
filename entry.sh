#!bin/bash

echo "Starting container ..."

RESTIC_CMD=restic

if [ -n "${ROOT_CERT}" ]; then
	RESTIC_CMD="${RESTIC_CMD} --cert ${ROOT_CERT}"
fi

if [ -n "${NFS_TARGET}" ]; then
    echo "Mounting NFS based on NFS_TARGET: ${NFS_TARGET}"
    mount -o nolock -v ${NFS_TARGET} /mnt/restic
fi

if grep -q 'sftp:' $RESTIC_REPOSITORY; then
        host_regex='^sftp:[^\s]+@(.+):(.+)$'
        [[ $RESTIC_REPOSITORY =~ $host_regex ]]

        # Test whether the path exists on the remote repository. If not then create it.
        if ssh ${BASH_REMATCH[1]} stat ${BASH_REMATCH[2]} \> /dev/null 2\>\&1; then
                echo "Successfully found Restic repository '${RESTIC_REPOSITORY}'."
            else
                echo "Restic repository '${RESTIC_REPOSITORY}' does not exist. Running restic init."
                restic init | true
        fi
    else
        restic snapshots &>/dev/null
        status=$?
        echo "Check Repo status $status"

        if [ $status != 0 ]; then
            echo "Restic repository '${RESTIC_REPOSITORY}' does not exist. Running restic init."
            restic init

            init_status=$?
            echo "Repo init status $init_status"

            if [ $init_status != 0 ]; then
                echo "Failed to init the repository: '${RESTIC_REPOSITORY}'"
                exit 1
            fi
        fi
fi

echo "Setup backup cron job with cron expression BACKUP_CRON: ${BACKUP_CRON}"
echo "${BACKUP_CRON} /bin/backup >> /var/log/cron.log 2>&1" > /var/spool/cron/crontabs/root

# Make sure the file exists before we start tail
touch /var/log/cron.log

# start the cron deamon
crond

echo "Container started."

exec "$@"