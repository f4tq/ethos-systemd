#!/bin/bash 

LOCALPATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd $LOCALPATH

source $LOCALPATH/../lib/lock_helpers.sh
source $LOCALPATH/../lib/mesos_helpers.sh

on_exit "log 'Goodbye...'"
assert_root

[ -d /var/lib/skopos ] || ( mkdir -p /var/lib/skopos && [ -d /var/lib/skopos ] ) || die "can't make /var/lib/skopos"

need_reboot(){
    test -f /var/lib/skopos/needs_reboot
}

log "Welcome to Skopos"
if [ "${NODE_ROLE}" != "control" ]; then
    
    until (etcdctl --endpoints ${LOCKSMITHCTL_ENDPOINT} ls >/dev/null ) ; do
	log "Waiting for etcd @ ${LOCKSMITHCTL_ENDPOINT}"
	sleep 2;
    done
fi

if [ -e /var/lib/skopos/rebooting ]; then
    
    health_url=""
    if [ "${NODE_ROLE}" == "control" ]; then
	# WARNING: zk must be up before we allow other nodes to continue!
	# DC/OS assumption: zk is running on control node.  Probably better way to detect
	# 
	# TODO: ethos
	#    
	#    - mesos/zk needs user/password
	#    - docker image appropriate/nc brings netcat
	#    - zk not in a zk systemd unit.
	#
	
        while [ "imok" != "$(echo "ruok" | ncat "${LOCAL_IP}" 2181)" ]; do
	    log "Waiting for zookeeper"
	    sleep 1
	done
	log "Zookeeper up ..."
	# wait for etcd to show this node in the list
	while [ 0 -eq $(etcdctl member list  | grep -c "${LOCAL_IP}" ) ];do
	    log "Waiting for etcd"
	    sleep 1
	done
	log "etcd up ..."
	health_url="http://${LOCAL_IP}:5050/master/redirect"
	if ! (ps -wef | grep mesos-master) ; then
	    systemctl start ${MESOS_UNIT}
	fi
    elif [ "${NODE_ROLE}" == "worker" ]; then
	# TODO: ethos mesos slave needs user/password
	# TODO:  all worker nodes assumed to run mesos-slave???
	#
	health_url="http://${LOCAL_IP}:5051/state"
    elif [ "${NODE_ROLE}" == "proxy" ]; then
	log "Unknown health_url for node role: ${NODE_ROLE}"
    fi

    while  [ ! -z "${health_url}" ] && ! curl -SsfLk "${health_url}"  > /dev/null 2>&1  ; do
	log "Waiting for mesos ${health_url} to pass before freeing cluster-wide reboot lock"
	sleep 1
    done

    log "mesos/up Unlocking cluster reboot lock"
    # bring ourselves up.
    if ${USE_MESOS_API}; then
	$LOCALPATH/mesos_up.sh
    fi
    unlock_reboot
    if [ $? -ne 0 ];then
	log "update_os| This is AWKWARD.  After rebooting,we can't unlock_reboot ( which we held ).  Did someone unlock it? : proceeding as if and ignoring"
    fi
    rm -f /var/lib/skopos/rebooting
    rm -f /var/lib/skopos/needs_reboot
    if [ "REBOOT" == "$(host_state)" ] ; then
	# This shouldn't happen but if the host lock reads REBOOT then something odd
	# happened.  So unlock and make sure there are no rules left in the iptables SKOPOS chain
	#
        if [ 0 -lt $(iptables -t filter -nL -v | grep -c 'Chain SKOPOS') ]; then
	    iptables -t filter -F SKOPOS
	fi
	unlock_host "REBOOT"
    fi
    log "finished update process.  everything normal ..."    
fi
	
timeout=10

# To complete update, we must reboot.
# drain first
while : ; do
    if $(need_reboot) ; then
	lock_reboot
	if [ $? -eq 0 ]; then
	    #on_exit 'unlock_reboot'
	    while : ; do 
		# we hold the tier lock for reboot
		$LOCALPATH/drain.sh drain "REBOOT"
		status=$?
		if [ $status -eq 0 ] ; then 
		    log "update-os|drain succeeded. rebooting host_locks sez: $(host_state)"
		    touch /var/lib/skopos/rebooting
		    shutdown -r now
		else
		    log "update-os| Can't drain.  host lock's state: '$(host_state)'"
		    set -x
		    unlock_reboot
		    set +x
		    break
		fi
	    done
	else
	    log "update-os|Can't get reboot lock. sleeping"
	    sleep 1
	fi
    fi
    sleep 20
done

   
       
