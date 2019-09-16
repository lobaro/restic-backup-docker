.PHONY: build login logout deploy test install

# Project variables
PROJECT_NAME ?= restic-backup-docker
ORG_NAME ?= cobrijani
REPO_NAME ?= restic-backup

# Schema variables
SCHEMA_URL ?= "https://github.com/Cobrijani/restic-backup-docker"
SCHEMA_VERSION = "1.0"
SCHEMA_NAME = "restic-backup-docker"

VCS_URL ?= "https://github.com/Cobrijani/restic-backup-docker.git"
VENDOR ?= "Cobrijani"
DESCRIPTION ?= "Automatic restic backup using docker"

VERSION := `cat VERSION`
BUILD_DATE := `date -u +"%Y-%m-%dT%H:%M:%SZ"`
VCS_REF := `git rev-parse --short HEAD`

MAINTAINER ?= "Stefan Bratic"

DOCKER_REGISTRY ?= docker.io
DOCKER_REGISTRY_AUTH ?=
DOCKER_USER ?=
DOCKER_PASSWORD ?=

build:
	${INFO} "Building docker images..."
	@ docker build --no-cache -t $(ORG_NAME)/$(REPO_NAME) \
				 --label maintainer=$(MAINTAINER) \
				 --label org.label-schema.build-date=$(BUILD_DATE) \
				 --label org.label-schema.name=$(SCHEMA_NAME) \
				 --label org.label-schema.description=$(DESCRIPTION) \
				 --label org.label-schema.url=$(SCHEMA_URL) \
				 --label org.label-schema.vcs-ref=$(VCS_REF) \
				 --label org.label-schema.vcs-url=$(VCS_URL) \
				 --label org.label-schema.vendor=$(VENDOR) \
				 --label org.label-schema.version=$(VERSION) \
				 --label org.label-schema.schema-version=$(SCHEMA_VERSION) \
				  .
	@ docker build --no-cache -t $(ORG_NAME)/$(REPO_NAME):rclone-latest \
				 --label maintainer=$(MAINTAINER) \
				 --label org.label-schema.build-date=$(BUILD_DATE) \
				 --label org.label-schema.name=$(SCHEMA_NAME) \
				 --label org.label-schema.description=$(DESCRIPTION) \
				 --label org.label-schema.url=$(SCHEMA_URL) \
				 --label org.label-schema.vcs-ref=$(VCS_REF) \
				 --label org.label-schema.vcs-url=$(VCS_URL) \
				 --label org.label-schema.vendor=$(VENDOR) \
				 --label org.label-schema.version=$(VERSION) \
				 --label org.label-schema.schema-version=$(SCHEMA_VERSION) \
				  ./rclone
	${INFO} "Building complete"

login:
	${INFO} "Logging in to Docker registry $(DOCKER_REGISTRY)..."
	@ docker login -u $(DOCKER_USER) -p $(DOCKER_PASSWORD) $(DOCKER_REGISTRY_AUTH)
	${INFO} "Logged in to Docker registry $(DOCKER_REGISTRY)"


logout:
	${INFO} "Logging out of Docker registry $(DOCKER_REGISTRY)..."
	@ docker logout $(DOCKER_REGISTRY_AUTH)
	${INFO} "Logged out of Docker registry $(DOCKER_REGISTRY)"


deploy:
	${INFO} "Deploying images"
	@ docker push $(ORG_NAME)/$(REPO_NAME)
	@ docker push $(ORG_NAME)/$(REPO_NAME):rclone-latest
	@ docker push $(ORG_NAME)/$(REPO_NAME):$(VERSION).$(VCS_REF)
	@ docker push $(ORG_NAME)/$(REPO_NAME):rclone-$(VERSION).$(VCS_REF)
	${INFO} "Complete"

test:
	${INFO} "Testing ..."
	@ docker-compose -f docker-compose.test.yml up
	@ docker-compose -f rclone/docker-compose.test.yml up
	${INFO} "Test Complete!"

install:
	${INFO} "Installing..."
	@ docker tag $(ORG_NAME)/$(REPO_NAME) $(ORG_NAME)/$(REPO_NAME):$(VERSION).$(VCS_REF)
	@ docker tag $(ORG_NAME)/$(REPO_NAME):rclone-latest $(ORG_NAME)/$(REPO_NAME):rclone-$(VERSION).$(VCS_REF)
	${INFO} "Install complete"

# Cosmetics
YELLOW := "\e[1;33m"
NC := "\e[0m"

# Shell Functions
INFO := @bash -c '\
	printf $(YELLOW); \
	echo "=> $$1"; \
	printf $(NC)' SOME_VALUE