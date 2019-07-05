FROM alpine as certs
RUN apk add --no-cache ca-certificates


FROM busybox:glibc as base
COPY --from=certs /etc/ssl/certs /etc/ssl/certs

# Get restic executable
ARG RESTIC_VERSION=0.9.5
ARG ARCH=amd64
ADD https://github.com/restic/restic/releases/download/v${RESTIC_VERSION}/restic_${RESTIC_VERSION}_linux_${ARCH}.bz2 /
RUN bzip2 -d restic_${RESTIC_VERSION}_linux_${ARCH}.bz2 \
    && mv restic_${RESTIC_VERSION}_linux_${ARCH} /bin/restic \
    && chmod +x /bin/restic \
    && mkdir -p /mnt/restic /var/spool/cron/crontabs /var/log \
    && /var/log/cron.log


ENV RESTIC_REPOSITORY=/mnt/restic
ENV RESTIC_PASSWORD=""
ENV RESTIC_TAG=""
ENV NFS_TARGET=""
# By default backup every 6 hours
ENV BACKUP_CRON="0 */6 * * *"
ENV RESTIC_FORGET_ARGS=""
ENV RESTIC_JOB_ARGS=""

# /data is the dir where you have to put the data to be backed up
VOLUME /data

COPY backup.sh /bin/backup
COPY entry.sh /entry.sh


WORKDIR "/"
ENTRYPOINT ["/entry.sh"]
CMD ["tail","-fn0" "/var/log/cron.log"]

FROM busybox:glibc as rclone

ARG RCLONE_VERSION=current
ARG ARCH=amd64
# install rclone
ADD https://downloads.rclone.org/rclone-${RCLONE_VERSION}-linux-${ARCH}.zip /
RUN unzip rclone-${RCLONE_VERSION}-linux-${ARCH}.zip && \
    mv rclone-*-linux-${ARCH}/rclone /bin/rclone && \
    chmod 755 /bin/rclone && \
    rm rclone-${RCLONE_VERSION}-linux-${ARCH}.zip && \
    rm -rf rclone-*-linux-${ARCH}

ENV RESTIC_REPOSITORY=""
ENV RESTIC_PASSWORD=""
ENV RESTIC_TAG=""
ENV NFS_TARGET=""
ENV BACKUP_CRON="0 */6 * * *"
ENV RESTIC_FORGET_ARGS=""
ENV RESTIC_JOB_ARGS=""


COPY --from=base /mnt/restic /mnt/restic
COPY --from=base /var/spool/cron/crontabs /var/spool/cron/crontabs
COPY --from=base /var/log /var/log
COPY --from=base /var/log/cron.log /var/log/cron.log
COPY --from=base /etc/ssl/certs /etc/ssl/certs
COPY --from=base /bin/restic /bin/restic
COPY --from=base /bin/backup /bin/backup
COPY --from=base /entry.sh /entry.sh

WORKDIR "/"
ENTRYPOINT ["/entry.sh"]
CMD ["tail","-fn0" "/var/log/cron.log"]