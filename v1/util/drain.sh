#!/bin/bash -x

# This script assumes you already hold the appropriate lock
# It will check to make sure and error out if the lock holder doesn't contain this host's machine-id `cat /etc/machine-id`
#

LOCALPATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source /etc/environment

echo "-------Starting skopos drain-------"

if [ "${NODE_ROLE}" != "worker" ]; then
    >&2 echo "No drain for worker role ${NODE_ROLE}" 
    exit 0
fi

. /etc/profile.d/etcdctl.sh


error() {
    if [ ! -z "$1" ]; then
	echo $1
    fi
    exit -1
}

# Get out local ip
LOCAL_IP="$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)"

# Get marathon info from etcd
MARATHON_USER="$(etcdctl get /marathon/config/username)"
MARATHON_PASSWORD="$(etcdctl get /marathon/config/password)"
MARATHON_ENDPOINT="$(etcdctl get /flight-director/config/marathon-master)"

MARATHON_CREDS=""
if [ ! -z "${MARATHON_USER}" -a ! -z "${MARATHON_PASSWORD}" ];then
   MARATHON_CREDS="-u ${MARATHON_USER}:${MARATHON_PASSWORD}"
fi

# docker can be long running and slow.  cache this once

tmpdir=${TMPDIR-/tmp}/skopos-$RANDOM-$$
mkdir -p $tmpdir
trap 'ret=$?; rmdir "$tmpdir"  2>/dev/null; exit $ret' 0
DOCKER_INSPECT="$tmpdir/docker_inspect_$(date +%s)"

docker inspect $(docker ps -q) > $DOCKER_INSPECT

docker_inspect(){
    cat ${DOCKER_INSPECT}
}

find_docker_id_by_taskId(){
    taskId="$1"
    if [ -z "$taskId" ]; then
	error "Missing taskId in call to find_docker_id_by_taskId"
    fi
    docker_inspect | jq --arg taskId  '.[] | select(.Config.Env[] | contains($taskId ))| .Id'
}


# Getting the slave Id.
SLAVE_CACHE="$tmpdir/mesos_slave_$(date +%s)"
curl -SsfLk http://${LOCAL_IP}:5051/state > ${SLAVE_CACHE}

slave_info(){
    cat ${SLAVE_CACHE}
}

SLAVE_ID=$( slave_info | jq .id)
if [ -z "${SLAVE_ID}" ]; then
    error "No slave id found.  Is the mesos-slave running?"
fi

SLAVE_HOST=$( slave_info | jq .hostname)

find_all_mesos_docker_instances(){
    # Mesos creates docker instances for potentially many frameworks.  Marathon is just one
    docker_inspect | jq '[.[] | select( .Name | startswith("/mesos-")) | { name: .Name, id: .Id}]'
}


read -d '' marathon_jq <<'EOF'
   [.tasks[] | select( .slaveId == $slaveId)|  .host as $host| .servicePorts as $outside | .ports as $inside | .appId as $appId | reduce range(0, $inside |length) as $i ( .mapping;  . + [($host+":"+($inside[$i] | tostring))] )| { host: $host, slaveId: $slaveId, appId: $appId, mappings: .} ]
EOF


# Get jobs assigned to this slave
#   If tags are used, the jq can be refined
#  
THIS_SLAVES_MARATHON_JOBS=$(curl -sSfLk -m 10 ${MARATHON_CREDS} ${MARATHON_ENDPOINT}/v2/tasks |
			     jq --arg slaveId ${SLAVE_ID} '[
        .tasks[]  
        | select( .slaveId == $slaveId) 
        | .host as $host| .servicePorts as $outside | .ports as $inside | .appId as $appId 
        | reduce range(0, $inside |length) as $i ( .mapping;  . + [($host+":"+($inside[$i] | tostring))] )| { host: $host, slaveId: $slaveId, appId: $appId, mappings: .} 
        ]')

: <<'example_output'
Given slaveId=4a98185c-2c2b-40ca-81b2-c58dfe4a1576-S1
[
  {
    "host": "172.16.29.181",
    "slaveId": "4a98185c-2c2b-40ca-81b2-c58dfe4a1576-S1",
    "mesos_task_id": "jenkins.9141ce32-5055-11e6-84ac-ea00985491e4",
    "appId": "/jenkins",
    "mappings": [
      "172.16.29.181:17912",
      "172.16.29.181:17913"
    ]
  }
]
example_output


marathon_jobs() {
    echo "${THIS_SLAVES_MARATHON_JOBS}"
}
host_ports() {
    # pre-made for egrep
    marathon_jobs | jq 'reduce .[] as $list ([] ; . + $list.mappings)| join("|")'
}
just_ports() {
    # egrep ready.
    # just ports.  Put out a leading ':' after the join
    marathon_jobs | jq 'reduce .[] as $list ([] ; . + $list.mappings)| reduce .[] as $foo ([] ; . + [($foo| split(":")|last)])| join("|:") |  if ( . | length ) > 0 then  ":" + . else . end'
}

drain_tcp() {
    # stop the slave
    TIMEOUT=[[ $SECONDS + 900 ]]
    DRAIN_PORTS=1
    if [ ! -z "$(just_ports)" ] ;then
	DRAIN_PORTS=0
    fi
    while :; do
	if [ 0 -eq ${DRAIN_PORTS} ] ;then
	    break
	fi
	cnt=$(ss -t | grep ESTAB | egrep  just_ports | wc -l)
	if [ $cnt == "0" ]; then
	    echo "All done draining port $(just_ports)"
	fi
	if [[ $SECONDS > $TIMEOUT ]]; then
            echo "Timeout ..."
            break
	fi
    done
}



case "$1" in
    marathon_jobs)
	marathon_jobs
	;;
    host_ports)
	host_ports
	;;
    just_ports)
	just_ports
	;;
    drain_tcp)
	drain_tcp
	;;
    drain_docker)
	drain_docker
	;;
    drain)
	drain_tcp
	drain_docker
	;;

    *)
        echo "Usage: drain {marathon_jobs|host_ports|just_ports|drain_tcp|drain_docker}"
        exit 1
        ;;
esac


