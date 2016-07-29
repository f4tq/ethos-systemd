#!/usr/bin/bash -x

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source $DIR/../../lib/helpers.sh

# Setup cluster wide locks
IMAGE=`etcdctl get /images/etcd-locks`
CLUSTERWIDE_LOCKS="booster_drain skopos coreos_updates"
set -x
for j in ${CLUSTERWIDE_LOCKS}; do
    etcdctl ls /adobe.com/locks/$j  >/dev/null 2>&1
    if [ $? -eq 0 ]; then
	echo "$j locks already exist" 
	continue
    fi	
         
    for i in control worker proxy; do
	    docker run --net host -i --rm $($IMAGE)  locksmithctl --topic $j --group $i status 
	    max_locks="1"
	    x=$(etcdctl get /etcd-locks/$j/$i 2>/dev/null )
	    if [ $? -eq 0 -a ! -z "$x"]; then
		max_locks=$x
	    fi
	    if [ "1" != "${max_locks}" ]; then 
		# allow 2 updates to happen
		docker run --net host -i --rm $($IMAGE)  locksmithctl --topic $j --group $i set-max ${max_locks}
	    fi

    done 
done
