FROM alpine as certs
RUN apk add --no-cache ca-certificates


FROM busybox:glibc as base

COPY --from=certs /etc/ssl/certs /etc/ssl/certs
ENV ARCH=amd64
# Get restic executable
ARG RESTIC_VERSION=0.9.5
ADD https://github.com/restic/restic/releases/download/v${RESTIC_VERSION}/restic_${RESTIC_VERSION}_linux_${ARCH}.bz2 /
RUN bzip2 -d restic_${RESTIC_VERSION}_linux_${ARCH}.bz2 && \
 mv restic_${RESTIC_VERSION}_linux_${ARCH} /bin/restic && \
 chmod +x /bin/restic

RUN mkdir -p /mnt/restic /var/spool/cron/crontabs /var/log

ENV RESTIC_REPOSITORY=/mnt/restic
ENV RESTIC_PASSWORD=""
ENV RESTIC_TAG=""
ENV NFS_TARGET=""
# By default backup every 6 hours
ENV BACKUP_CRON="0 */6 * * *"
ENV RESTIC_FORGET_ARGS=""
ENV RESTIC_JOB_ARGS=""

VOLUME /data

COPY backup.sh /bin/backup
COPY entry.sh /entry.sh

RUN touch /var/log/cron.log
WORKDIR "/"
ENTRYPOINT ["/entry.sh"]

FROM busybox:glibc as rclone

ARG RCLONE_VERSION=current

# install rclone
ADD https://downloads.rclone.org/rclone-${RCLONE_VERSION}-linux-${ARCH}.zip /
RUN unzip rclone-${RCLONE_VERSION}-linux-${ARCH}.zip && \
    mv rclone-*-linux-${ARCH}/rclone /bin/rclone && \
    chmod 755 /bin/rclone && \
    rm rclone-${RCLONE_VERSION}-linux-${ARCH}.zip

ENV RCLONE_ARGS=""

COPY --from=base /etc/ssl/certs /etc/ssl/certs
COPY --from=base /bin/restic /bin/restic
COPY backup-rclone.sh /bin/backup
COPY entry-rclone.sh /entry.sh



