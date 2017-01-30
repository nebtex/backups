#!/usr/bin/dumb-init /bin/bash
set -e

#ntpdate -q pool.ntp.org

#initi sys log
rsyslogd

if [ "$BACKUP_PATH" == "" ]; then
   [ -z $APP_NAME ] && { echo "Need to set APP_NAME or BACKUP_PATH"; exit 1; }
   [ -z $NAMESPACE ] && { echo "Need to set NAMESPACE or BACKUP_PATH"; exit 1; }
   if [ "$POD_NAME" == "" ]; then
      BACKUP_PATH=/$NAMESPACE/$APP_NAME
   else
      BACKUP_PATH=/$NAMESPACE/$APP_NAME/$POD_NAME 
   fi
else
    echo "BACKUP_PATH defined as $BACKUP_PATH"
fi

[ -z $BACKUP_PATH ] && { echo "Need to set BACKUP_PATH"; exit 1; }
printf $BACKUP_PATH > /etc/backup_path


if  [ "$CONSUL_HTTP_ADDR" == "" ]; then
    echo "$(tput setaf 3)CONSUL_HTTP_ADDR not found, using environments vairables ...$(tput sgr0)"
    [ -z $AWS_BUCKET ] && { echo "Need to set AWS_BUCKET"; exit 1; }
    [ -z $BORG_PASSPHRASE ] && { echo "Need to set  BORG_PASSPHRASE"; exit 1; }
    [ -z $AWS_ACCESS_KEY_ID ] && { echo "Need to set  AWS_ACCESS_KEY_ID"; exit 1; }
    [ -z $AWS_SECRET_ACCESS_KEY ] && { echo "Need to set  AWS_SECRET_ACCESS_KEY"; exit 1; }
    [ -z $AWS_REGION ] && { echo "Need to set  AWS_REGION"; exit 1; }
    printf $AWS_BUCKET > /etc/default_prefix
    printf $BORG_PASSPHRASE > /etc/borg_passphrase
    rclone_file=/root/.rclone.conf

    cp /templates/default-rclone.conf $rclone_file
    echo "s@AWS_ACCESS_KEY_ID@${AWS_ACCESS_KEY_ID}@"
    sed -Ei "s@AWS_ACCESS_KEY_ID@${AWS_ACCESS_KEY_ID}@" $rclone_file
    echo "s@AWS_SECRET_ACCESS_KEY@${AWS_SECRET_ACCESS_KEY}@"
    sed -Ei "s@AWS_SECRET_ACCESS_KEY@${AWS_SECRET_ACCESS_KEY}@" $rclone_file
    echo "s@AWS_REGION@${AWS_REGION}@"
    sed -Ei "s@AWS_REGION@${AWS_REGION}@" $rclone_file
fi

# get vault token
VAULT_FILE='/secrets/vault-token'

if [ -f "$VAULT_FILE" ]; then
   echo "Loading vault config $VAULT_FILE..."
   export VAULT_TOKEN=`cat /secrets/vault-token | jq .clientToken -r`
   export VAULT_ADDR=`cat /secrets/vault-token | jq .vaultAddr -r`
else
   echo "ignoring Vault, file $VAULT_FILE does not exist"
fi


if [ "$1" == "restore" ];then
    echo "restoring files ...."
    if ! [ "$CONSUL_HTTP_ADDR" == "" ]; then
        consul-template \
            -template="/templates/consul-child.conf:/tmp/ct-child" -once
        consul-template -config="/tmp/ct-child" -once
    fi
    restore.sh || exit 1
    exit 0
else
    echo "doing regular backups... "
    # write crontab file
    crontab='/tmp/crontab'
    cp /templates/crontab $crontab
    CRON_TIME=$1
    sed -Ei "s@CRON_TIME@${CRON_TIME}@" $crontab
    chkcrontab $crontab
    echo "cron is correct !!"
    crontab  $crontab
    echo "cron successful loaded !!"
    #start cron
    cron

    if [ "$CONSUL_HTTP_ADDR" == "" ]; then

        #run an initial backup 
        echo "doing initial backup ..."
        export DISABLE_SYSLOG="yes"
        backup.sh || exit 1
        tail -F /var/log/syslog
        
    else
        echo "doing initial backup ..."
        consul-template \
        -template="/templates/consul-child.conf:/tmp/ct-child" -once
        
        consul-template -config="/tmp/ct-child" -once
        
        export DISABLE_SYSLOG="yes"
        backup.sh || exit 1

        consul-template \
        -exec-reload-signal="SIGHUP" \
        -template="/templates/consul-child.conf:/tmp/ct-child" \
        -exec="consul-template -config=\"/tmp/ct-child\" -exec=\"tail -F /var/log/syslog\""

    fi
fi