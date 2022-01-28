# Gitlab backup to remote storage and retention manager
# -------------------------------------------------------------------------------------
# Author          :   Rory Swann {rory@shirenet.io}
# Version         :   v1.0
# Last Updated    :   2022-01-28
# Notes           :   Requires remote storage mounted to file system
#                     Logs to stdout by default
#                     Recommend running as a cronjob
# -------------------------------------------------------------------------------------
#!/usr/bin/env bash

# Variables
DATA_VOLUME=""                          ### Volume containing Gitlab
BACKUP_VOLUME=""                        ### Mounted remote volume containing Gitlab backups
GL_TMP_BACKUP_DIR=""                    ### Temp directory for storing Gitlab dump
GL_BACKUP_DIR=""                        ### Mounted remote directory for Gitlab backups
GITLAB_ETC="/etc/gitlab"                ### Gitlab config directory
GITLAB_HTTP="/etc/httpd"                ### Gitlab HTTP directory
NICE_VALUE="15"                         ### Nice value. Determins Gitlab backup priority
DATE=$(date +%Y-%m-%d)                  ### Current date
LOG_DATE='date --rfc-3339=seconds'      ### Format of logging date/time
LOCKFILE="/tmp/gitlab_backup.lock"      ### Lock file location
FREE_SPACE="1000000000"                 ### Space required to enable backup to proceed
BACKUP_RETENTION="6"                    ### How many backups to store. Oldest is deleted

mvBackup() {
    # Moves the backup to the remote storage.
    echo "$($LOG_DATE) -- Creating backup directory on remote storage."
    mkdir -p ${GL_BACKUP_DIR}/${DATE}
    echo "$($LOG_DATE) -- Moving backup from temporary to remote location."
    rsync ${GL_TMP_BACKUP_DIR}/*.tar* ${GL_BACKUP_DIR}/${DATE}
}

cleanTmp() {
    # Cleans the temporary backup directory.
    echo "$($LOG_DATE) -- Cleaning temporary backup directory."
    rm -rf ${GL_TMP_BACKUP_DIR}/*
}

startBackup() {
    # Initiates the backup process. Writes to local data volume.
    echo "$($LOG_DATE) -- Starting backup."
    nice -n $NICE_VALUE gitlab-backup create
    tar czf $GL_TMP_BACKUP_DIR/${DATE}_gitlab_etc.tar.gz $GITLAB_ETC
    tar czf $GL_TMP_BACKUP_DIR/${DATE}_gitlab_httpd.tar.gz $GITLAB_HTTP
}

createLockFile() {
    # Creates the lock file to prevent simultanious executions.
    echo "$($LOG_DATE) -- Creating lock file."
    touch $LOCKFILE
}

deleteLockFile() {
    # Deletes the lock file.
    echo "$($LOG_DATE) -- Deleting lock file."
    rm $LOCKFILE
}

checkDiskSpace() {
    # Checks available space on volume passed as argument.
    df --output=source,avail | grep $1 | awk '{ print $2 }'
}

deleteOldestBackup() {
    # Deletes the oldest backup if BACKUP_RETENTION variable is exceeded.
    OLDEST=$(ls -t ${GL_BACKUP_DIR} | tail -1)
    if [ "$(ls ${GL_BACKUP_DIR} | wc -l)" -ge ${BACKUP_RETENTION} ]; then
        echo "$($LOG_DATE) -- 3 or more backups available. Deleting oldest."
        rm -rf ${GL_BACKUP_DIR}/${OLDEST}
    else
        echo "$($LOG_DATE) -- 3 previous backups not availble. Retaining current."
    fi
}

checkSameDate() {
    # Checks if a backup for the same date already exists. If so, script terminates.
    if [ -d $GL_BACKUP_DIR/$DATE ]; then
        echo "$($LOG_DATE) -- Backup for ${DATE} already exists. Terminating."
        deleteLockFile
        exit 1
    fi
}

# Check for a lock file before we start.
if [ -f $LOCKFILE ]; then
    echo "$($LOG_DATE) -- Lock file exists. Terminating."
    exit 1
else
    createLockFile
fi

# Check the available disk space on essential volumes.
if [ $(checkDiskSpace $DATA_VOLUME) -lt $FREE_SPACE ]; then
    echo "$($LOG_DATE) -- Available disk space on data volume is below 1TB."
    deleteLockFile
    exit 1
elif [ $(checkDiskSpace $BACKUP_VOLUME) -lt $FREE_SPACE ]; then
    echo "$($LOG_DATE) -- Available disk space on backup NFS share is below 1TB."
    deleteLockFile
    exit 1
else
    echo "$($LOG_DATE) -- Available disk space OK for backup."
fi

# Start the backup.
checkSameDate
cleanTmp
startBackup

# Get MD5 sum of local backup.
LATEST_BACKUP=$(ls -At $GL_TMP_BACKUP_DIR | grep gitlab_backup | head -1)
MD5_LATEST=$(md5sum ${GL_TMP_BACKUP_DIR}/${LATEST_BACKUP} | awk '{ print $1 }')
echo "$($LOG_DATE) -- Local md5: $MD5_LATEST"

# Clean space and move the local backup to remote storage.
deleteOldestBackup
mvBackup
MD5_REMOTE=$(md5sum ${GL_BACKUP_DIR}/${DATE}/${LATEST_BACKUP} | awk '{ print $1 }')
echo "$($LOG_DATE) -- Remote md5: $MD5_REMOTE"

# Compare local MD5 against remote MD5.
if [ "$MD5_LATEST" == "$MD5_REMOTE" ]; then
    echo "$($LOG_DATE) -- MD5 sums of local and remote backups match."
    cleanTmp
    deleteLockFile
    exit 0
else
    echo "$($LOG_DATE) -- ERROR: MD5 sums of local and remote backups do not match."
    cleanTmp
    deleteLockFile
    exit 1
fi