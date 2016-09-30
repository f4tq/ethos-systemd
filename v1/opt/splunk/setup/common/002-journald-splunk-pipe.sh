#!/usr/bin/bash -x
source /etc/environment
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SPLUNKENVFILE="/etc/splunk.env"
source $DIR/../../../../lib/helpers.sh 
SPLUNK_DIR="/opt/splunk/etc/system/local"
INSTANCEID=`curl -s http://169.254.169.254/latest/meta-data/instance-id`
HOSTNAME=`curl -s http://169.254.169.254/latest/meta-data/hostname`
ACCOUNTID=`curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | grep -oP '(?<=\"accountId\" : \")[^\"]*(?=\")'`
#setup additional enviornmentfile
cat << EOF > $SPLUNKENVFILE
NODE_ROLE=$NODE_ROLE
STACK_NAME=$STACK_NAME
INSTANCEID=$INSTANCEID
HOSTNAME=$HOSTNAME
ACCOUNTID=$ACCOUNTID
EOF
