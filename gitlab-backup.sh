#!/usr/bin/env bash

DATE=$(date +%y-%m-%d)
BACKUPDIR='/mnt/backups'
GITLAB_RB='/etc/gitlab/gitlab.rb'
GITLAB_RB_REMOTE="$BACKUPDIR/files/gitlab.rb-$DATE"
GITLAB_SECRETS='/etc/gitlab/gitlab-secrets.json'
GITLAB_SECRETS_REMOTE="$BACKUPDIR/files/gitlab-secrets.json-$DATE"
GITLAB_USER_1=''
GITLAB_USER_2=''

deleteOldFiles() {

    num_files=$(ls "$BACKUPDIR" | wc -l)
    echo "Number of backups: $num_files"

    if [ "$num_files" -gt 4 ]; then
        echo 'Deleting backups older than 28 days'
        find $BACKUPDIR -mtime +28 -exec rm {} \;
    fi
}

gitBackup() {

    echo 'Backing up Gitlab'
    gitlab-backup create
}

gitBackupFiles() {

    echo 'Backing up Gitlab files'
    cp $GITLAB_RB "$GITLAB_RB_REMOTE-$DATE"
    cp $GITLAB_SECRETS "$GITLAB_SECRETS_REMOTE-$DATE"
}

checkGitDir() {

    if [ ! -d "$BACKUPDIR/files" ]; then
        echo "file dir doesn't exist. Creating..."
        mkdir "$BACKUPDIR/files"
    fi
}

checkMount() {

    mount | grep '/mnt/backups' > /dev/null

    if [ $? -ne 0 ]; then
        echo "Backup not mounted"
        mailx -s "Gitlab backup failed" -r $GITLAB_USER_1 $GITLAB_USER_2 <<< "Gitlab backup mount down"
        exit 1
    fi
}

checkMount
deleteOldFiles
checkGitDir
gitBackup
gitBackupFiles
