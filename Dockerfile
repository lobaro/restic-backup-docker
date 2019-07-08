FROM alpine as certs
RUN apk add --no-cache ca-certificates
ARG BUILD_DATE
ARG VCS_REF
ARG VERSION
LABEL maintainer="Stefan Bratic" \
      org.label-schema.build-date=$BUILD_DATE \
      org.label-schema.name="restic-backup-docker" \
      org.label-schema.description="Automatic restic backup using docker" \
      org.label-schema.url="https://github.com/Cobrijani/restic-backup-docker" \
      org.label-schema.vcs-ref=$VCS_REF \
      org.label-schema.vcs-url="https://github.com/Cobrijani/restic-backup-docker.git" \
      org.label-schema.vendor="Cobrijani" \
      org.label-schema.version=$VERSION \
      org.label-schema.schema-version="1.0"


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
    && touch /var/log/cron.log


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
CMD ["tail","-fn0","/var/log/cron.log"]