# Gitlab Backup

This script backs up Gitlab and manages the backup retention. It should ideally backup to a remote
location such as an NFS share or S3 bucket.

## Usage

The remote backup location needs to be mounted to the file system.

The script should be run as a cronjob every 24-48 hours.

Larger (100GB+) Gitlab instances can take an extremely long time to backup. Due to this limitation, the
backup is created on a local data volume and then transfered using rsync to the remote storage. An MD5
comparison between the local and remote copy of the backup ensures data integrity after the transfer.

The script doesn't take any arguments. Configuration is done within the script under the 'Variables' section.
The variables are described and should be self explanitory.
