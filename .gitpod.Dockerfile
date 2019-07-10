FROM gitpod/workspace-full:latest

USER root

<<<<<<< HEAD
RUN echo "deb https://apt.dockerproject.org/repo debian-jessie main" | tee /etc/apt/sources.list.d/docker.list && \
    # apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 58118E89F3A912897C070ADBF76221572C52609D && \
    apt-get update && \
    apt-get install -y --no-install-recommends --allow-unauthenticated docker-engine && \
    echo "gitpod ALL=NOPASSWD: /usr/bin/docker" >> /etc/sudoers && \
    echo "gitpod ALL=NOPASSWD: /usr/local/bin/docker-compose" >> /etc/sudoers && \
    echo 'Defaults  env_keep += "HOME"' >> /etc/sudoers && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*
=======
RUN apt-get -y update \
    && apt-get -y install \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg-agent \
    software-properties-common \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add - \
    && apt-key fingerprint 0EBFCD88 \
    && add-apt-repository -y \
   "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
   $(lsb_release -cs) \
   stable" \
   && apt-get -y update \
   && apt-get -y install docker-ce docker-ce-cli containerd.io \
   && groupadd docker \
   && usermod -aG docker gitpod
>>>>>>> 185ce43ec51b730c08f8c33942b353df1176b3a6
