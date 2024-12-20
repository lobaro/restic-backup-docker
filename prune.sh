#!/bin/sh

lastLogfile="/var/log/prune-last.log"
lastMailLogfile="/var/log/prune-mail-last.log"
lastMicrosoftTeamsLogfile="/var/log/prune-microsoft-teams-last.log"

copyErrorLog() {
  cp ${lastLogfile} /var/log/prune-error-last.log
}

logLast() {
  echo "$1" >> ${lastLogfile}
}

if [ -f "/hooks/pre-prune.sh" ]; then
    echo "Starting pre-prune script ..."
    /hooks/pre-prune.sh
else
    echo "Pre-prune script not found ..."
fi

start=`date +%s`
rm -f ${lastLogfile} ${lastMailLogfile}
echo "Starting Prune at $(date +"%Y-%m-%d %H:%M:%S")"
echo "Starting Prune at $(date)" >> ${lastLogfile}
logLast "PRUNE_CRON: ${PRUNE_CRON}"
logLast "RESTIC_DATA_SUBSET: ${RESTIC_DATA_SUBSET}"
logLast "RESTIC_REPOSITORY: ${RESTIC_REPOSITORY}"
logLast "AWS_ACCESS_KEY_ID: ${AWS_ACCESS_KEY_ID}"

# Do not save full prune log to logfile but to prune-last.log
restic prune >> ${lastLogfile} 2>&1
pruneRC=$?
logLast "Finished prune at $(date)"
if [[ $pruneRC == 0 ]]; then
    echo "Prune Successful"
else
    echo "Prune Failed with Status ${pruneRC}"
    restic unlock
    copyErrorLog
fi

end=`date +%s`
echo "Finished Prune at $(date +"%Y-%m-%d %H:%M:%S") after $((end-start)) seconds"

if [ -n "${TEAMS_WEBHOOK_URL}" ]; then
    teamsTitle="Restic Last Prune Log"
    teamsMessage=$( cat ${lastLogfile} | sed 's/"/\"/g' | sed "s/'/\'/g" | sed ':a;N;$!ba;s/\n/\n\n/g' )
    teamsReqBody="{\"title\": \"${teamsTitle}\", \"text\": \"${teamsMessage}\" }"
    sh -c "curl -H 'Content-Type: application/json' -d '${teamsReqBody}' '${TEAMS_WEBHOOK_URL}' > ${lastMicrosoftTeamsLogfile} 2>&1"
    if [ $? == 0 ]; then
        echo "Microsoft Teams notification successfully sent."
    else
        echo "Sending Microsoft Teams notification FAILED. Prune ${lastMicrosoftTeamsLogfile} for further information."
    fi
fi

if [ -n "${MAILX_ARGS}" ]; then
    sh -c "mail -v -S sendwait ${MAILX_ARGS} < ${lastLogfile} > ${lastMailLogfile} 2>&1"
    if [ $? == 0 ]; then
        echo "Mail notification successfully sent."
    else
        echo "Sending mail notification FAILED. Prune ${lastMailLogfile} for further information."
    fi
fi

if [ -f "/hooks/post-prune.sh" ]; then
    echo "Starting post-prune script ..."
    /hooks/post-prune.sh $pruneRC
else
    echo "Post-prune script not found ..."
fi
