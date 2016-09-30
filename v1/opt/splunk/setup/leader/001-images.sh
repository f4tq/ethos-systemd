#!/usr/bin/bash -x

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source $DIR/../../../../lib/helpers.sh

etcd-set /images/splunk					"index.docker.io/adobeplatform/docker-splunk:v1.0.0"
etcd-set /images/logging-config			"index.docker.io/adobeplatform/logging-config:latest"
etcd-set /images/splunk-heavyforwarder	"index.docker.io/adobeplatform/docker-splunk:heavyforwarder-latest"
etcd-set /images/splunk					"index.docker.io/adobeplatform/docker-splunk:latest"
