#!/bin/bash 

set -x

LOCALPATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd $LOCALPATH

source /etc/environment
MACHINEID=`cat /etc/machine-id`
LOCKSMITHCTL_ENDPOINT=127.0.0.1:2379

if [ "${NODE_ROLE}" == "worker" ]; then
    . /etc/profile.d/etcdctl.sh
    LOCKSMITHCTL_ENDPOINT="${ETCDCTL_PEERS}"
fi


timeout=10
IMAGE=`etcdctl get /images/etcd-locks`

# use a bit of knowledge on lock layout to inspect who's holding a lock with jq


freshreboot=$(etcdctl get /adobe.com/locks/coreos_reboot/groups/${NODE_ROLE}/semaphore| jq --arg machineId $MACHINEID '.holders[] | contains($machineId)')

if [ $freshreboot ]; then

    # make sure the drain is unlocked too
    docker run --net host -i --rm -e LOCKSMITHCTL_ENDPOINT="${LOCKSMITHCTL_ENDPOINT}" $IMAGE  locksmithctl --topic coreos_drain --group ${NODE_ROLE} unlock $MACHINEID

    # we still hold the lock so let it go
    docker run --net host -i --rm -e LOCKSMITHCTL_ENDPOINT="${LOCKSMITHCTL_ENDPOINT}" $IMAGE  locksmithctl --topic coreos_reboot --group ${NODE_ROLE} unlock $MACHINEID

    echo "Released reboot and drain locks" 
fi

get_lockval(){
    etcdctl get /adobe.com/locks/coreos_reboot/groups/${NODE_ROLE}/semaphore| jq --arg machineId $MACHINEID '.holders | join(" ")'
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
	
# locks   coreos_reboot > coreos_drain

while : ; do
    # check for update
    update_engine_client -status|grep -q NEED_REBOOT
    if [ $? -eq 1 ]; then
       sleep $timeout
       continue
    fi
    # We need to reboot
    # Try to get the lock
    docker run --net host -i --rm  -e LOCKSMITHCTL_ENDPOINT="${LOCKSMITHCTL_ENDPOINT}" $IMAGE  locksmithctl --topic coreos_reboot --group ${NODE_ROLE} lock $MACHINEID
    status=$?
    while [ $status -ne 0 ]; do
	# locksmith does an implicit 'lock $(cat /etc/machine-id)' as does coreos' locksmith
	watch_lock "docker run --net host -e LOCKSMITHCTL_ENDPOINT=${LOCKSMITHCTL_ENDPOINT} -i --rm $IMAGE locksmithctl --topic coreos_reboot --group ${NODE_ROLE} lock $MACHINEID"
	
	status=$?
	
	if [ $status -eq 0 ];then
	    echo "Locked update/${NODE_ROLE}"
	    break
	fi
    done
    ./drain.sh drain
    # shutdown holding the lock.  Free it on the way in
    
    # shutdown -r now
done
       
