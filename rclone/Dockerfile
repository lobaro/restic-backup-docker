FROM cobrijani/restic-backup:latest

ARG RCLONE_VERSION=current
ARG ARCH=amd64
# install rclone
ADD https://downloads.rclone.org/rclone-${RCLONE_VERSION}-linux-${ARCH}.zip /
RUN unzip rclone-${RCLONE_VERSION}-linux-${ARCH}.zip && \
    mv rclone-*-linux-${ARCH}/rclone /bin/rclone && \
    chmod 755 /bin/rclone && \
    rm rclone-${RCLONE_VERSION}-linux-${ARCH}.zip && \
    rm -rf rclone-*-linux-${ARCH}