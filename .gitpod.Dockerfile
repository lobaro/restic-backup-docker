FROM gitpod/workspace-full:latest

USER root

RUN echo "deb https://apt.dockerproject.org/repo debian-jessie main" | tee /etc/apt/sources.list.d/docker.list && \
    # apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 58118E89F3A912897C070ADBF76221572C52609D && \
    apt-get update && \
    apt-get install -y --no-install-recommends --allow-unauthenticated docker-engine && \
    echo "gitpod ALL=NOPASSWD: /usr/bin/docker" >> /etc/sudoers && \
    echo "gitpod ALL=NOPASSWD: /usr/local/bin/docker-compose" >> /etc/sudoers && \
    echo 'Defaults  env_keep += "HOME"' >> /etc/sudoers && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*