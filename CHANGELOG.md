# Changelog

## 1.3.1-0.9.6

### Changed
* Update to Restic v0.9.5
* Reduced the number of layers in the Docker image

### Fixed
* Check if a repo already exists works now for all repository types

### Added
* shh added to container
* fuse added to container
* support to send mails using external SMTP server after backups

## 1.2-0.9.4

### Added
* AWS Support

## 1.1

### Fixed
* `--prune` must be passed to `RESTIC_FORGET_ARGS` to execute prune after forget.

### Changed
* Switch to base Docker container to `golang:1.7-alpine` to support latest restic build.

## 1.0

Initial release.

The container has proper logs now and was running for over a month in production. 
There are still some features missing. Sticking to semantic versioning we do not expect any breaking changes in the 1.x releases.