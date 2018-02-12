FROM alpine as certs
RUN apk update && apk add ca-certificates


FROM busybox:glibc

COPY --from=certs /etc/ssl/certs /etc/ssl/certs

# Get restic executable
ENV RESTIC_VERION=0.8.1
ADD https://github.com/restic/restic/releases/download/v${RESTIC_VERION}/restic_${RESTIC_VERION}_linux_amd64.bz2 /
RUN bzip2 -d restic_${RESTIC_VERION}_linux_amd64.bz2 && mv restic_${RESTIC_VERION}_linux_amd64 /bin/restic && chmod +x /bin/restic

RUN mkdir -p /mnt/restic /var/spool/cron/crontabs /var/log

ENV RESTIC_REPOSITORY=/mnt/restic
ENV RESTIC_PASSWORD=""
ENV RESTIC_TAG=""
ENV NFS_TARGET=""
# By default backup every 6 hours
ENV BACKUP_CRON="* */6 * * *"
ENV RESTIC_FORGET_ARGS=""
ENV RESTIC_JOB_ARGS=""

# /data is the dir where you have to put the data to be backed up
VOLUME /data

COPY backup.sh /bin/backup
COPY entry.sh /entry.sh

RUN touch /var/log/cron.log

WORKDIR "/"

#ENTRYPOINT ["ls"]
ENTRYPOINT ["/entry.sh"]

