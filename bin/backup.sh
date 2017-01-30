#!/usr/bin/dumb-init /bin/bash
set -e

DISABLE_SYSLOG=${DISABLE_SYSLOG:-"no"}
if [ $DISABLE_SYSLOG == "no" ]; then
    #send logs to syslog
    exec 1> >(logger -s -t $(basename $0)) 2>&1
fi

export BORG_PASSPHRASE=`cat /etc/borg_passphrase`
BACKUP_PATH=`cat /etc/backup_path`
LOCAL_REPOSITORY=/borg/

# check if volumes folder is empty
if [ -n "$(ls -A /volumes)" ]
then
  echo "I am ready to backup /volumes ( ͡° ͜ʖ ͡°)"
else
  echo "/volumes is empty nothing to backup"
  exit 1
fi

#init volume if not exist 
if [ -d "$LOCAL_REPOSITORY" ]; then
    echo "repo already exists ...."
else
    borg init $LOCAL_REPOSITORY
fi

IFS=':' read -r -a ALL_REMOTES <<< "$(rclone listremotes | tr -d '[:space:]')"
declare -a APPROVED_REMOTES


function check_remote {
   local prefix=`cat /etc/$1_prefix`
   local remote_repo=$1:$prefix$BACKUP_PATH
   echo " $(tput setaf 1)◉$(tput sgr0) Running preflight checks for $1 rep [$remote_repo]"
   # check if remote repo is empty or contains files
   local repo_size=`rclone size $remote_repo | gawk '{ match($0, /([0-9]+) Bytes/, arr); if(arr[1] != "") print arr[1] }'`
   if [ "$repo_size" == "" ]; then
       echo "Skipping, failed to read the remote repo is probably that the bucket does not exist, you need to create it manually"
       return 1 
   fi
   if [ "$repo_size" == "0" ]; then
       echo "    $(tput setaf 2)✓$(tput sgr0) remote repo ok"
       return 0 
   else
       rclone --include "/config" check $LOCAL_REPOSITORY $remote_repo || \
       echo "$(tput setaf 1)                       
      #############                         #############
    ##            *##                     ##############*##
   #               **#                   ################**#
  #       %% %%    ***#                 ########  #  ####***#
 #       %%%%%%%   ****#               ########       ###****#
#         %%%%%    *****#             ##########     ####*****#
#   ###     %     ###***#             ####   ##### #####   ***#
#  # ####       #### #**#             ###      #######      **#
#  #     #     #     #**#             ###   X   #####   X   **#
#   #####  # #  #####***#             ####     ## # ##     ***#
#         #   #  *******#             ########## ### ##*******#
 ### #           **# ###               ### ############**# ###
     # - - - - - - #                       ##-#-#-#-#-#-##
      | | | | | | |                         | | | | | | |

"

       echo "    Danger!!: the private keys does not match (︶︹︺), this can delete all your data please fix the issues$(tput sgr0)" && exit 1
       echo "    private key check passed $(tput setaf 3)(*•̀ᴗ•́*)و$(tput sgr0)"
   fi
} 


function upload_to_remote {
   local prefix=`cat /etc/$1_prefix`
   local remote_repo=$1:$prefix$BACKUP_PATH
   # upload volume to cloud storage
   rclone sync $LOCAL_REPOSITORY $remote_repo
} 

THERE_IS_APPROVED_REPOS="false"

for item in "${ALL_REMOTES[@]}"
do
  if check_remote "${item}"; then
    APPROVED_REMOTES+=("${item}")
    THERE_IS_APPROVED_REPOS="true"
  fi
done

if [ "$THERE_IS_APPROVED_REPOS" == "false" ]; then
    echo "I can't use any of availables remote repos to upload the backup"
    exit 1
fi

# Backup all of /volumes
borg create --compression lz4 -v --stats $LOCAL_REPOSITORY::`date +%Y-%m%d-%H%M%S` /volumes

# Use the prune subcommand to maintain the latest backup of each day up to 10, 1 weekly backup up 4,  and a backup for each month
# maintain the last backup of each year up 100 years
borg prune -v --list $LOCAL_REPOSITORY  --keep-within 2d --keep-daily=10 --keep-weekly=4 --keep-monthly=12 --keep-yearly=100
for item in "${APPROVED_REMOTES[@]}"
do
  upload_to_remote "${item}"
done