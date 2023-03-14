#!/bin/sh

docker buildx build --platform linux/arm64 --push --tag bfriedrichs/restic-backup-docker-arm:latest --file Dockerfile .

