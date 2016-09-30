#!/usr/bin/bash -x

source /etc/environment

SCALOCK_ADMIN_PASSWORD=$(etcdctl get /aqua/config/password)
EXTERNAL_URL=$(etcdctl get /aqua/config/gateway-external)


function add_images () {
IMAGE=`etcdctl get /images/$1`
URL_NODOCKER=${IMAGE:16}
REPO=${URL_NODOCKER%:*}
TAG=${URL_NODOCKER#*:}

curl -H "Content-Type: application/json" -g --data '{"images":[{"registry":"Docker Hub","repository":"'"$REPO"'","tag":"'"$TAG"'"}]}' -u administrator:$SCALOCK_ADMIN_PASSWORD $EXTERNAL_URL/api/v1/images --insecure
curl -H "Content-Type: application/json" -g --data '{"images":[{"registry":"Docker Hub","repository":"'"$REPO"'","tag":"'"$TAG"'"}],"comment": "Allowing"}' -u administrator:$SCALOCK_ADMIN_PASSWORD $EXTERNAL_URL/api/v1/images/allow --insecure
}

add_images mesos-slave
add_images splunk
