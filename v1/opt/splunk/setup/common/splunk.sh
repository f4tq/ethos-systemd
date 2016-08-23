#!/usr/bin/bash -x
source /etc/environment
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source $DIR/../../../../lib/helpers.sh 
SPLUNK_DIR="/opt/splunk/etc/system/local"
SPLUNK_ENABLE_SECOPS_FORWARDER=$(etcd-get /splunk/config/enable-secops-forwarder)
SPLUNK_ENABLE_CLOUDOPS_FORWARDER=$(etcd-get /splunk/config/enable-cloudops-forwarder)
SPLUNK_FORWARD_SECOPS_SERVER_LIST=$(etcd-get /splunk/config/forward-secops-server-list)
SPLUNK_FORWARD_CLOUDOPS_SERVER_LIST=$(etcd-get /splunk/config/forward-cloudops-server-list)
SPLUNK_SECOPS_SSLPASSWORD=$(etcd-get /splunk/config/secops-sslpassword)
SPLUNK_CLOUDOPS_SSLPASSWORD=$(etcd-get /splunk/config/cloudops-sslpassword)
SPLUNK_SECOPS_INDEX=$(etcd-get /splunk/config/secops-index)
SPLUNK_CLOUDOPS_INDEX=$(etcd-get /splunk/config/cloudops-index)
SPLUNK_FORWARDER_HOST=`curl -s http://169.254.169.254/latest/meta-data/hostname`
SPLUNK_CLOUDOPS_CERTPATH_FORMAT=$(etcd-get /splunk/config/cloudops-certpath-format)
SPLUNK_SECOPS_CERTPATH_FORMAT=$(etcd-get /splunk/config/secops-certpath-format)
SPLUNK_CLOUDOPS_ROOTCA_FORMAT=$(etcd-get /splunk/config/cloudops-rootca-format)
SPLUNK_SECOPS_ROOTCA_FORMAT=$(etcd-get /splunk/config/secops-rootca-format)


#create splunk configuration directory
mkdir -p $SPLUNK_DIR
#generate/fetch secure certs in configurations directory
cat << EOF > /$SPLUNK_DIR/secopsCA.$SPLUNK_CLOUDOPS_CERTPATH_FORMAT
$(etcd-get /splunk/config/secopsca-cert | awk '{gsub(/\\n/,"\n")}1')
EOF

cat << EOF > /$SPLUNK_DIR/secopsForwarder.$SPLUNK_CLOUDOPS_ROOTCA_FORMAT
$(etcd-get /splunk/config/secopsforwarder-cert | awk '{gsub(/\\n/,"\n")}1')
EOF


cat << EOF > /$SPLUNK_DIR/cloudopsCA.$SPLUNK_CLOUDOPS_CERTPATH_FORMAT
$(etcd-get /splunk/config/cloudopsca-cert | awk '{gsub(/\\n/,"\n")}1')
EOF

cat << EOF > /$SPLUNK_DIR/cloudopsForwarder.$SPLUNK_CLOUDOPS_ROOTCA_FORMAT
$(etcd-get /splunk/config/cloudopsforwarder-cert | awk '{gsub(/\\n/,"\n")}1')
EOF

#set default groups, default to genericForwarder if cloudops and secops enabled then set if cloudops enabled onyl.
DEFAULTGROUP="splunkssl-genericForwarder"

if [ "$SPLUNK_ENABLE_ClOUDOPS_FORWARDER" == "1" ]; then
  DEFAULTGROUP="splunkssl-secondaryForwarder"
fi
if [ "$SPLUNK_ENABLE_SECOPS_FORWARDER" == "1" ] && [ "$SPLUNK_ENABLE_SECOPS_FORWARDER" == "1" ]; then
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
sourcetype = journald
EOF
fi

if [ "$SPLUNK_ENABLE_SECOPS_FORWARDER" == "1" ]; then
cat << EOF >> /$SPLUNK_DIR/outputs.conf

[tcpout:splunkssl-genericForwarder]
server = $SPLUNK_FORWARD_SECOPS_SERVER_LIST
sslCertPath = /opt/splunk/etc/system/local/secopsForwarder.$SPLUNK_SECOPS_CERTPATH_FORMAT
sslRootCAPath = /opt/splunk/etc/system/local/secopsCA.$SPLUNK_SECOPS_ROOTCA_FORMAT
sslPassword = $SPLUNK_SECOPS_SSLPASSWORD
sslVerifyServerCert = false
EOF

cat << EOF >> /$SPLUNK_DIR/inputs.conf

[udp://1514]
_TCP_ROUTING = splunkssl-genericForwarder
index=$SPLUNK_SECOPS_INDEX
EOF
fi

if [ "$SPLUNK_ENABLE_CLOUDOPS_FORWARDER" == "1" ]; then
cat << EOF >> /$SPLUNK_DIR/outputs.conf

[tcpout:splunkssl-secondaryForwarder]
server = $SPLUNK_FORWARD_CLOUDOPS_SERVER_LIST
sslCertPath = /opt/splunk/etc/system/local/cloudopsForwarder.$SPLUNK_CLOUDOPS_CERTPATH_FORMAT
sslRootCAPath = /opt/splunk/etc/system/local/cloudopsCA.$SPLUNK_CLOUDOPS_ROOTCA_FORMAT
sslPassword = $SPLUNK_CLOUDOPS_SSLPASSWORD
sslVerifyServerCert = false
EOF

cat << EOF >> /$SPLUNK_DIR/inputs.conf

[udp://1515]
_TCP_ROUTING = splunkssl-secondaryForwarder
index=$SPLUNK_CLOUDOPS_INDEX
EOF
fi

