FROM --platform=$TARGETPLATFORM docker.io/alpine:latest as rclone
ARG TARGETPLATFORM

RUN apk add wget

# Get rclone executable
RUN if [ "$TARGETPLATFORM" = "linux/amd64" ]; then \
        wget https://downloads.rclone.org/rclone-current-linux-amd64.zip && unzip rclone-current-linux-amd64.zip && mv rclone-*-linux-amd64/rclone /bin/rclone && chmod +x /bin/rclone; \
    elif [ "$TARGETPLATFORM" = "linux/arm64" ]; then \
        wget https://downloads.rclone.org/rclone-current-linux-arm64.zip && unzip rclone-current-linux-arm64.zip && mv rclone-*-linux-arm64/rclone /bin/rclone && chmod +x /bin/rclone; \
    elif [ "$TARGETPLATFORM" = "linux/arm/v7" ]; then \
        wget https://downloads.rclone.org/rclone-current-linux-arm-v7.zip && unzip rclone-current-linux-arm-v7.zip && mv rclone-*-linux-arm-v7/rclone /bin/rclone && chmod +x /bin/rclone; \
    fi


FROM docker.io/restic/restic:0.18.0

RUN apk add --update --no-cache bash curl docker-cli mailx shadow tzdata

COPY --from=rclone /bin/rclone /bin/rclone

RUN \
    mkdir -p /mnt/restic /var/spool/cron/crontabs /var/log; \
    touch /var/log/cron.log;

ENV RESTIC_REPOSITORY=/mnt/restic
ENV RESTIC_PASSWORD=""
ENV RESTIC_TAG=""
ENV NFS_TARGET=""
ENV TZ="UTC"
ENV BACKUP_CRON="0 */6 * * *"
ENV CHECK_CRON=""
ENV RESTIC_INIT_ARGS=""
ENV RESTIC_FORGET_ARGS=""
ENV RESTIC_JOB_ARGS=""
ENV RESTIC_DATA_SUBSET=""
ENV MAILX_ARGS=""
ENV OS_AUTH_URL=""
ENV OS_PROJECT_ID=""
ENV OS_PROJECT_NAME=""
ENV OS_USER_DOMAIN_NAME="Default"
ENV OS_PROJECT_DOMAIN_ID="default"
ENV OS_USERNAME=""
ENV OS_PASSWORD=""
ENV OS_REGION_NAME=""
ENV OS_INTERFACE=""
ENV OS_IDENTITY_API_VERSION=3
ENV BACKUP_SOURCES=""

# openshift fix
RUN mkdir /.cache && \
    chgrp -R 0 /.cache && \
    chmod -R g=u /.cache && \
    chgrp -R 0 /mnt && \
    chmod -R g=u /mnt && \
    chgrp -R 0 /var/spool/cron/crontabs/root && \
    chmod -R g=u /var/spool/cron/crontabs/root && \
    chgrp -R 0 /var/log/cron.log && \
    chmod -R g=u /var/log/cron.log

# /data is the dir where you have to put the data to be backed up
VOLUME /data

COPY backup.sh /bin/backup
COPY check.sh /bin/check
COPY entry.sh /entry.sh

ENTRYPOINT ["/entry.sh"]
CMD ["tail","-fn0","/var/log/cron.log"]
