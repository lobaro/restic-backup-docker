FROM alpine:3.6
MAINTAINER info@lobaro.com

RUN apk add --no-cache nfs-utils openssh fuse
COPY restic /usr/local/bin/

RUN mkdir /mnt/restic

ENV RESTIC_REPOSITORY=/mnt/restic
ENV RESTIC_PASSWORD=""
ENV RESTIC_TAG=""
ENV NFS_TARGET=""
# By default backup every 6 hours
ENV BACKUP_CRON="* */6 * * *"
ENV RESTIC_FORGET_ARGS=""

# /data is the dir where you have to put the data to be backed up
VOLUME /data

COPY backup.sh /bin/backup
RUN chmod +x /bin/backup

COPY entry.sh /entry.sh

RUN touch /var/log/cron.log

WORKDIR "/"

#ENTRYPOINT ["ls"]
ENTRYPOINT ["/entry.sh"]

