#!/bin/sh

echo "Starting Backup"

restic backup /data --tag=${RESTIC_TAG?"Missing environment variable RESTIC_TAG"} >> /var/log/cron.log


