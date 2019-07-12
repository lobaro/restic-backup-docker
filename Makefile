.PHONY: build login logout deploy test

# Project variables
PROJECT_NAME ?= restic-backup-docker
ORG_NAME ?= cobrijani
REPO_NAME ?= restic-backup-docker

VERSION := `cat VERSION`
BUILD_DATE := `date -u +"%Y-%m-%dT%H:%M:%SZ"`
VCS_REF := `git rev-parse --short HEAD`

DOCKER_REGISTRY ?= docker.io
DOCKER_REGISTRY_AUTH ?=

build:
	${INFO} "Building docker images..."
	@ docker build --no-cache -t $(ORG_NAME)/$(REPO_NAME) \
				 --label maintainer="Stefan Bratic" \
				 --label org.label-schema.build-date=$(BUILD_DATE) \
				 --label org.label-schema.name="restic-backup-docker" \
				 --label org.label-schema.description="Automatic restic backup using docker" \
				 --label org.label-schema.url="https://github.com/Cobrijani/restic-backup-docker" \
				 --label org.label-schema.vcs-ref=$(VCS_REF) \
				 --label org.label-schema.vcs-url="https://github.com/Cobrijani/restic-backup-docker.git" \
				 --label org.label-schema.vendor="Cobrijani" \
				 --label org.label-schema.version=$(VERSION) \
				 --label org.label-schema.schema-version="1.0" \
				  .
	@ docker build --no-cache -t $(ORG_NAME)/$(REPO_NAME):rclone-latest \
				 --label maintainer="Stefan Bratic" \
				 --label org.label-schema.build-date=$(BUILD_DATE) \
				 --label org.label-schema.name="restic-backup-docker" \
				 --label org.label-schema.description="Automatic restic backup using docker" \
				 --label org.label-schema.url="https://github.com/Cobrijani/restic-backup-docker" \
				 --label org.label-schema.vcs-ref=$(VCS_REF) \
				 --label org.label-schema.vcs-url="https://github.com/Cobrijani/restic-backup-docker.git" \
				 --label org.label-schema.vendor="Cobrijani" \
				 --label org.label-schema.version=$(VERSION) \
				 --label org.label-schema.schema-version="1.0" \
				  ./rclone
	${INFO} "Building complete"

login:
	${INFO} "Logging in to Docker registry $$DOCKER_REGISTRY..."
	@ docker login -u $$DOCKER_USER -p $$DOCKER_PASSWORD $(DOCKER_REGISTRY_AUTH)
	${INFO} "Logged in to Docker registry $$DOCKER_REGISTRY"

logout:
	${INFO} "Logging out of Docker registry $$DOCKER_REGISTRY..."
	@ docker logout
	${INFO} "Logged out of Docker registry $$DOCKER_REGISTRY"


deploy:
	${INFO} "Deploying images"
	${INFO} "Complete"

test:
	${INFO} "Testing ..."
	${INFO} "Test Complete!"


# Repository Filter
ifeq ($(DOCKER_REGISTRY), docker.io)
	REPO_FILTER := $(ORG_NAME)/$(REPO_NAME)[^[:space:]|\$$]*
else
	REPO_FILTER := $(DOCKER_REGISTRY)/$(ORG_NAME)/$(REPO_NAME)[^[:space:]|\$$]*
endif

# Cosmetics
YELLOW := "\e[1;33m"
NC := "\e[0m"

# Shell Functions
INFO := @bash -c '\
	printf $(YELLOW); \
	echo "=> $$1"; \
	printf $(NC)' SOME_VALUE