#!/bin/bash 

set -x

LOCALPATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd $LOCALPATH

source /etc/environment

timeout=10
IMAGE=`etcdctl get /images/etcd-locks`

# use a bit of knowledge on lock layout to inspect who's holding a lock with jq
freshreboot=$(etcdctl get /adobe.com/locks/default/groups/worker/semaphore| jq --arg machineId $(cat /etc/machine-id) '.holders[] | contains($machineId)')

if [ $freshreboot ]; then
    # we still hold the lock so let it go
    docker run --net host -i --rm $($IMAGE)  locksmithctl --topic updates --group ${NODE_ROLE} unlock
fi

while : ; do
    # check for update
    update_engine_client -status|grep -q NEED_REBOOT
    if [ $? -eq 1 ]; then
       sleep $timeout
       continue
    fi
    # We need to reboot
    # Try to get the lock
    docker run --net host -i --rm $($IMAGE)  locksmithctl --topic updates --group ${NODE_ROLE} lock
    status=$?
    while [ $status -ne 0 ]; do
	# locksmith does an implicit 'lock $(cat /etc/machine-id)' as does coreos' locksmith
	etcdctl exec-watch watch /adobe.com/locks/updates/groups/${NODE_ROLE}/semaphore docker run --net host -i --rm $($IMAGE) locksmithctl --topic updates --group ${NODE_ROLE} lock
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
       
