#!/bin/sh

lastLogfile="/var/log/backup-last.log"
lastMailLogfile="/var/log/mail-last.log"
lastMicrosoftTeamsLogfile="/var/log/microsoft-teams-last.log"

copyErrorLog() {
  cp ${lastLogfile} /var/log/backup-error-last.log
}

logLast() {
  echo "$1" >> ${lastLogfile}
}

backupDatebase(){
  echo "### Start MongoDB Dump ###"
  echo "Backup Datebase: ${DATABASE_TYPE}"
  # 检查 dump 目录是否存在，如果存在则删除
  if [ -d "/script/dump" ]; then
      rm -rf /script/dump
  fi
  mkdir /script/dump
  # 运行 dump 脚本
  npm run dump
  # 检查 /script/dump 目录下是否为空，不为空则复制 dump 数据到
  if [ "$(ls -A /script/dump)" ]; then
      # 检查 /data/dump 目录存在，自动删除旧备份；如果不存在则创建 dump 目录
      if [ -d "/data/dump" ]; then
        rm -rf /data/dump/*
      else
        mkdir /data/dump
      fi
      # 复制最新的备份
      cp -r /script/dump /data/
      echo "\n MongoDB Dump List:"
      ls -l /data/dump
  else
      echo "./dump Folder Empty, MongoDB Dump Fail."
  fi
  echo "### End ${DATABASE_TYPE} Dump ###"
}

if [ -f "/hooks/pre-backup.sh" ]; then
    echo "Starting pre-backup script ..."
    /hooks/pre-backup.sh
else
    echo "Pre-backup script not found ..."
fi

# Dump Datebase
if [ -n "${DATABASE_TYPE}" ]; then
    # 判断时间是否在指定时间段内(建议凌晨1点到凌晨5点之间)
    current_hour=$(date +%H)
    # if [[ $current_hour -ge 0 && $current_hour -le 23 ]]; then
    if [[ $current_hour -ge ${DATABASE_BACKUP_START} && $current_hour -le ${DATABASE_BACKUP_END} ]]; then
        echo "Current within the Backup Time Period (${DATABASE_BACKUP_START}~${DATABASE_BACKUP_END})"
        backupDatebase
    else
        echo "Current not within the Backup Time Period (${DATABASE_BACKUP_START}~${DATABASE_BACKUP_END})"
        echo "Skip ${DATABASE_TYPE} Dump"
    fi
fi

start=`date +%s`
rm -f ${lastLogfile} ${lastMailLogfile}
echo "Starting Backup at $(date +"%Y-%m-%d %H:%M:%S")"
echo "Starting Backup at $(date)" >> ${lastLogfile}
logLast "BACKUP_CRON: ${BACKUP_CRON}"
logLast "RESTIC_TAG: ${RESTIC_TAG}"
logLast "RESTIC_FORGET_ARGS: ${RESTIC_FORGET_ARGS}"
logLast "RESTIC_JOB_ARGS: ${RESTIC_JOB_ARGS}"
logLast "RESTIC_REPOSITORY: ${RESTIC_REPOSITORY}"
logLast "AWS_ACCESS_KEY_ID: ${AWS_ACCESS_KEY_ID}"

# Do not save full backup log to logfile but to backup-last.log
restic backup /data ${RESTIC_JOB_ARGS} --tag=${RESTIC_TAG?"Missing environment variable RESTIC_TAG"} >> ${lastLogfile} 2>&1
backupRC=$?
logLast "Finished backup at $(date)"
if [[ $backupRC == 0 ]]; then
    echo "Backup Successful"
else
    echo "Backup Failed with Status ${backupRC}"
    restic unlock
    copyErrorLog
fi

if [[ $backupRC == 0 ]] && [ -n "${RESTIC_FORGET_ARGS}" ]; then
    echo "Forget about old snapshots based on RESTIC_FORGET_ARGS = ${RESTIC_FORGET_ARGS}"
    restic forget ${RESTIC_FORGET_ARGS} >> ${lastLogfile} 2>&1
    rc=$?
    logLast "Finished forget at $(date)"
    if [[ $rc == 0 ]]; then
        echo "Forget Successful"
    else
        echo "Forget Failed with Status ${rc}"
        restic unlock
        copyErrorLog
    fi
fi

end=`date +%s`
echo "Finished Backup at $(date +"%Y-%m-%d %H:%M:%S") after $((end-start)) seconds"

if [ -n "${TEAMS_WEBHOOK_URL}" ]; then
    teamsTitle="Restic Last Backup Log"
    teamsMessage=$( cat ${lastLogfile} | sed 's/"/\"/g' | sed "s/'/\'/g" | sed ':a;N;$!ba;s/\n/\n\n/g' )
    teamsReqBody="{\"title\": \"${teamsTitle}\", \"text\": \"${teamsMessage}\" }"
    sh -c "curl -H 'Content-Type: application/json' -d '${teamsReqBody}' '${TEAMS_WEBHOOK_URL}' > ${lastMicrosoftTeamsLogfile} 2>&1"
    if [ $? == 0 ]; then
        echo "Microsoft Teams notification successfully sent."
    else
        echo "Sending Microsoft Teams notification FAILED. Check ${lastMicrosoftTeamsLogfile} for further information."
    fi
fi

if [ -n "${MAILX_ARGS}" ]; then
    sh -c "mail -v -S sendwait ${MAILX_ARGS} < ${lastLogfile} > ${lastMailLogfile} 2>&1"
    if [ $? == 0 ]; then
        echo "Mail notification successfully sent."
    else
        echo "Sending mail notification FAILED. Check ${lastMailLogfile} for further information."
    fi
fi

if [ -f "/hooks/post-backup.sh" ]; then
    echo "Starting post-backup script ..."
    /hooks/post-backup.sh $backupRC
else
    echo "Post-backup script not found ..."
fi
