#!/usr/bin/bash -x
source /etc/environment
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source $DIR/../../../../lib/helpers.sh

if [ "${NODE_ROLE}" != "logging" ]; then
    exit 0
fi

SPLUNK_DIR="/opt/splunk-fluentd/etc/system/local"
SPLUNK_ENABLE_CLOUDOPS_FORWARDER=$(etcd-get /splunk/config/cloudops/enable-forwarder)
SPLUNK_ENABLE_HEC_FORWARDER=$(etcd-get /splunk/config/hec/enable-forwarder)
SPLUNK_FORWARD_CLOUDOPS_SERVER_LIST=$(etcd-get /splunk/config/cloudops/forward-server-list)
SPLUNK_CLOUDOPS_SSLPASSWORD=$(etcd-get /splunk/config/cloudops/sslpassword)
SPLUNK_CLOUDOPS_INDEX=$(etcd-get /splunk/config/cloudops/index)
SPLUNK_FORWARDER_HOST=`curl -s http://169.254.169.254/latest/meta-data/hostname`
SPLUNK_CLOUDOPS_CERTPATH_FORMAT=$(etcd-get /splunk/config/cloudops/certpath-format)
SPLUNK_CLOUDOPS_ROOTCA_FORMAT=$(etcd-get /splunk/config/cloudops/rootca-format)
SPLUNK_HEC_TOKEN=$(etcd-get /logging/config/fluentd-httpext-splunk-hec-token)
SPLUNK_HEC_ENDPOINT=$(etcd-get /logging/config/fluentd-httpext-splunk-url)
SPLUNK_HEC_DEFAULT_INDEX=$(etcd-get /splunk/config/hec/default-index)
SPLUNK_ENABLE_FLUENTD_PROXY=$(etcd-get /splunk/config/heavyforwarder/fluentd-proxy)
SPLUNK_ENABLE_JOURNALD_PROXY=$(etcd-get /splunk/config/heavyforwarder/journald-proxy)
SPLUNK_HEAVYFORWARDER_DEFAULT_PORT=$(etcd-get /splunk/config/heavyforwarder/default-port)
SPLUNK_HEAVYFORWARDER_PROXY_PORT=$(etcd-get /splunk/config/heavyforwarder/proxy-port)
SPLUNK_HEAVYFORWARDER_FLUENTD_TOKEN=$(etcd-get /splunk/config/heavyforwarder/fluentd-token)
SPLUNK_HEAVYFORWARDER_SYSTEM_TOKEN=$(etcd-get /splunk/config/heavyforwarder/system-token)

#create splunk configuration directory
mkdir -p $SPLUNK_DIR


DEFAULTGROUP="splunkssl"
DEFAULTINDEX=$SPLUNK_CLOUDOPS_INDEX

#always setup default listener
cat << EOF > /$SPLUNK_DIR/inputs.conf
[tcp://$SPLUNK_HEAVYFORWARDER_DEFAULT_PORT]
index = $DEFAULTINDEX
_TCP_ROUTING = $DEFAULTGROUP
EOF

# enable HEC listener for fluentd customer logs cerauth passthrough and journald system logs hec passthrough
if [ "$SPLUNK_ENABLE_FLUENTD_PROXY" == "1" ] || [ "$SPLUNK_ENABLE_JOURNALD_PROXY" == "1" ]; then
cat << EOF >> /$SPLUNK_DIR/inputs.conf

[http]
disabled = 0
enableSSL = 0
port = $SPLUNK_HEAVYFORWARDER_PROXY_PORT
outputGroup = splunkssl
EOF
fi

#setup token for customer logs
if [ "$SPLUNK_ENABLE_FLUENTD_PROXY" == "1" ]; then
#make sure the token is set to the same as fluentd is set to auth with
SPLUNK_HEAVYFORWARDER_FLUENTD_TOKEN=$SPLUNK_HEC_TOKEN
cat << EOF >> /$SPLUNK_DIR/inputs.conf

[http://ethos]
token = $SPLUNK_HEAVYFORWARDER_FLUENTD_TOKEN
disabled = 0
EOF
fi

# setup token for system logs
if [ "$SPLUNK_ENABLE_JOURNALD_PROXY" == "1" ]; then
cat << EOF >> /$SPLUNK_DIR/inputs.conf

[http://system]
token = $SPLUNK_HEAVYFORWARDER_SYSTEM_TOKEN
index = $SPLUNK_CLOUDOPS_INDEX
outputGroup = splunkhec
disabled = 0
EOF
fi

#setup props listeners
cat << EOF > /$SPLUNK_DIR/props.conf
[source::tcp:9997]
TRANSFORMS-index = default_index
TRANSFORMS-sourcetype = default_sourcetype
EOF


#setup default transforms.conf configuration this will be updated via api from marathon imagedef extraction
cat << EOF > /$SPLUNK_DIR/transforms.conf
[default_index]
REGEX = .
DEST_KEY = _MetaData:Index
FORMAT = $SPLUNK_HEC_DEFAULT_INDEX

[default_sourcetype]
REGEX = .
DEST_KEY = MetaData:Sourcetype
FORMAT = sourcetype::json

EOF

#Setup default values for outputs.conf
cat << EOF > /$SPLUNK_DIR/outputs.conf
[default]
defaultGroup = splunkssl
EOF

if [ "$SPLUNK_ENABLE_CLOUDOPS_FORWARDER" == "1" ] || [ "$SPLUNK_ENABLE_FLUENTD_PROXY" == "1" ]; then
#Generate CloudOps Certs
cat << EOF > /$SPLUNK_DIR/cloudopsCA.$SPLUNK_CLOUDOPS_ROOTCA_FORMAT
$(etcd-get /splunk/config/cloudops/ca-cert | awk '{gsub(/\\n/,"\n")}1')
EOF
cat << EOF > /$SPLUNK_DIR/cloudopsForwarder.$SPLUNK_CLOUDOPS_CERTPATH_FORMAT
$(etcd-get /splunk/config/cloudops/forwarder-cert | awk '{gsub(/\\n/,"\n")}1')
EOF

#generate forwardering endpoints
cat << EOF >> /$SPLUNK_DIR/outputs.conf

[tcpout:splunkssl]
server = $SPLUNK_FORWARD_CLOUDOPS_SERVER_LIST
sslCertPath = /opt/splunk/etc/system/local/cloudopsForwarder.$SPLUNK_CLOUDOPS_CERTPATH_FORMAT
sslRootCAPath = /opt/splunk/etc/system/local/cloudopsCA.$SPLUNK_CLOUDOPS_ROOTCA_FORMAT
sslPassword = $SPLUNK_CLOUDOPS_SSLPASSWORD
EOF
fi

#Forwarding to HEC splunk indexer else use cert based cloudops endpoints
if [ "$SPLUNK_ENABLE_HEC_FORWARDER" == "1" ] || [ "$SPLUNK_ENABLE_JOURNALD_PROXY" == "1" ]; then
	#grab HEC token from splunk keys if not set for fluentd
	if [ $SPLUNK_HEC_TOKEN == "" ]; then
		SPLUNK_HEC_TOKEN=$(etcd-get /splunk/config/hec/token)
	fi
	if [ $SPLUNK_HEC_ENDPOINT == "" ]; then
		SPLUNK_HEC_ENDPOINT=$(etcd-get /splunk/config/hec/endpoint)
	fi
	#make sure teh endpoint is formated correctly remove https:// and URI from fluentd endpoint
	if [[ $SPLUNK_HEC_ENDPOINT =~ ^(https|http)://.*/services/collector ]]; then
		SPLUNK_HEC_ENDPOINT=`echo $SPLUNK_HEC_ENDPOINT | awk -F "/" '{print $3}'`
	fi
	if [ "$SPLUNK_HEC_TOKEN" == "" ] || [ $SPLUNK_HEC_ENDPOINT == "" ]; then
		echo "ERROR: Invalid Configurations for Splunk HEC: HEC Token or Endpoint not set correctly check your etcd keys for logging or splunk"
	else
cat << EOF >> /$SPLUNK_DIR/outputs.conf

[tcpout:splunkhec]
token = $SPLUNK_HEC_TOKEN
server = $SPLUNK_HEC_ENDPOINT:443
EOF
	fi
fi
