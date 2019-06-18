#!bin/sh
set -e
rclone serve restic --addr :8080 -v ${RESTIC_REPOSITORY}