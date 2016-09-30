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


if [ "$JOURNALD_PROXY" == "1" ]; then
	# wait for etcdctl value then proceed set on standup on logging tier
	if [ "$LOGGING_ELB" == "" ]; then
		LOGGING_ELB=`etcdctl watch /environment/FLUENT_ELB`
	fi
	#System Logs to Http Event Collector and SplunkES over CertAuth
	journalctl -f | while read line; do curl -s -k http://$LOGGING_ELB:$LOGGING_PORT/services/collector -H "Authorization: Splunk $SYSTEM_TOKEN" -d "{ \"event\": { \"log\": \"$line\", \"stack_name\": \"$STACK_NAME\", \"accountid\": \"$ACCOUNTID\", \"node_role\": \"$NODE_ROLE\", \"instanceid\": \"$INSTANCEID\", \"hostname\": \"$HOSTNAME\" }, \"index\": \"$LOGGING_INDEX\", \"sourcetype\": \"syslog\" }" > dev/null; done &
	journalctl -f | while read line; do echo "STACK_NAME=$STACK_NAME ACCOUNTID=$ACCOUNTID NODE_ROLE=$NODE_ROLE INSTANCEID=$INSTANCEID HOSTNAME=$HOSTNAME LOG=$line" | ncat --udp localhost 1514;done
else
	#System Logs to local universal forwarder for splunkES and splunkAAS
 	journalctl -f | while read line; do echo "STACK_NAME=$STACK_NAME ACCOUNTID=$ACCOUNTID NODE_ROLE=$NODE_ROLE INSTANCEID=$INSTANCEID HOSTNAME=$HOSTNAME LOG=$line" | ncat --udp localhost 1514;done &
	journalctl -f | while read line; do echo "STACK_NAME=$STACK_NAME ACCOUNTID=$ACCOUNTID NODE_ROLE=$NODE_ROLE INSTANCEID=$INSTANCEID HOSTNAME=$HOSTNAME LOG=$line" | ncat --udp localhost 1515;done 
fi
