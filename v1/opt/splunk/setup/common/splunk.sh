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

#create splunk configuration directory
mkdir -p $SPLUNK_DIR
#generate/fetch secure certs in configurations directory
cat << EOF > /$SPLUNK_DIR/secopsCA.crt
$(etcd-get /splunk/config/secopsca-cert | awk '{gsub(/\\n/,"\n")}1')
EOF

cat << EOF > /$SPLUNK_DIR/secopsForwarder.pem
$(etcd-get /splunk/config/secopsforwarder-cert | awk '{gsub(/\\n/,"\n")}1')
EOF


cat << EOF > /$SPLUNK_DIR/cloudopsCA.crt
$(etcd-get /splunk/config/cloudopsca-cert | awk '{gsub(/\\n/,"\n")}1')
EOF

cat << EOF > /$SPLUNK_DIR/cloudopsForwarder.pem
$(etcd-get /splunk/config/cloudopsforwarder-cert | awk '{gsub(/\\n/,"\n")}1')
EOF

#generate configurtion outputs file
if [ "$SPLUNK_ENABLE_SECOPS_FORWARDER" == "1" ] || [ "$SPLUNK_ENABLE_SECOPS_FORWARDER" == "1" ]; then
cat << EOF > /$SPLUNK_DIR/outputs.conf
[tcpout]
defaultGroup = splunkssl-genericForwarder
maxQueueSize = 7MB
useACK = true
autoLB = true
EOF
fi

if [ "$SPLUNK_ENABLE_SECOPS_FORWARDER" == "1" ]; then
cat << EOF >> /$SPLUNK_DIR/outputs.conf

[tcpout:splunkssl-genericForwarder]
server = $SPLUNK_FORWARD_SECOPS_SERVER_LIST
sslCertPath = /opt/splunk/etc/system/local/secopsForwarder.pem
sslRootCAPath = /opt/splunk/etc/system/local/secopsCA.crt
sslPassword = $SPLUNK_SECOPS_SSLPASSWORD
sslVerifyServerCert = false
EOF
fi

if [ "$SPLUNK_ENABLE_CLOUDOPS_FORWARDER" == "1" ]; then
cat << EOF >> /$SPLUNK_DIR/outputs.conf

[tcpout:splunk-secondaryForwarder]
server = $SPLUNK_FORWARD_CLOUDOPS_SERVER_LIST
sslCertPath = /opt/splunk/etc/system/local/cloudopsForwarder.pem
sslRootCAPath = /opt/splunk/etc/system/local/cloudopsCA.crt
sslPassword = $SPLUNK_CLOUDOPS_SSLPASSWORD
sslVerifyServerCert = false
EOF
fi

