#!/bin/bash 

# This script assumes you already hold the appropriate lock
# It will check to make sure and error out if the lock holder doesn't contain this host's machine-id `cat /etc/machine-id`
#

LOCALPATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source /etc/environment

2> echo "-------Starting skopos drain-------"

if [ "${NODE_ROLE}" != "worker" ]; then
    >&2 echo "No drain for non-worker role ${NODE_ROLE}"
    exit 0
fi

if [ -f /etc/profile.d/etcdctl.sh ]; then
    . /etc/profile.d/etcdctl.sh
fi

source $LOCALPATH/../lib/lock_helpers.sh

assert_root
tmpdir=${TMPDIR-/tmp}/skopos-$RANDOM-$$
mkdir -p $tmpdir
on_exit 'rmdir "$tmpdir" 2>/dev/null'

verbose=false
STOP_TIMEOUT=20

# Get out local ip
LOCAL_IP="$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)"
MESOS_UNIT=$(systemctl list-units | egrep 'dcos-mesos-slave|mesos-slave@'| awk '{ print $1}' )

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
    procs="$(docker ps -q)"
    if [ -z "$procs" ];then
	echo -n "" | tee $DOCKER_INSPECT
    else
	docker inspect $procs | tee $DOCKER_INSPECT
    fi
}

#
# cached file rep. docker inspect can be slow
#
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
#  Return pid of docker task.  Can be used trace all processes in a docker instance
#
find_docker_pid_by_taskId(){
    taskId="$1"
    if [ -z "$taskId" ]; then
	error "Missing taskId in call to find_docker_id_by_taskId"
    fi
    docker_inspect | jq -r --arg taskId "$taskId" '.[] | select(.Config.Env[] | contains($taskId ))| .State.Pid'
}
#
# Parses docker inspect to return tasks Network mode.
#
find_docker_networkmode_by_taskId(){
    taskId="$1"
    if [ -z "$taskId" ]; then
	error "Missing taskId in call to find_docker_id_by_taskId"
    fi
    docker_inspect | jq -r --arg taskId "$taskId" '.[] | select(.Config.Env[] | contains($taskId ))| .HostConfig.NetworkMode'
}
# output the whole stanza given the mesos taskId
find_docker_stanza_by_taskId(){
    taskId="$1"
    if [ -z "$taskId" ]; then
	error "Missing taskId in call to find_docker_id_by_taskId"
    fi
    docker_inspect | jq -r --arg taskId "$taskId" '.[] | . as $d | select(.Config.Env[] | contains($taskId ))| $d'
}

#
# Produces process tree given docker pid taken from docker inspect
# 
process_list(){
    pid=$1
    ps --forest -o pid= $(ps -e --no-header -o pid,ppid|awk -vp=$pid 'function r(s){print s;s=a[s];while(s){sub(",","",s);t=s;sub(",.*","",t);sub("[0-9]+","",s);r(t)}}{a[$2]=a[$2]","$1}END{r(p)}')
}
#
#  Takes list of pids, finds listening sockets, and converts 0.0.0.0 into a pattern that will match any socket
#
listening_tcp(){
    sudo netstat -tnlp | grep $(process_list $1| xargs -n 1 -IXX echo " -e XX") 
}
#
#  Takes a list of patterned listening sockets and makes it friendly for grep
#
listening_patterns(){
    listening_tcp $1 | awk '{print $4}'| sed 's/0.0.0.0/[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/'| xargs -n 1 -I XX echo " -e XX"
}
# output the whole stanza given the mesos taskId

get_fw_rules(){
    taskId=$1
    mode=$(find_docker_networkmode_by_taskId $taskId)
    case "$mode" in
	bridge)
	    #
	    #      this                                    V is .[] with all
	    #
            find_docker_stanza_by_taskId $taskId | jq -r ' . | .NetworkSettings as $in | 
             $in.Ports|keys[] |  
             if ( $in.Ports[.] | length) > 0 then 
                 [ "iptables -A SKOPOS -p ", (. | split("/") | last)," --dport ",(. | split("/") | first),"-d",$in.Networks.bridge.IPAddress, "-j REJECT "]|join(" ")  
             else ""  end'
	    ;;
	host)
	    pid=$(find_docker_pid_by_taskId $taskId)
	    for hp in $(listening_tcp $pid |awk '{print $4}'); do
		port=$(echo $hp | grep -o '[^:]*$')
		host=$(echo $hp | sed "s/:$port\$//")

		case $host in
		    '::'|'0.0.0.0'|'*')
			host='*'
			echo "iptables -A SKOPOS -p tcp --syn -dport $port -j REJECT"
			;;
		    *)
			log "WARNING: don't know how to generate fw rule for $host"
		esac
	    done
	    ;;
    esac
}

#
# given a mesos taskId
#  - get the underlying docker info then 
#  - determine whether the docker instance is in bridged or host networking mode
#  - get all the connections associated with it
#
# If verbose is passed, the entire list is returned otherwise just a count is returned
#
get_connections_by_task_id(){
    taskId="$1"
    verbose=false
    if [ ! -z "$2" ];then
	verbose=true
    fi
    task_pid=$(find_docker_pid_by_taskId $taskId)
    mode=$(find_docker_networkmode_by_taskId $taskId)
    case "$mode" in
	bridge)
	    if $verbose; then
		cat /proc/${task_pid}/net/tcp6  | $LOCALPATH/read_tcp6.sh -E
	    else
		cat /proc/${task_pid}/net/tcp6  | $LOCALPATH/read_tcp6.sh -E | wc -l
	    fi
	    ;;
	host)
	    # the docker process can and will have *Multiple* child process
	    pids=$(ps --forest -o pid= $(ps -e --no-header -o pid,ppid|awk -vp=${task_pid} 'function r(s){print s;s=a[s];while(s){sub(",","",s);t=s;sub(",.*","",t);sub("[0-9]+","",s);r(t)}}{a[$2]=a[$2]","$1}END{r(p)}'))
	    # 1. first this gets the process tree for the docker process
	    # 2. then it converts the pids in -e <pid> options for grep
	    # 3. which is then used to filter listening ports on the host.  At this point we have a list of endpoints
	    # 4. next, convert the 0.0.0.0:xxx into a regexp that will match any interface listening on the ports
	    #
	    # 
	    # Now we have a list of listeners and looks for established connections
	    # tcp4 addresses for now
	    #      	  Add | awk '{ print substr($0, index($0,$3)) }' to chop off leading recvQ/sendQ
	    #
	    # verbose mode is set for the cli when the user invokes $0 marathon_connections.  otherwise, a count is used with drain
	    #
	    CNT="-c"
	    if $verbose ;  then
		ss -tn4 -o state established   | grep  -E $(listening_patterns ${task_pid}) |awk '{ print substr($0, index($0,$3)) }'
	    else
		ss -tn4 -o state established   | grep -c -E $(listening_patterns ${task_pid})
	    fi

	    ;;
	*)
	    error "Unknown network type: $mode  This can happen EASILY with docker as user can define their own network types/bridges etc/"
    esac
}

#
# slave info
#
# Make sure curl worked to host and that it got back something
#
update_slave_info() {
    curl -SsfLk http://${LOCAL_IP}:5051/state > $tmpdir/mesos-slave-$$.json
    if [ $? -eq 0 -a -s $tmpdir/mesos-slave$$.json ]; then
	mv $tmpdir/mesos-slave$$.json ${SLAVE_CACHE}
	cat ${SLAVE_CACHE}
    else
	echo
    fi
}
#
# Grab all the local data from the mesos-slave api
#
slave_info(){
    if [ ! -f "${SLAVE_CACHE}" -o ! -s "${SLAVE_CACHE}" ]; then
	update_slave_info
    else
	# TODO: may want to check freshness
	cat ${SLAVE_CACHE}
    fi
}
#
# Cross reference the mesos slave info to docker instances
#
find_all_mesos_docker_instances(){
    # Mesos creates docker instances for potentially many frameworks.  Marathon is just one
    docker_inspect | jq '[.[] | select( .Name | startswith("/mesos-")) | { name: .Name, id: .Id}]'
}

#
# Get all the marathon jobs.  snapshot
#
marathon_jobs() {
    echo "${THIS_SLAVES_MARATHON_JOBS}"
}
#
# Given the mesos slave id
# Return all the docker ids for the given marathon tasks for
#
show_marathon_docker_ids() {
    for i in $(marathon_jobs | jq -r '.[] | .mesos_task_id' ); do
	docker_id=$(find_docker_id_by_taskId $i)
	echo "marathon/mesos_task_id: $i maps to docker_id: ${docker_id}"
    done
}
#
# Given the mesos slave id,
# Get the associated marathon tasks and cross-reference it to docker pids
#  i.e. {{.State.Pid}}
#
show_marathon_docker_pids() {
    for i in $(marathon_jobs | jq -r '.[] | .mesos_task_id' ); do
	docker_pid=$(find_docker_pid_by_taskId $i)
	echo "marathon/mesos_task_id: $i maps to docker_id: ${docker_pid}"
    done
}
#
# Given the marathon task list for this slave,
# Cross-reference to the docker instances
# Then make fw rules to block SYN
#
generate_marathon_fw_rules() {
    for i in $(marathon_jobs | jq -r '.[] | .mesos_task_id' ); do
	docker_id=$(find_docker_id_by_taskId $i)
	if $verbose; then
	    echo "marathon/mesos_task_id: $i maps to docker_id: ${docker_id}"
	fi
	get_fw_rules $i | grep -v -E '^\s*$'
    done
}
#
# Given a mesos task id
# Get the marathon task xref to docker xref to /proc/$docker_pid/net/tcp6
#
# Return the full list of connections
show_marathon_connections() {
    for i in $(marathon_jobs | jq -r '.[] | .mesos_task_id' ); do
	get_connections_by_task_id $i true
    done
}
#
# Get a list of well know host:ports for all the tasks associated with this host from marathon's perspective
#
host_ports() {
    # pre-made for egrep
    marathon_jobs | jq -r 'reduce .[] as $list ([] ; . + $list.mappings)| join("|")'
}
#
# Get a list of well know ports for all the tasks associated with this host from marathon's perspective
#
just_ports() {
    # egrep ready.
    # just ports.  Put out a leading ':' after the join
    marathon_jobs | jq -r 'reduce .[] as $list ([] ; . + $list.mappings)| reduce .[] as $foo ([] ; . + [($foo| split(":")|last)])| join("|:") |  if ( . | length ) > 0 then  ":" + . else . end'
}
#
# drain all the connections associated with this host
#
# This places firewall rules into iptables -t filter -A SKOPOS
# If the SKOPOS chain doesn't exist, it is made
# The SKOPOS chain is flushed on exit
#
drain_tcp(){
    # block marathon health checks with iptables
    if [ 0 -eq $(sudo iptables -nL -v | grep -c 'Chain SKOPOS') ]; then
	iptables -t filter -N SKOPOS
	# we need to go before DOCKER
	iptables -t filter -I FORWARD -j SKOPOS
    fi
    # generate and run the rules
    generate_marathon_fw_rules | xargs -n 1 -IXX bash -c "XX"
    on_exit "iptables -F SKOPOS"

    # stop the slave
    TIMEOUT=$(( $SECONDS + 900 )) 
    while :; do
	cnt=0
	for i in $(marathon_jobs | jq -r '.[] | .mesos_task_id' ); do
	    jj=$(get_connections_by_task_id $i)
	    cnt=$(( $cnt + $jj ))
	done
	if [ $cnt -eq 0 ]; then
	    log "drain_tcp| Connections at zero"
	    break
	fi
	if [[ $SECONDS > $TIMEOUT ]]; then
            log "drain_tcp| Timeout ... with $cnt remaining connections"
            break
	fi
	log "drain_tcp| Waiting for $cnt more connections $SECONDS->$TIMEOUT"
        sleep 1
    done
    log "done draining"
}

#
# Get all the docker ids assoc with this host
#

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
#
# drain_docker
#
# - call docker stop on all processes marathon related docker instances
# - wait for a period of time
# - check if they all stop
# - keep waiting 900 seconds (15 mins)
# - if still active after 15 mins, call docker kill
#
#
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
	     log "drain_docker: Stopped $i/${docker_id}"
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

#
# drain
#  
#   - grab the host lock using "DRAIN" as a value
#   - register an on exit unlock_host once acquired
#   - stop mesos-slave
#   - call drain_tcp
#   - call drain_docker
#   - unlock
 
drain(){
    token="DRAIN"
    if [ ! -z "$1" ];then
	token="$1"
    fi
    lock_host $token
    if [ $? -ne 0 ];then
	state=$(host_state)
	error "Can't get local host lock.  state: $state"
    fi
    on_exit 'unlock_host "$token"'
    log "$MACHINE-ID got drain lock with lock token \"$token\""
    # we already have mesos/marathon/docker data
    systemctl stop ${MESOS_UNIT}
    
    # update docker inspect just in case the lock took a while to get
    DOCKER_INSPECT="$tmpdir/docker_inspect_$(date +%s)"
    drain_tcp
    drain_docker
    unlock_host "$token"
}

if [ ! -z "$1" ];then
    # Get docker info
    
    if [ -z "$(update_docker_inspect)" ]; then
	# TODO: error for now, but actually edge case.
	# Nothing is running so just drain
	finish_ok "No docker instances"
    fi
    if [ -z "$(  update_slave_info )" ] ;then
	finish_ok "No slave info. Is mesos-slave running?"
    fi
    # Getting the slave Id.
    SLAVE_ID=$( slave_info | jq -r .id)
    if [ -z "${SLAVE_ID}" ]; then
	#
	# it is weird to call this ok as there is always a slave it if the slave is running.
	# 
        finish_ok "No slave id found.  Is the mesos-slave running?"
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
        marat
	;;
    marathon_docker_pids)
	show_marathon_docker_pids
	;;
    marathon_connections)
	show_marathon_connections
	;;
    generate_marathon_fw_rules)
	generate_marathon_fw_rules

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
	drain
	;;
    
    *)
        cat <<EOF 
Usage: drain {marathon_jobs|marathon_docker_ids|marathon_docker_pids|marathon_docker_connections|host_ports|just_ports|drain_tcp|drain_docker|drain}
     Drains a mesos & marathon managed node where the tasks are docker instances in bridged or host network mode

     Ethos assumptions:  All endpoints are in etcd and that all nodes have access to etcd.

     host_ports - outputs the pipe separated list ip:ports for this listening on this slave
     just_ports - is just the ports separated by pipes for grep
     marathon_jobs - outputs json with the mesos_task_id
     marathon_docker_ids -- terse list of docker instance ids
     marathon_docker_pids -- list of pids 
     marathon_connections -- show all ESTABLISHED connection for this host related to marathon tasks.  Both 'host' and 'bridged'
     marathon_docker_jobs - takes the output of marathon_jobs and search docker_inspect in a xref into the .Config.Env for the task id.  Mesos sets the task id into the docker instances it starts.
     generate_marathon_fw_rules - show the listeners for each docker pid.  Used to block marathon with iptables
     drain_tcp - stops the mesos slave and waits for all the ports coming from host_ports in an ESTABLISHED state to drop to zero.
     drain_docker - takes 
     drain   - locks host-lock 
		 - if it's not already locked.  
	     - locks the drain cluster-wide lock
	     - grabs mesos-slave,docker, and marathon data
	     - stops mesos
	     - call drain_tcp which works with host and bridge network types
	     - calls drain_docker which calls docker stop, waits a period of time to ensure all instances stop, then calls docker kill
	     - unlocks cluster-wide lock
	     - unlocks host lock


EOF
        exit 1
        ;;
esac


