FROM alpine as certs
RUN apk add --no-cache ca-certificates

# Get restic executable
ENV RESTIC_VERSION=0.9.5
ADD https://github.com/restic/restic/releases/download/v${RESTIC_VERSION}/restic_${RESTIC_VERSION}_linux_amd64.bz2 /
RUN bzip2 -d restic_${RESTIC_VERSION}_linux_amd64.bz2 && mv restic_${RESTIC_VERSION}_linux_amd64 /bin/restic && chmod +x /bin/restic

FROM alpine as rclone

# Get rclone executable
ADD https://downloads.rclone.org/rclone-current-linux-amd64.zip /
RUN unzip rclone-current-linux-amd64.zip && mv rclone-*-linux-amd64/rclone /bin/rclone && chmod +x /bin/rclone

FROM busybox:glibc

COPY --from=certs /etc/ssl/certs /etc/ssl/certs
COPY --from=certs /bin/restic /bin/restic
COPY --from=rclone /bin/rclone /bin/rclone

RUN \
    mkdir -p /mnt/restic /var/spool/cron/crontabs /var/log; \
    touch /var/log/cron.log;

ENV \
    RESTIC_REPOSITORY=/mnt/restic \
    RESTIC_PASSWORD="" \
    RESTIC_TAG="" \
    NFS_TARGET="" \
    BACKUP_CRON="0 */6 * * *" \
    RESTIC_FORGET_ARGS="" \
    RESTIC_JOB_ARGS=""

# /data is the dir where you have to put the data to be backed up
VOLUME /data

COPY backup.sh /bin/backup
COPY entry.sh /entry.sh


WORKDIR "/"

ENTRYPOINT ["/entry.sh"]
CMD ["tail","-fn0","/var/log/cron.log"]