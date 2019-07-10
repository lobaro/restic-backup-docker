FROM gitpod/workspace-full:latest

USER root

RUN apt-get -y update \
    && apt-get -y install \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg-agent \
    software-properties-common \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add - \
    && apt-key fingerprint 0EBFCD88 \
    && add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
   $(lsb_release -cs) \
   stable" \
   && apt-get -y update \
   && apt-get -y install docker-ce docker-ce-cli containerd.io \
   && groupadd docker \
   && usermod -aG docker gitpod
