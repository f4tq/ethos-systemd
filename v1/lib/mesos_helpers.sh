#!/usr/bin/bash
MESOSLIB="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source $MESOSLIB/vercomp.sh

set -x

MESOS_UNIT=$(systemctl list-units | egrep 'dcos-mesos-slave|mesos-slave@|dcos-mesos-master|mesos-master'| awk '{ print $1}' )

MESOS_USER="$(etcdctl get /mesos/config/username  2>/dev/null)"
MESOS_PW="$(etcdctl get /mesos/config/password  2>/dev/null)"
MESOS_CREDS=""
if [ ! -z "${MESOS_USER}" -a ! -z "${MESOS_PW}" ];then
   MESOS_CREDS="-u ${MESOS_USER}:${MESOS_PW}"
fi
MESOS_PROTO=http
if [ 0 -lt $( systemctl list-units | grep -c 'dcos-') ]; then
    # dns can lag behind what /redirect sez.
    MESOS_MASTER="leader.mesos:5050"
    MESOS_URL="http://${MESOS_MASTER}"
# on reboot, it can take a bit before.  make sure spartan gives us something
    until (ping -c 1 leader.mesos) ; do
	sleep 1
    done
elif ( etcdctl get /flight-director/config/mesos-master >/dev/null 2>&1 ); then
    MESOS_MASTER=$(etcdctl get /flight-director/config/mesos-master)
    MESOS_PROTO=$(etcdctl get /flight-director/config/mesos-master-protocol)
else
    error "Don't know where mesos master is located"
fi
MESOS_ELB="${MESOS_PROTO}://${MESOS_MASTER}"


#
# we need to use the redirect because dc/os dns strangely lags what mesos thinks is master
#
#MESOS_MASTER=$(curl -sI ${MESOS_CREDS} ${MESOS_URL}/redirect | grep Location | awk -F'Location: //' '{ print $2}'| awk '{ print $1}')

# true master comes from redirect.  anything else is bunk
MESOS_MASTER=""
while [ -z "${MESOS_MASTER}" ]; do
    MESOS_MASTER=$(curl -svI ${MESOS_CREDS} ${MESOS_ELB}/redirect | grep Location | tr -d '\r\n' | sed  's!Location: //\(.*\)!\1!')
    sleep 1
done
MESOS_URL="${MESOS_PROTO}://${MESOS_MASTER}"


MESOS_VERSION="$(curl -SsL -X GET ${MESOS_CREDS} ${MESOS_URL}/version | jq -r '.version')"

USE_MESOS_API=true
set +x
vercomp ${MESOS_VERSION} 0.28.0
set -x
if [ $? -ne 1  ]; then
    USE_MESOS_API=false
fi



# Get marathon info from etcd
MARATHON_USER="$(etcdctl get /marathon/config/username)"
MARATHON_PASSWORD="$(etcdctl get /marathon/config/password)"
MARATHON_ENDPOINT="$(etcdctl get /flight-director/config/marathon-master)"

MARATHON_CREDS=""
if [ ! -z "${MARATHON_USER}" -a ! -z "${MARATHON_PASSWORD}" ];then
   MARATHON_CREDS="-u ${MARATHON_USER}:${MARATHON_PASSWORD}"
fi

set +x 

