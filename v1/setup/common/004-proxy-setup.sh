#!/bin/bash -x

source /etc/environment

if [ "$NODE_ROLE" != "proxy" ]; then
    exit 0
fi

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source $DIR/../../lib/helpers.sh

echo "-------Beginning proxy setup-------"

PROXY_SETUP_IMAGE=$(etcd-get /images/proxy-setup)

if [ -f /etc/profile.d/etcdctl.sh ]; then 
      source /etc/profile.d/etcdctl.sh
fi

docker run \
    --name mesos-proxy-setup \
    --net='host' \
    --privileged \
    --log-opt max-size=$(etcdctl get /docker/config/logs-max-size) \
    --log-opt max-file=$(etcdctl get /docker/config/logs-max-file) \
    ${PROXY_SETUP_IMAGE}

echo "-------Done proxy setup-------"
