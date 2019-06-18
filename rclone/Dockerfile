FROM alpine

ARG RCLONE_VERSION=current
ARG ARCH=amd64

COPY entry.sh /entry.sh

# install rclone
ADD https://downloads.rclone.org/rclone-${RCLONE_VERSION}-linux-${ARCH}.zip /
RUN unzip rclone-${RCLONE_VERSION}-linux-${ARCH}.zip && \
    mv rclone-*-linux-${ARCH}/rclone /bin/rclone && \
    chmod 755 /bin/rclone && \
    rm rclone-${RCLONE_VERSION}-linux-${ARCH}.zip && \
    chmod +x /entry.sh



WORKDIR "/"
ENTRYPOINT ["/entry.sh"]

CMD ["serve"]