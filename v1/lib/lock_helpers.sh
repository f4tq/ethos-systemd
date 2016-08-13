#!/usr/bin/bash -x
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source $DIR/helpers.sh

SKOPOS_CLUSTERWIDE_LOCKS=/adobe.com/locks/cluster-wide
SKOPOS_PERHOST_LOCKS=/adobe.com/locks/per-host
SKOPOS_HOST_STATE=/adobe.com/locks/host-state
SKOPOS_FEATURE_FLIP=/adobe.com
MACHINEID=$(cat /etc/machine-id)

IMAGE=$(etcdctl get /images/etcd-locks)

BOOSTER_LOCK=booster_drain
UPDATE_DRAIN_LOCK=coreos_drain
REBOOT_LOCK=coreos_reboot
CLUSTERWIDE_LOCKS="${BOOSTER_LOCK} ${UPDATE_DRAIN_LOCK} ${REBOOT_LOCK}"


#
#
#  Clusterwide
#
#
log(){
    echo "[$(date +%s)] $*"
}
lock_booster(){
    docker run --net host -i --rm  -e LOCKSMITHCTL_ENDPOINT=${ETCDCTL_PEERS} $IMAGE  locksmithctl --path ${SKOPOS_CLUSTERWIDE_LOCKS} --topic ${BOOSTER_LOCK} --group ${NODE_ROLE} lock $MACHINEID
}

unlock_booster(){
    docker run --net host -i --rm  -e LOCKSMITHCTL_ENDPOINT=${ETCDCTL_PEERS} $IMAGE  locksmithctl --path ${SKOPOS_CLUSTERWIDE_LOCKS} --topic ${BOOSTER_LOCK} --group ${NODE_ROLE} unlock $MACHINEID
}    

lock_drain(){
    docker run --net host -i --rm  -e LOCKSMITHCTL_ENDPOINT=${ETCDCTL_PEERS} $IMAGE  locksmithctl --path ${SKOPOS_CLUSTERWIDE_LOCKS} --topic ${UPDATE_DRAIN_LOCK} --group ${NODE_ROLE} lock $MACHINEID
}

unlock_drain(){
    docker run --net host -i --rm  -e LOCKSMITHCTL_ENDPOINT=${ETCDCTL_PEERS} $IMAGE  locksmithctl --path ${SKOPOS_CLUSTERWIDE_LOCKS} --topic ${UPDATE_DRAIN_LOCK} --group ${NODE_ROLE} unlock $MACHINEID
}

lock_reboot(){
    docker run --net host -i --rm  -e LOCKSMITHCTL_ENDPOINT=${ETCDCTL_PEERS} $IMAGE  locksmithctl --path ${SKOPOS_CLUSTERWIDE_LOCKS} --topic ${REBOOT_LOCK} --group ${NODE_ROLE} lock $MACHINEID
}

unlock_reboot(){
    docker run --net host -i --rm  -e LOCKSMITHCTL_ENDPOINT=${ETCDCTL_PEERS} $IMAGE  locksmithctl --path ${SKOPOS_CLUSTERWIDE_LOCKS} --topic ${REBOOT_LOCK} --group ${NODE_ROLE} unlock $MACHINEID
}

    
cluster_init(){
    for j in ${CLUSTERWIDE_LOCKS}; do
	etcdctl ls ${SKOPOS_CLUSTERWIDE_LOCKS}/$j  >/dev/null 2>&1
	if [ $? -eq 0 ]; then
	    echo "etcd path ${SKOPOS_CLUSTERWIDE_LOCKS}/$j locks already exists"
	    continue
	fi	
        
	for i in control worker proxy; do
	    docker run --net host -i --rm -e LOCKSMITHCTL_ENDPOINT=${ETCDCTL_PEERS}  $IMAGE  locksmithctl --path ${SKOPOS_CLUSTERWIDE_LOCKS} --topic $j --group $i status 
	    max_locks="1"
	    x=$(etcdctl get ${SKOPOS_FEATURE_FLIP}/settings/etcd-locks/$j/num_$i 2>/dev/null )
	    if [ $? -eq 0 -a ! -z "$x" ]; then
		max_locks=$x
	    fi
	    if [ "1" != "${max_locks}" ]; then 
		# allow 2 updates to happen
		docker run --net host -i --rm -e LOCKSMITHCTL_ENDPOINT=${ETCDCTL_PEERS} $IMAGE  locksmithctl --path ${SKOPOS_CLUSTERWIDE_LOCKS}  --topic $j --group $i set-max ${max_locks}
	    fi
	done 
    done
}
# the host locks are assumed to be used only by the host with $MACHINEID.  Hence the lock value is used to indicate state
#    DRAIN
#    REBOOT
# which can be used to prevent queued up drains or reboots
# The id used in the lock defaults to $MACHINEID which is unique and owned by the host
# 
host_init(){
    docker run --net host -i --rm   -e LOCKSMITHCTL_ENDPOINT=${ETCDCTL_PEERS} $IMAGE locksmithctl --path ${SKOPOS_PERHOST_LOCKS} --topic $MACHINEID status 
}
	

# you must provide a reason such as REBOOT, DRAIN then unlock with the same key or fail	
lock_host(){
    if [ -z "$1" ]; then
	reason=$MACHINEID
    else
	reason=$1
    fi
    docker run --net host -i --rm   -e LOCKSMITHCTL_ENDPOINT=${ETCDCTL_PEERS} $IMAGE locksmithctl --path ${SKOPOS_PERHOST_LOCKS} --topic $MACHINEID lock $reason
}
unlock_host(){

    if [ -z "$1" ]; then
	reason=$MACHINEID
    else
	reason=$1
    fi
    docker run --net host -i --rm   -e LOCKSMITHCTL_ENDPOINT=${ETCDCTL_PEERS} $IMAGE locksmithctl --path ${SKOPOS_PERHOST_LOCKS} --topic $MACHINEID unlock $reason
}

host_state(){
    etcdctl get ${SKOPOS_PERHOST_LOCKS}/$MACHINEID| jq -r --arg machineId $MACHINEID '.holders|(if length > 0 then (.| join(" ")) else "" end)'
}
lock_error(){
    if [ ! -z "$1" ];then
	2>echo $1
    fi
    exit -1
}
#
# the semaphore value.  We need this to watch for changes.
# There will be an update to etcdctl that fixes this but for now
#
# holders is an array
cluster_lock_val(){
    if [ -z "$1" ]; then
	lock_error "You must provide one of '${CLUSTERWIDE_LOCKS}'"
    fi
    topic=$1
    if [ ! -z "$2" ]; then tier=$2;  else tier=${NODE_ROLE} ; fi

    etcdctl get ${SKOPOS_CLUSTERWIDE_LOCKS}/$topic/groups/$tier/semaphore| jq -r --arg machineId $MACHINEID '.holders|(if length > 0 then (.| join(" ")) else "" end)'
}

am_cluster_lock_holder(){
    if [ -z "$1" ]; then
	lock_error "You must provide one of '${CLUSTERWIDE_LOCKS}'"
    fi
    topic=$1
    if [  -z "$2" ]; then
	lock_error "You must provide one of '${CLUSTERWIDE_LOCKS}' with a tier [worker,control,proxy]"
    fi
    tier=$2

    etcdctl get ${SKOPOS_CLUSTERWIDE_LOCKS}/$topic/groups/$tier/semaphore| jq --arg machineId $MACHINEID '.holders|(length > 0 and (.[] | contains($machineId)))'
}


watch_clusterwide_lock() {
    # etcdctl exec-watch doesn't work on coreos...
    topic=$1
    orig=$(cluster_lock_val $topic ${NODE_ROLE})
    while : ; do
	newv=$(cluster_lock_val $topic ${NODE_ROLE})
	if [ "$orig" != "$newv" ];then
	    break
	fi
	sleep 2
    done
    eval $*
}
watch_drain_lock(){
    watch_clusterwide_lock ${UPDATE_DRAIN_LOCK} $MACHINEID $*
}
watch_booster_lock(){
    watch_clusterwide_lock ${BOOSTER_LOCK} $MACHINEID $*
}
watch_reboot_lock(){
    watch_clusterwide_lock ${REBOOT_LOCK} $MACHINEID $*
}
drain_state(){
    cluster_lock_val ${UPDATE_DRAIN_LOCK} ${NODE_ROLE}
}
reboot_state(){
    cluster_lock_val ${REBOOT_LOCK} ${NODE_ROLE}
}
booster_state(){
    cluster_lock_val ${BOOSTER_LOCK} ${NODE_ROLE}
}

am_drain_holder(){
    am_cluster_lock_holder ${UPDATE_DRAIN_LOCK} ${NODE_ROLE}
}
am_reboot_holder(){
    am_cluster_lock_holder ${REBOOT_LOCK} ${NODE_ROLE}
}
am_booster_holder(){
    am_cluster_lock_holder ${BOOSTER_LOCK} ${NODE_ROLE}
}

