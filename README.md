# Restic Backup Docker Container
A docker container to automate [restic backups](https://restic.github.io/)

This container runs restic backups in regular intervals. 

* Easy setup and maintanance
* Support for different targets (tested with: Local, NFS, SFTP, AWS)
* Support `restic mount` inside the container to browse the backup files

**Container**: [lobaro/restic-backup-docker](https://hub.docker.com/r/lobaro/restic-backup-docker/)

Stable
```
docker pull lobaro/restic-backup-docker:1.2-0.9.4
```

Latest (experimental)
```
docker pull lobaro/restic-backup-docker:latest
```

## Hooks

If you need to execute a script before or after each backup, 
you need to add your hook script in the container folder `/hooks`:
```
-v ~/home/user/hooks:/hooks
```
Call your pre backup script `pre-backup.sh` and post backup script `post-backup.sh`

Please don't hesitate to report any issue you find. **Thanks.**

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

Now you can use restic [as documented](https://restic.readthedocs.io/en/stable/), e.g. try to run `restic snapshots` to list all your snapshots.

## Logfiles
Logfiles are inside the container. If needed you can create volumes for them.

```
docker logs
```
Shows `/var/log/cron.log`

Additionally you can see the the full log, including restic output, of the last execution in `/var/log/backup-last.log`. When the backup fails the log is copied to `/var/log/restic-error-last.log`. If configured, you can find the full output of the mail notification in `/var/log/mail-last.log`.

# Use the running container

Assuming the container name is `restic-backup-var`

You can execute restic with ` docker exec -ti restic-backup-var restic`

## Backup

To execute a backup manually independent of the CRON run:

    docker exec -ti restic-backup-var /bin/backup
    
    
Backup a single file or directory

    docker exec -ti restic-backup-var restic backup /data/path/to/dir --tag my-tag

## Restore

You might want to mount a separate hostvolume at e.g. `/restore` to not override existing data while restoring. 

Get your snapshot ID with

    docker exec -ti restic-backup-var restic snapshots
    
e.g. `abcdef12`

     docker exec -ti restic-backup-var restic restore --include /data/path/to/files --target / abcdef12

The target is `/` since all data backed up should be inside the host mounted `/data` dir. If you mount `/restore` you should set `--target /restore` and data will end up in `/restore/data/path/to/files`.



# Customize the Container

The container is setup by setting [environment variables](https://docs.docker.com/engine/reference/run/#/env-environment-variables) and [volumes](https://docs.docker.com/engine/reference/run/#volume-shared-filesystems).

## Environment variables

* `RESTIC_REPOSITORY` - the location of the restic repository. Default `/mnt/restic`. For S3: `s3:https://s3.amazonaws.com/BUCKET_NAME`
* `RESTIC_PASSWORD` - the password for the restic repository. Will also be used for restic init during first start when the repository is not initialized.
* `RESTIC_TAG` - Optional. To tag the images created by the container.
* `NFS_TARGET` - Optional. If set the given NFS is mounted, i.e. `mount -o nolock -v ${NFS_TARGET} /mnt/restic`. `RESTIC_REPOSITORY` must remain it's default value!
* `BACKUP_CRON` - A cron expression to run the backup. Note: cron daemon uses UTC time zone. Default: `0 */6 * * *` aka every 6 hours.
* `RESTIC_FORGET_ARGS` - Optional. Only if specified `restic forget` is run with the given arguments after each backup. Example value: `-e "RESTIC_FORGET_ARGS=--prune --keep-last 10 --keep-hourly 24 --keep-daily 7 --keep-weekly 52 --keep-monthly 120 --keep-yearly 100"`
* `RESTIC_JOB_ARGS` - Optional. Allows to specify extra arguments to the back up job such as limiting bandwith with `--limit-upload` or excluding file masks with `--exclude`.
* `AWS_ACCESS_KEY_ID` - Optional. When using restic with AWS S3 storage.
* `AWS_SECRET_ACCESS_KEY` - Optional. When using restic with AWS S3 storage.
* `TEAMS_WEBHOOK_URL` - Optional. If specified, the content of `/var/log/backup-last.log` is sent to your Microsoft Teams channel after each backup.
* `MAILX_ARGS` - Optional. If specified, the content of `/var/log/backup-last.log` is sent via mail after each backup using an *external SMTP*. To have maximum flexibility, you have to specify the mail/smtp parameters by your own. Have a look at the [mailx manpage](https://linux.die.net/man/1/mailx) for further information. Example value: `-e "MAILX_ARGS=-r 'from@example.de' -s 'Result of the last restic backup run' -S smtp='smtp.example.com:587' -S smtp-use-starttls -S smtp-auth=login -S smtp-auth-user='username' -S smtp-auth-password='password' 'to@example.com'"`.
* `OS_AUTH_URL` - Optional. When using restic with OpenStack Swift container.
* `OS_PROJECT_ID` - Optional. When using restic with OpenStack Swift container.
* `OS_PROJECT_NAME` - Optional. When using restic with OpenStack Swift container.
* `OS_USER_DOMAIN_NAME` - Optional. When using restic with OpenStack Swift container.
* `OS_PROJECT_DOMAIN_ID` - Optional. When using restic with OpenStack Swift container.
* `OS_USERNAME` - Optional. When using restic with OpenStack Swift container.
* `OS_PASSWORD` - Optional. When using restic with OpenStack Swift container.
* `OS_REGION_NAME` - Optional. When using restic with OpenStack Swift container.
* `OS_INTERFACE` - Optional. When using restic with OpenStack Swift container.
* `OS_IDENTITY_API_VERSION` - Optional. When using restic with OpenStack Swift container.

## Volumes

* `/data` - This is the data that gets backed up. Just [mount](https://docs.docker.com/engine/reference/run/#volume-shared-filesystems) it to wherever you want.

## Set the hostname

Since restic saves the hostname with each snapshot and the hostname of a docker container is derived from it's id you might want to customize this by setting the hostname of the container to another value.

Set `--hostname` in the [network settings](https://docs.docker.com/engine/reference/run/#network-settings)

## Backup via SFTP

Since restic needs a **password less login** to the SFTP server make sure you can do `sftp user@host` from inside the container. If you can do so from your host system, the easiest way is to just mount your `.ssh` folder conaining the authorized cert into the container by specifying `-v ~/.ssh:/root/.ssh` as argument for `docker run`.

Now you can simply specify the restic repository to be an [SFTP repository](https://restic.readthedocs.io/en/stable/Manual/#create-an-sftp-repository).

```
-e "RESTIC_REPOSITORY=sftp:user@host:/tmp/backup"
```

## Backup via OpenStack Swift

Restic can backup data to an OpenStack Swift container. Because Swift supports various authentication methods, credentials are passed through environment variables. In order to help integration with existing OpenStack installations, the naming convention of those variables follows the official Python Swift client.  
Now you can simply specify the restic repository to be an [Swift repository](https://restic.readthedocs.io/en/latest/030_preparing_a_new_repo.html#openstack-swift).

```
-e "RESTIC_REPOSITORY=swift:backup:/"
-e "RESTIC_PASSWORD=password"
-e "OS_AUTH_URL=https://auth.cloud.ovh.net/v3"
-e "OS_PROJECT_ID=xxxx"
-e "OS_PROJECT_NAME=xxxx"
-e "OS_USER_DOMAIN_NAME=Default"
-e "OS_PROJECT_DOMAIN_ID=default"
-e "OS_USERNAME=username"
-e "OS_PASSWORD=password"
-e "OS_REGION_NAME=SBG"
-e "OS_INTERFACE=public"
-e "OS_IDENTITY_API_VERSION=3"
```

## Backup via rclone

To use rclone as a backend for restic, simply add the rclone config file as a volume with `-v /absolute/path/to/rclone.conf:/root/.config/rclone/rclone.conf`.

Note that for some backends (Among them Google Drive and Microsoft OneDrive), rclone writes data back to the `rclone.conf` file. In this case it needs to be writable by Docker.

If the the container fails to write the new `rclone.conf` file with the error message `Failed to save config after 10 tries: Failed to move previous config to backup location`, add the entire `rclone` directory as volume: `-v /absolute/path/to/rclone-dir:/root/.config/rclone`.
 
# Versioning & Changelog

Starting from v1.3.0 versioning follows [Semantic versioning](http://semver.org/)

Build metadata is used to declare the Restic version.

**Example:** 1.3.0+0.9.5 (includes Restic 0.9.5)

For changelog see: https://github.com/lobaro/restic-backup-docker/releases
