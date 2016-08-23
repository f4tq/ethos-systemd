#!/usr/bin/bash

IMAGE=$(etcdctl get /images/flight-director)

#only set SCALER_ENDPOINT id booster is enabled
SCALER_ENDPOINT=""
if [ "$(etcdctl get /booster/config/enabled)" == "1" ] 
then
  SCALER_ENDPOINT=`etcdctl get /flight-director/config/scaler-endpoint`
fi


/usr/bin/docker run \
  --name flight-director \
  --net='host' \
  -e LOG_APP_NAME=flight-director \
  -e FD_API_SERVER_PORT=`etcdctl get /flight-director/config/api-server-port` \
  -e FD_CHRONOS_MASTER=`etcdctl get /flight-director/config/chronos-master` \
  -e FD_DB_DATABASE=`etcdctl get /flight-director/config/db-name` \
  -e FD_DB_ENGINE=`etcdctl get /flight-director/config/db-engine` \
  -e FD_DB_PASSWORD=`etcdctl get /environment/RDSPASSWORD` \
  -e FD_DB_PATH=`etcdctl get /flight-director/config/db-path` \
  -e FD_DB_USERNAME=`etcdctl get /flight-director/config/db-username` \
  -e FD_MARATHON_USER=`etcdctl get /marathon/config/username` \
  -e FD_MARATHON_PASSWORD=`etcdctl get /marathon/config/password` \
  -e FD_DEBUG=`etcdctl get /flight-director/config/debug` \
  -e FD_DOCKERCFG_LOCATION=`etcdctl get /flight-director/config/dockercfg-location` \
  -e FD_EVENT_INTERFACE=`etcdctl get /flight-director/config/event-interface` \
  -e FD_EVENT_PORT=`etcdctl get /flight-director/config/event-port` \
  -e FD_FIXTURES=`etcdctl get /flight-director/config/fixtures` \
  -e FD_KV_SERVER=`etcdctl get /flight-director/config/kv-server` \
  -e FD_LOG_LEVEL=`etcdctl get /flight-director/config/log-level` \
  -e FD_LOG_LOCATION=`etcdctl get /flight-director/config/log-location` \
  -e FD_LOG_MARATHON_API_CALLS=`etcdctl get /flight-director/config/log-marathon-api-calls` \
  -e FD_MARATHON_MASTER=`etcdctl get /flight-director/config/marathon-master` \
  -e FD_MESOS_MASTER=`etcdctl get /flight-director/config/mesos-master` \
  -e AUTHORIZER_TYPE=`etcdctl get /flight-director/config/authorizer-type` \
  -e FD_IAMROLE_LABEL=`etcdctl get /flight-director/config/iam-role-label` \
  -e FD_AIRLOCK_PUBLIC_KEY="`etcdctl get /flight-director/config/airlock-public-key`" \
  -e FD_MARATHON_MASTER_PROTOCOL=`etcdctl get /flight-director/config/marathon-master-protocol` \
  -e FD_MESOS_MASTER_PROTOCOL=`etcdctl get /flight-director/config/mesos-master-protocol` \
  -e FD_ALLOW_MARATHON_UNVERIFIED_TLS=`etcdctl get /flight-director/config/allow-marathon-unverified-tls` \
  -e FD_SCALER_PROTOCOL=`etcdctl get /flight-director/config/scaler-protocol` \
  -e FD_SCALER_ENDPOINT=$SCALER_ENDPOINT \
  $IMAGE
