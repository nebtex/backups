#!/usr/bin/dumb-init /bin/bash
export BORG_PASSPHRASE=`cat /etc/borg_passphrase`
BACKUP_PATH=`cat /etc/backup_path`
LOCAL_REPOSITORY=/borg/

IFS=':' read -r -a ALL_REMOTES <<< "$(rclone listremotes | tr -d '[:space:]')"

function download_to_local {
   local prefix=`cat /etc/$1_prefix`
   local remote_repo=$1:$prefix$BACKUP_PATH
   # download backup to the local repo
   if rclone sync $remote_repo $LOCAL_REPOSITORY; then
       return 0
   else
       return 1
   fi
} 

for item in "${ALL_REMOTES[@]}"
do
  if download_to_local "${item}"; then
    #break with the first successful restore
    break
  fi
done

if [ -n "$(ls -A /borg)" ]
then
  # restore latest backup
  backups=($(borg list /borg))
  borg extract /borg::${backups[-4]}
  echo "$(tput setaf 3)❃ႣᄎႣ❃$(tput sgr0)  restore is done, enjoy !!! $(tput setaf 3)❃ႣᄎႣ❃$(tput sgr0)"
else
  echo "/borg is empty nothing to restore"
fi
