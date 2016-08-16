#!/bin/bash 

# This script assumes you already hold the appropriate lock
# It will check to make sure and error out if the lock holder doesn't contain this host's machine-id `cat /etc/machine-id`
#

LOCALPATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source /etc/environment

if [ -f /etc/profile.d/etcdctl.sh ]; then
    . /etc/profile.d/etcdctl.sh
fi

source $LOCALPATH/../lib/lock_helpers.sh

usage(){
    if [ ! -z "$1" ]; then
	2> echo "$1"
    fi
        cat <<EOF 
Usage: $0 [un]lock_host|[un]lock_drain|[un]lock_reboot|[un]lock_booster|[host|drain|booster|reboot]_state,am_[drain,booster,reboot]_holder

    Control and display cluster wide & host locks

    You can also manipulate locks which can be useful it a lock is in an undesirable state i.e. machine crashed while holding a lock 

    -- host lock -- 
    Each host has it own locks.  The locks in etcd are named after the machine id (cat /etc/machine-id).  The values held in the lock should be the task the host is locked for.  You unlock it using the same host state value.  This value is returned with all *lock* calls in this cli

    lock_host  <value>  default: DRAIN  Other likely values: REBOOT, BOOSTER    
    unlock_host <value>  default: DRAIN
    host_state -- returns the current value of the host lock i.e. DRAIN.

    -- cluster wide locks ---
    Cluster wide lock values are machine-ids.  You don't provide a value for these directly.

    lock_drain  -- limits the number of simulataneous drains in the cluster.  This can be different for each controlled by tier
    unlock_drain
    lock_reboot -- limits the number of simulataneous reboots in the cluster.  This can be different for each controlled by tier
    unlock_reboot
    lock_booster -- limits the number of simulataneous booster locks in the cluster.  This can be different for each controlled by tier
    unlock_booster

    drain_state  -- returns the list of machine-ids currently in possesion of the lock.  It can be empty or multiple
    booster_state
    reboot_state 
EOF
	exit -1
}
case "$1" in
    lock_host)
	log "BEFORE host lock: host state: '$(host_state)'"
	token="DRAIN"
	if [ ! -z "$2" ]; then
	    token="$2"
	fi
	lock_host "$token"
	if [ $? -ne 0 ]; then
	    log "WARNING: host lock failed.  You must use the host state value"
	fi
	log "AFTER host lock: host state: '$(host_state)'"
	;;
    unlock_host)
	log "BEFORE host unlock: host state: '$(host_state)'"
	token="DRAIN"
	if [ ! -z "$2" ]; then
	    token="$2"
	fi
	unlock_host "$token"
	if [ $? -ne 0 ]; then
	    log "WARNING: host unlock failed.  You must use the `host_state` value"
	fi
	log "AFTER host unlock: host state: '$(host_state)'"
	;;
    lock_drain)
	log "drain lock BEFORE: '$(drain_state)'"
	lock_drain
	if [ $? -ne 0 ]; then
	    log "WARNING: drain lock failed"
	fi
	log "drain lock AFTER: '$(drain_state)'"
	;;
    unlock_drain)
	log "drain_lock BEFORE: '$(drain_state)'"
	unlock_drain
	if [ $? -ne 0 ]; then
	    log "WARNING: drain unlock failed"
	fi
	log "drain_lock AFTER : '$(drain_state)'"
	;;
    lock_reboot)
	log "reboot_lock BEFORE : '$(reboot_state)'"
	lock_reboot
	if [ $? -ne 0 ]; then
	    log "WARNING: reboot lock failed"
	fi
	log "reboot lock AFTER: '$(reboot_state)'"
	;;
    unlock_reboot)
	log "reboot unlock BEFORE: '$(reboot_state)'"
	unlock_reboot
	if [ $? -ne 0 ]; then
	    log "WARNING: reboot unlock failed"
	fi
	log "reboot unlock AFTER: '$(reboot_state)'"
	;;
    lock_booster)
	log "booster lock BEFORE: '$(booster_state)'"
	lock_booster
	if [ $? -ne 0 ]; then
	    log "WARNING: booster lock failed"
	fi
	log "booster lock AFTER: '$(booster_state)'"
	;;
    unlock_booster)
	log "booster unlock BEFORE: '$(booster_state)'"
	unlock_booster
	if [ $? -ne 0 ]; then
	    log "WARNING: booster unlock failed"
	fi
	log "booster unlock AFTER: '$(booster_state)'"
	;;

    am_drain_holder)
	am_drain_holder
	;;
    am_reboot_holder)
	am_booster_holder
	;;
    am_booster_holder)
	am_booster_holder
	;;

    host_state)
	host_state
	;;
    drain_state)
	drain_state
	;;
    booster_state)
	booster_state
	;;
    reboot_state)
	reboot_state
	;;
    
    *)
	usage
	;;
esac
exit 0
