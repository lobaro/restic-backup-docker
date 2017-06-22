#!/bin/sh

set -e

VOLUMEID=`docker volume create`

docker run --rm -t -v $VOLUMEID:/src -w /src \
    bravissimolabs/alpine-git \
    git clone https://github.com/restic/restic.git

docker run --rm -t \
    -v `pwd`:/output \
    -v $VOLUMEID:/go/src/github.com/restic \
    -w /go/src/github.com/restic/restic golang:1.8.3-alpine \
    /bin/sh -c "go run build.go && mv restic /output"

docker build --rm -t restic-backup .

docker volume rm $VOLUMEID
