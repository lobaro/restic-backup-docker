# Changelog

## Unreleased

## v1.3.2+restic-0-16-0

### Changed
* Base image directly on official restic image
* [Semver](https://semver.org/) aligned version naming including restic version

### Added
* rclone to docker image
* Implemented a simple mail notification after backups using mailx
* MAILX_ARGS environment variable

## v1.3.1-0.9.6

### Changed
* Update to Restic v0.9.5
* Reduced the number of layers in the Docker image

### Fixed
* Check if a repo already exists works now for all repository types

### Added
* shh added to container
* fuse added to container
* support to send mails using external SMTP server after backups

## v1.2-0.9.4

### Added
* AWS Support

## v1.1

### Fixed
* `--prune` must be passed to `RESTIC_FORGET_ARGS` to execute prune after forget.

### Changed
* Switch to base Docker container to `golang:1.7-alpine` to support latest restic build.

## v1.0

Initial release.

The container has proper logs now and was running for over a month in production. 
There are still some features missing. Sticking to semantic versioning we do not expect any breaking changes in the 1.x releases.
