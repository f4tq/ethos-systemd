#!/bin/bash 

LOCALPATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source /etc/environment

if [ -f /etc/profile.d/etcdctl.sh ]; then
    . /etc/profile.d/etcdctl.sh
fi

source $LOCALPATH/../lib/lock_helpers.sh

assert_root

log "drain_cleanup running"

# cleanup fleet created oneshot systemd units that fleet doesn't know how to remove.  in fact, it will try to launch it on a reboot

for i in $(ls /var/lib/skopos/*.done 2>/dev/null); do
    unit="$(basename $i | awk -F'.done' '{print $1}')"
    
    status="$(systemctl is-enabled $unit  2>/dev/null )"

    if [ "linked-runtime" == "$status" ];then
	
	    active="$(systemctl is-active  $unit  2>/dev/null )"

	    if [ "inactive" == "$active" ];then
		log "drain-cleanup removing fleet unit $unit"
		fleetctl destroy $unit
		if [ $? -eq 0 ]; then
		    # cleanup
		    rm -f $i
		fi
	    fi
    fi
done

log "drain_cleanup| All done for now"

