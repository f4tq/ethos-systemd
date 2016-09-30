#!/usr/bin/bash -x
source /etc/environment
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source $DIR/../../../../lib/helpers.sh 
SPLUNK_DIR="/opt/splunk/etc/system/local"
SPLUNK_ENABLE_SECOPS_FORWARDER=$(etcd-get /splunk/config/secops/enable-forwarder)
SPLUNK_ENABLE_CLOUDOPS_FORWARDER=$(etcd-get /splunk/config/cloudops/enable-forwarder)
SPLUNK_FORWARD_SECOPS_SERVER_LIST=$(etcd-get /splunk/config/secops/forward-server-list)
SPLUNK_FORWARD_CLOUDOPS_SERVER_LIST=$(etcd-get /splunk/config/cloudops/forward-server-list)
SPLUNK_SECOPS_SSLPASSWORD=$(etcd-get /splunk/config/secops/sslpassword)
SPLUNK_CLOUDOPS_SSLPASSWORD=$(etcd-get /splunk/config/cloudops/sslpassword)
SPLUNK_SECOPS_INDEX=$(etcd-get /splunk/config/secops/index)
SPLUNK_CLOUDOPS_INDEX=$(etcd-get /splunk/config/cloudops/index)
SPLUNK_CLOUDOPS_SOURCETYPE=$(etcd-get /splunk/config/cloudops/sourcetype)
SPLUNK_SECOPS_SOURCETYPE=$(etcd-get /splunk/config/secops/sourcetype)
SPLUNK_FORWARDER_HOST=`curl -s http://169.254.169.254/latest/meta-data/hostname`
SPLUNK_CLOUDOPS_CERTPATH_FORMAT=$(etcd-get /splunk/config/cloudops/certpath-format)
SPLUNK_SECOPS_CERTPATH_FORMAT=$(etcd-get /splunk/config/secops/certpath-format)
SPLUNK_CLOUDOPS_ROOTCA_FORMAT=$(etcd-get /splunk/config/cloudops/rootca-format)
SPLUNK_SECOPS_ROOTCA_FORMAT=$(etcd-get /splunk/config/secops/rootca-format)
SPLUNK_UNIVERSALFORWARDER_SECOPS_PORT==$(etcd-get /splunk/config/universalforwarder/secops-port)
SPLUNK_UNIVERSALFORWARDER_CLOUDOPS_PORT==$(etcd-get /splunk/config/universalforwarder/cloudops-port)

#create splunk configuration directory
mkdir -p $SPLUNK_DIR

#set default groups, default to genericForwarder if cloudops and secops enabled then set if cloudops enabled onyl.
DEFAULTGROUP="splunkssl-genericForwarder"

if [ "$SPLUNK_ENABLE_CLOUDOPS_FORWARDER" == "1" ]; then
  DEFAULTGROUP="splunkssl-secondaryForwarder"
fi
if [ "$SPLUNK_ENABLE_SECOPS_FORWARDER" == "1" ] && [ "$SPLUNK_ENABLE_CLOUDOPS_FORWARDER" == "1" ]; then
  DEFAULTGROUP="splunkssl-genericForwarder,splunkssl-secondaryForwarder"
fi
#generate configurtion outputs file
if [ "$SPLUNK_ENABLE_SECOPS_FORWARDER" == "1" ] || [ "$SPLUNK_ENABLE_CLOUDOPS_FORWARDER" == "1" ]; then
cat << EOF > /$SPLUNK_DIR/outputs.conf
[tcpout]
defaultGroup = $DEFAULTGROUP
maxQueueSize = 7MB
useACK = true
autoLB = true
EOF

cat << EOF > /$SPLUNK_DIR/inputs.conf
[default]
host = $SPLUNK_FORWARDER_HOST
connection_host = none
sourcetype = syslog
EOF
fi

if [ "$SPLUNK_ENABLE_SECOPS_FORWARDER" == "1" ]; then
#generate certs
cat << EOF > /$SPLUNK_DIR/secopsCA.$SPLUNK_SECOPS_ROOTCA_FORMAT
$(etcd-get /splunk/config/secops/ca-cert | awk '{gsub(/\\n/,"\n")}1')
EOF

cat << EOF > /$SPLUNK_DIR/secopsForwarder.$SPLUNK_SECOPS_CERTPATH_FORMAT
$(etcd-get /splunk/config/secops/forwarder-cert | awk '{gsub(/\\n/,"\n")}1')
EOF

cat << EOF >> /$SPLUNK_DIR/outputs.conf

[tcpout:splunkssl-genericForwarder]
server = $SPLUNK_FORWARD_SECOPS_SERVER_LIST
sslCertPath = /opt/splunk/etc/system/local/secopsForwarder.$SPLUNK_SECOPS_CERTPATH_FORMAT
sslRootCAPath = /opt/splunk/etc/system/local/secopsCA.$SPLUNK_SECOPS_ROOTCA_FORMAT
sslPassword = $SPLUNK_SECOPS_SSLPASSWORD
sslVerifyServerCert = false
EOF

cat << EOF >> /$SPLUNK_DIR/inputs.conf

[udp://$SPLUNK_UNIVERSALFORWARDER_SECOPS_PORT]
_TCP_ROUTING = splunkssl-genericForwarder
index=$SPLUNK_SECOPS_INDEX
sourcetype=$SPLUNK_SECOPS_SOURCETYPE
EOF
fi

if [ "$SPLUNK_ENABLE_CLOUDOPS_FORWARDER" == "1" ]; then
#generate certs
cat << EOF > /$SPLUNK_DIR/cloudopsCA.$SPLUNK_CLOUDOPS_ROOTCA_FORMAT
$(etcd-get /splunk/config/cloudops/ca-cert | awk '{gsub(/\\n/,"\n")}1')
EOF

cat << EOF > /$SPLUNK_DIR/cloudopsForwarder.$SPLUNK_CLOUDOPS_CERTPATH_FORMAT
$(etcd-get /splunk/config/cloudops/forwarder-cert | awk '{gsub(/\\n/,"\n")}1')
EOF
cat << EOF >> /$SPLUNK_DIR/outputs.conf

[tcpout:splunkssl-secondaryForwarder]
server = $SPLUNK_FORWARD_CLOUDOPS_SERVER_LIST
sslCertPath = /opt/splunk/etc/system/local/cloudopsForwarder.$SPLUNK_CLOUDOPS_CERTPATH_FORMAT
sslRootCAPath = /opt/splunk/etc/system/local/cloudopsCA.$SPLUNK_CLOUDOPS_ROOTCA_FORMAT
sslPassword = $SPLUNK_CLOUDOPS_SSLPASSWORD
sslVerifyServerCert = false
EOF

cat << EOF >> /$SPLUNK_DIR/inputs.conf

[udp://$SPLUNK_UNIVERSALFORWARDER_CLOUDOPS_PORT]
_TCP_ROUTING = splunkssl-secondaryForwarder
index=$SPLUNK_CLOUDOPS_INDEX
sourcetype=$SPLUNK_CLOUDOPS_SOURCETYPE
EOF
fi

