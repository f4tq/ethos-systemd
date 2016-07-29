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

STOP_TIMEOUT=20
IMAGE=`etcdctl get /images/etcd-locks`
MACHINEID=`cat /etc/machine-id`
LOCKCMD="docker run --net host -i --rm  -e LOCKSMITHCTL_ENDPOINT=${ETCDCTL_PEERS} $IMAGE  locksmithctl --topic coreos_drain --group ${NODE_ROLE} lock $MACHINEID"
UNLOCKCMD="docker run --net host -i --rm  -e LOCKSMITHCTL_ENDPOINT=${ETCDCTL_PEERS} $IMAGE  locksmithctl --topic coreos_drain --group ${NODE_ROLE} unlock $MACHINEID"

error() {
    if [ ! -z "$1" ]; then
	echo $1
    fi
    exit -1
}
get_lockval(){
    etcdctl get /adobe.com/locks/coreos_drain/groups/${NODE_ROLE}/semaphore| jq --arg machineId $MACHINEID '.holders | join(" ")'
}

watch_lock() {
    # etcdctl exec-watch doesn't work on coreos...
    
    orig=$(get_lockval)
    
    while : ; do
	newv=$(get_lockval)
	if [ "$orig" != "$newv" ];then
	    break
	fi
	sleep 5
    done
    eval $*
}
trap_cmd(){
    eval $UNLOCKCMD
}

while : ; do
    eval $LOCKCMD
    status=$?
    if [ $status -eq 0 ]; then
	break
    else
	watch_lock $LOCKCMD
	status=$?
	if [ $status -eq 0 ]; then
	    break
	fi
    fi
done
echo "$(date +%s)|$MACHINE-ID got drain lock"

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

# find_docker_id_by_taskId
#  takes a mesos_task_id and search docker inspect for the matching docker id
#
find_docker_id_by_taskId(){
    taskId="$1"
    if [ -z "$taskId" ]; then
	error "Missing taskId in call to find_docker_id_by_taskId"
    fi
    docker_inspect | jq --arg taskId "$taskId" '.[] | select(.Config.Env[] | contains($taskId ))| .Id'
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
marathon_docker_ids() {
    marathon_jobs | 
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
# drain_docker cycles through docker instances started by mesos

drain_docker() {
    for i in $(marathon_docker_jobs | jq '.[] | .mesos_task_id' ); do
	docker_id=$(find_docker_id_by_taskId $i)
	echo "mesos: $i maps to ${docker_id}"
	NOW=$SECONDS
	MAX=$((SECONDS+ ${STOP_TIMEOUT} ))
	dead=0
	while [ $SECONDS -lt $MAX ]; do
	    docker stop ${docker_id}
	    docker ps -a | grep ${docker_id} | grep -q Exited
	    if [ $? -eq 0]; then
		echo "$(date +%s)|drain_docker: Stopped $i/${docker_id}"
		dead=1
		break
	    fi
	done
	if [ $dead -eq 0 ]; then
	    echo "$(date +%s)|drain_docker: Using a hammer stopping $i/${docker_id}"
	    docker kill ${docker_id}
	fi
    done
}


case "$1" in
    marathon_jobs)
	marathon_jobs
	;;
    marathon_docker_jobs)
	for i in $(marathon_docker_jobs | jq '.[] | .mesos_task_id' ); do
	    docker_id=$(find_docker_id_by_taskId $i)
	    echo "mesos: $i maps to ${docker_id}"
	done
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
        echo <<EOF 
Usage: drain {marathon_jobs|marathon_docker_jobs|host_ports|just_ports|drain_tcp|drain_docker}
Ethos assumptions:  All endpoints are in etcd and that all nodes have access to etcd.

host_ports - outputs the pipe separated list ip:ports for this listening on this slave
just_ports - is just the ports separated by pipes for grep
marathon_jobs - outputs json with the mesos_task_id
marathon_docker_jobs - takes the output of marathon_jobs and search docker_inspect in a xref into the .Config.Env for the task id.  Mesos sets the task id into the docker instances it starts.
drain_tcp - stops the mesos slave and waits for all the ports coming from host_ports in an ESTABLISHED state to drop to zero.
drain_docker - takes 

EOF
        exit 1
        ;;
esac


