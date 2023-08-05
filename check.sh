#!/bin/sh

lastLogfile="/var/log/check-last.log"
lastMailLogfile="/var/log/check-mail-last.log"
lastMicrosoftTeamsLogfile="/var/log/check-microsoft-teams-last.log"

copyErrorLog() {
  cp ${lastLogfile} /var/log/check-error-last.log
}

logLast() {
  echo "$1" >> ${lastLogfile}
}

if [ -f "/hooks/pre-check.sh" ]; then
    echo "Starting pre-check script ..."
    /hooks/pre-check.sh
else
    echo "Pre-check script not found ..."
fi

start=`date +%s`
rm -f ${lastLogfile} ${lastMailLogfile}
echo "Starting Check at $(date +"%Y-%m-%d %H:%M:%S")"
echo "Starting Check at $(date)" >> ${lastLogfile}
logLast "CHECK_CRON: ${CHECK_CRON}"
logLast "RESTIC_DATA_SUBSET: ${RESTIC_DATA_SUBSET}"
logLast "RESTIC_REPOSITORY: ${RESTIC_REPOSITORY}"
logLast "AWS_ACCESS_KEY_ID: ${AWS_ACCESS_KEY_ID}"

# Do not save full check log to logfile but to check-last.log
if [ -n "${RESTIC_DATA_SUBSET}" ]; then
    restic check --read-data-subset=${RESTIC_DATA_SUBSET} >> ${lastLogfile} 2>&1
else
    restic check >> ${lastLogfile} 2>&1
fi
checkRC=$?
logLast "Finished check at $(date)"
if [[ $checkRC == 0 ]]; then
    echo "Check Successful"
else
    echo "Check Failed with Status ${checkRC}"
    restic unlock
    copyErrorLog
fi

end=`date +%s`
echo "Finished Check at $(date +"%Y-%m-%d %H:%M:%S") after $((end-start)) seconds"

if [ -n "${TEAMS_WEBHOOK_URL}" ]; then
    teamsTitle="Restic Last Check Log"
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

if [ -f "/hooks/post-check.sh" ]; then
    echo "Starting post-check script ..."
    /hooks/post-check.sh $checkRC
else
    echo "Post-check script not found ..."
fi
