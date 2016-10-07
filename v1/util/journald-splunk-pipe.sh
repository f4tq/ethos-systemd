#!/usr/bin/bash
if [[ -f /etc/profile.d/etcdctl.sh ]]; 
  then source /etc/profile.d/etcdctl.sh;
fi

source /etc/splunk.env
# see what kind of forwarder is needed
LOGGING_PORT=`etcdctl get /splunk/config/heavyforwarder/proxy-port`
LOGGING_ELB=`etcdctl get /environment/LOGGING_ELB`
LOGGING_INDEX=`etcdctl get /splunk/config/cloudops/index`
JOURNALD_PROXY=`etcdctl get /splunk/config/heavyforwarder/journald-proxy`
SYSTEM_TOKEN=`etcdctl get /splunk/config/heavyforwarder/system-token`
LOG_SCRUB_REGEX=`etcdctl get /splunk/config/syslog-scrub-regex`
ENABLE_SYSLOG_SCRUB=`etcdctl get /splunk/config/scrub-syslog`

if [ "$JOURNALD_PROXY" == "1" ]; then
        logger "Journald proxy enabled"
        # wait for etcdctl value then proceed set on standup on logging tier
        if [ "$LOGGING_ELB" == "" ]; then
                LOGGING_ELB=`etcdctl watch /environment/FLUENT_ELB`
        fi
        #System Logs to Http Event Collector and SplunkES over CertAuth
        if [ "$ENABLE_SYSLOG_SCRUB" == "0" ]; then
                logger "syslog scrub disabled"
                journalctl -f | while read line; do curl -s -k http://$LOGGING_ELB:$LOGGING_PORT/services/collector -H "Authorization: Splunk $SYSTEM_TOKEN" -d "{ \"event\": { \"log\": \"$line\", \"stack_name\": \"$STACK_NAME\", \"accountid\": \"$ACCOUNTID\", \"node_role\": \"$NODE_ROLE\", \"instanceid\": \"$INSTANCEID\", \"hostname\": \"$HOSTNAME\" }, \"index\": \"$LOGGING_INDEX\", \"sourcetype\": \"syslog\" }" > dev/null; done &
                journalctl -f | while read line; do echo "STACK_NAME=$STACK_NAME ACCOUNTID=$ACCOUNTID NODE_ROLE=$NODE_ROLE INSTANCEID=$INSTANCEID HOSTNAME=$HOSTNAME LOG=$line" | ncat --udp localhost 1514;done
        else
                logger "syslog scrub enabled"
                journalctl -f | while read line; do curl -s -k http://$LOGGING_ELB:$LOGGING_PORT/services/collector -H "Authorization: Splunk $SYSTEM_TOKEN" -d "{ \"event\": { \"log\": \"$(echo $line | sed "$LOG_SCRUB_REGEX")\", \"stack_name\": \"$STACK_NAME\", \"accountid\": \"$ACCOUNTID\", \"node_role\": \"$NODE_ROLE\", \"instanceid\": \"$INSTANCEID\", \"hostname\": \"$HOSTNAME\" }, \"index\": \"$LOGGING_INDEX\", \"sourcetype\": \"syslog\" }" > dev/null; done &
                journalctl -f | while read line; do echo "STACK_NAME=$STACK_NAME ACCOUNTID=$ACCOUNTID NODE_ROLE=$NODE_ROLE INSTANCEID=$INSTANCEID HOSTNAME=$HOSTNAME LOG=$(echo $line | sed "$LOG_SCRUB_REGEX")" | ncat --udp localhost 1514;done
        fi
else
        #System Logs to local universal forwarder for splunkES and splunkAAS
        if [ "$ENABLE_SYSLOG_SCRUB" == "0" ]; then
                logger "syslog scrub disabled"
                journalctl -f | while read line; do echo "STACK_NAME=$STACK_NAME ACCOUNTID=$ACCOUNTID NODE_ROLE=$NODE_ROLE INSTANCEID=$INSTANCEID HOSTNAME=$HOSTNAME LOG=$line" | ncat --udp localhost 1514;done &
                journalctl -f | while read line; do echo "STACK_NAME=$STACK_NAME ACCOUNTID=$ACCOUNTID NODE_ROLE=$NODE_ROLE INSTANCEID=$INSTANCEID HOSTNAME=$HOSTNAME LOG=$line" | ncat --udp localhost 1515;done 
        else
                logger "syslog scrub enabled \"$LOG_SCRUB_REGEX\""
                journalctl -f | while read line; do echo "STACK_NAME=$STACK_NAME ACCOUNTID=$ACCOUNTID NODE_ROLE=$NODE_ROLE INSTANCEID=$INSTANCEID HOSTNAME=$HOSTNAME LOG=$(echo $line | sed "$LOG_SCRUB_REGEX")" | ncat --udp localhost 1514;done &
                journalctl -f | while read line; do echo "STACK_NAME=$STACK_NAME ACCOUNTID=$ACCOUNTID NODE_ROLE=$NODE_ROLE INSTANCEID=$INSTANCEID HOSTNAME=$HOSTNAME LOG=$(echo $line | sed "$LOG_SCRUB_REGEX")" | ncat --udp localhost 1515;done
        fi
fi
