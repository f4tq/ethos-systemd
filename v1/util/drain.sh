#!/bin/bash 

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

if [ -f /etc/profile.d/etcdctl.sh ]; then
    . /etc/profile.d/etcdctl.sh
fi

STOP_TIMEOUT=20

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
#
#  A temp directory for cached output
# 
tmpdir=${TMPDIR-/tmp}/skopos-$RANDOM-$$
mkdir -p $tmpdir
trap 'ret=$?; rmdir "$tmpdir"  2>/dev/null; exit $ret' 0

# Cached files
DOCKER_INSPECT="$tmpdir/docker_inspect_$(date +%s)"
SLAVE_CACHE="$tmpdir/mesos_slave_$(date +%s)"
THIS_SLAVES_MARATHON_JOBS=""

##########

###  Functions

##########
#
# Marathon: - Get jobs assigned to this slave
#   If tags are used on the stanzas, epecially wrt Shared Cloud, the jq can be refined to pick that up and map to shutdown (docker stop)
#
# update_marathon_jobs
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

update_marathon_jobs(){
    SLAVE_ID=$1
    curl -sSfLk -m 10 ${MARATHON_CREDS} ${MARATHON_ENDPOINT}/v2/tasks |
			     jq -r --arg slaveId ${SLAVE_ID} '[
        .tasks[]  
        | select( .slaveId == $slaveId) 
        | .host as $host| .servicePorts as $outside | .ports as $inside | .appId as $appId | .id as $mesos_id 
        | reduce range(0, $inside |length) as $i ( .mapping;  . + [($host+":"+($inside[$i] | tostring))] )| { mesos_task_id: $mesos_id, host: $host, slaveId: $slaveId, appId: $appId, mappings: .} 
        ]'

}

#
# docker can be long running and slow on a busy host.  cache this once
#  
# This gets run again after we acquire the lock
#

update_docker_inspect(){
    docker inspect $(docker ps -q) | tee $DOCKER_INSPECT
}

error() {
    if [ ! -z "$1" ]; then
	echo $1
    fi
    exit -1
}

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
    docker_inspect | jq -r --arg taskId "$taskId" '.[] | select(.Config.Env[] | contains($taskId ))| .Id'
}

#
# slave info
#
# Make sure curl worked to host and that it got back something
#
update_slave_info() {
    curl -SsfLk http://${LOCAL_IP}:5051/state > /tmp/fake
    if [ $? -eq 0 -a -s /tmp/fake ]; then
	mv /tmp/fake ${SLAVE_CACHE}
	cat ${SLAVE_CACHE}
    else
	echo
    fi
}

slave_info(){
    if [ ! -f "${SLAVE_CACHE}" -o ! -s "${SLAVE_CACHE}" ]; then
	update_slave_info
    else
	# TODO: may want to check freshness
	cat ${SLAVE_CACHE}
    fi
}

find_all_mesos_docker_instances(){
    # Mesos creates docker instances for potentially many frameworks.  Marathon is just one
    docker_inspect | jq '[.[] | select( .Name | startswith("/mesos-")) | { name: .Name, id: .Id}]'
}

marathon_jobs() {
    echo "${THIS_SLAVES_MARATHON_JOBS}"
}
show_marathon_docker_ids() {
    for i in $(marathon_jobs | jq -r '.[] | .mesos_task_id' ); do
	docker_id=$(find_docker_id_by_taskId $i)
	echo "marathon/mesos_task_id: $i maps to docker_id: ${docker_id}"
    done
}

host_ports() {
    # pre-made for egrep
    marathon_jobs | jq -r 'reduce .[] as $list ([] ; . + $list.mappings)| join("|")'
}

just_ports() {
    # egrep ready.
    # just ports.  Put out a leading ':' after the join
    marathon_jobs | jq -r 'reduce .[] as $list ([] ; . + $list.mappings)| reduce .[] as $foo ([] ; . + [($foo| split(":")|last)])| join("|:") |  if ( . | length ) > 0 then  ":" + . else . end'
}

drain_tcp() {
    # stop the slave
    TIMEOUT=$(( $SECONDS + 900 )) 
    DRAIN_PORTS=1
    if [  -z "$(just_ports)" ] ;then
	DRAIN_PORTS=0
    fi
    while :; do
	if [ 0 -eq ${DRAIN_PORTS} ] ;then
	    break
	fi
	cnt=$(ss -t | grep ESTAB | egrep -c $(just_ports))
	if [ $cnt -eq 0 ]; then
	    echo "No more remaining connections $(just_ports).  Done draining ports"
	    break
        else
	    echo "$cnt remainings connections"
	fi
	if [[ $SECONDS > $TIMEOUT ]]; then
            echo "Timeout ... with $cnt remaining connections"
          
            break
	fi
        sleep 1
    done
}
# drain_docker cycles through docker instances started by mesos

marathon_docker_ids(){
    for i in $(marathon_jobs | jq -r '.[] | .mesos_task_id' ); do
	echo $(find_docker_id_by_taskId $i)
    done
}
marat(){
  ID=""
  for i in $(marathon_docker_ids); do
     ID="$ID|$i"
  done
  echo $ID
}

drain_docker() {
    
    # stop all the docker instances
    for i in $(marathon_docker_ids) ; do
	echo docker stop ${i}
    done

    NOW=$SECONDS

    MAX=$((SECONDS+ ${STOP_TIMEOUT} ))
    dead=0
    
    while [ $SECONDS -lt $MAX ]; do
         cnt=$(docker ps -q | egrep -c "$(marat)")
         if [ $cnt -eq 0 ]; then
	     echo "$(date +%s)|drain_docker: Stopped $i/${docker_id}"
             dead=1
             break
         fi
         sleep 1
         echo "$SECONDS. Waiting for $cnt to stop"
    done
    
    echo "Giving up.  killing docker instances"
    for j in $(docker ps -q | egrep "$(marat)"); do
	echo docker kill $j 
    done
}

 
drain(){
    if [ 0 -ne $(host_lock "DRAIN") ];then
	state=$(host_state)
	error "Can't get local host lock.  state: $state"
    fi
    mesos_unit=$(systemctl list-units | egrep 'mesos-slave@|dcos-mesos-slave' | awk '{ print $1}')
    
    host_lock "DRAIN"
    status=$?
    if [ $status -eq 0 ]; then
	break
    else
	state=$(host_state)
	error "Unknown state.  Aborting"
    fi
    echo "$(date +%s)|$MACHINE-ID got drain lock"
    # update docker inspect just in case the lock took a while to get
    DOCKER_INSPECT="$tmpdir/docker_inspect_$(date +%s)"
    drain_tcp
    drain_docker
    host_unlock "DRAIN"
}

if [ ! -z "$1" ];then
    # Get docker info
    
    if [ -z "$(update_docker_inspect)" ]; then
	# TODO: error for now, but actually edge case.
	# Nothing is running so just drain
	error "No docker instances"
    fi
    if [ -z "$(  update_slave_info )" ] ;then
	error "No slave info. Is slave running?"
    fi
    # Getting the slave Id.
    SLAVE_ID=$( slave_info | jq -r .id)
    if [ -z "${SLAVE_ID}" ]; then
	error "No slave id found.  Is the mesos-slave running?"
    fi
    SLAVE_HOST=$( slave_info | jq -r .hostname)
    

    # Get marathon info filtered by this slave
    THIS_SLAVES_MARATHON_JOBS=$(update_marathon_jobs $SLAVE_ID)
fi

case "$1" in

    marathon_jobs)
	marathon_jobs
	;;
    marathon_docker_ids)
	show_marathon_docker_ids
        set -x
        marat
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


