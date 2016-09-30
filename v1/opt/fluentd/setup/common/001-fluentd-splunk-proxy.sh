#!/usr/bin/bash -x
source /etc/environment
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source $DIR/../../../../lib/helpers.sh

SPLUNK_ENABLE_FLUENTD_PROXY=$(etcd-get /splunk/config/heavyforwarder/fluentd-proxy)
LOGGING_ELB=$(etcd-get /environment/LOGGING_ELB)
SPLUNK_HEAVYFORWARDER_PROXY_PORT=$(etcd-get /splunk/config/heavyforwarder/proxy-port)

#point fluentd to splunk heavyforwarder HEC endpoint since there is no HEC endpoint
if [ "$SPLUNK_ENABLE_FLUENTD_PROXY" == "1" ]; then
        # make sure the the internal ELB value is setup.
        if [ "$LOGGING_ELB" == "" ]; then
                SPLUNK_HEC_ENDPOINT=`etcdctl watch /environment/LOGGING_ELB`
        else
                SPLUNK_HEC_ENDPOINT=$(etcd-get /environment/LOGGING_ELB)
        fi
        #check internal ELB format
        if [[ $SPLUNK_HEC_ENDPOINT =~ ^(https|http)://.*/services/collector ]]; then
                #this will probably not be set correctly so need to format the URL to be compatible
                echo "Setting fluentd-httpext-splunk-url to $SPLUNK_HEC_ENDPOINT"
        else
                #format fluentd endpoint https currently not supported make sure fluentd is set to not secure
                SPLUNK_HEC_ENDPOINT="http://$SPLUNK_HEC_ENDPOINT:$SPLUNK_HEAVYFORWARDER_PROXY_PORT/services/collector"
        fi
        etcd-set /logging/config/fluentd-httpext-splunk-url $SPLUNK_HEC_ENDPOINT
fi


