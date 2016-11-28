# Restic Backup Docker Container
A docker container to automate [restic backups](https://restic.github.io/)

This container runs restic backups in regular intervals. 

* Easy setup and maintanance
* Support for different targets (currently: Local, NFS, SFTP)
* Support `restic mount` inside the container to browse the backup files

**Container**: [lobaro/restic-backup-docker](https://hub.docker.com/r/lobaro/restic-backup-docker/)

```
docker pull lobaro/restic-backup-docker
```

# Test the container

Clone this repository

```
git clone https://github.com/Lobaro/restic-backup-docker.git
cd restic-backup-docker
```

Build the container. The container is named `backup-test`
```
./build.sh
```

Run the container.
```
./run.sh
```

This will run the container `backup-test` with the name  `backup-test`. Existing containers with that names are completly removed automatically.

The container will backup `~/test-data` to a repository with password `test` at `~/test-repo` every minute. The repository is initialized automatically by the container.

To enter your container execute

```
docker exec -ti backup-test /bin/sh
```

Now you can use restic [as documented](https://restic.readthedocs.io/en/stable/Manual/), e.g. try to run `restic snapshots` to list all your snapshots.

## Logfiles
Logfiles inside the container:

```
docker logs
```
Shows `/var/log/cron.log`

Additionally you can see the the full log of the last `backup` and `forget` command in `/var/log/backup-last.log` inside the container.

# Customize the Container

The container is setup by setting [environment variables](https://docs.docker.com/engine/reference/run/#/env-environment-variables) and [volumes](https://docs.docker.com/engine/reference/run/#volume-shared-filesystems).

## Environment variables

* `RESTIC_REPOSITORY` - the location of the restic repository. Default `/mnt/restic`
* `RESTIC_PASSWORD` - the password for the restic repository. Will also be used for restic init during first start when the repository is not initialized.
* `RESTIC_TAG` - Optional. To tag the images created by the container.
* `NFS_TARGET` - Optional. If set the given NFS is mounted, i.e. `mount -o nolock -v ${NFS_TARGET} /mnt/restic`. `RESTIC_REPOSITORY` must remain it's default value!
* `BACKUP_CRON` - A cron expression to run the backup. Default: `* */6 * * *` aka every 6 hours.
* `RESTIC_FORGET_ARGS` - Optional. Only if specified `restic forget` is run with the given arguments after each backup. Example value: `-e "RESTIC_FORGET_ARGS=--keep-last 10 --keep-hourly=24 --keep-daily 7 --keep-weekly=52 --keep-monthly=12 --keep-yearly 100"`

## Volumes

* `/data` - This is the data that gets backed up. Just mount it to wherever you want.

## Set the hostname

Since restic saves the hostname with each snapshot and the hostname of a docker container is it's id you might want to customize this by setting the hostname of the container to another value.

Either by setting the [environment variable](https://docs.docker.com/engine/reference/run/#env-environment-variables) `HOSTNAME` or with `--hostname` in the [network settings](https://docs.docker.com/engine/reference/run/#network-settings)

## Backup to SFTP

Since restic needs a **password less login** to the SFTP server make sure you can do `sftp user@host` from inside the container. If you can do so from your host system, the easiest way is to just mount your `.ssh` folder conaining the authorized cert into the container by specifying `-v ~/.ssh:/root/.ssh` as argument for `docker run`.

Now you can simply specify the restic repository to be an [SFTP repository](https://restic.readthedocs.io/en/stable/Manual/#create-an-sftp-repository).

```
-e "RESTIC_REPOSITORY=sftp:user@host:/tmp/backup"
```

# TODO

* Add testsetup based on docker-compose
