#!/usr/bin/bash -x

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source $DIR/../../lib/helpers.sh

# Setup cluster wide locks
IMAGE=`etcdctl get /images/etcd-locks`

for j in booster_drain skopos updates; do
         
    for i in control worker proxy; do
	etcdctl ls /adobe.com/locks/$j
	if [ $? -eq 1 ];then
	    docker run --net host -i --rm $($IMAGE)  /usr/local/bin/locksmithctl --topic $j --group $i status 

	    if [ "$j" == "updater" ]; then 
		# allow 2 updates to happen
		docker run --net host -i --rm $($IMAGE)  /usr/local/bin/locksmithctl --topic $j --group $i set-max 2
	    fi
	else
	    echo "$j locks already exist"
        fi
    done 
done
