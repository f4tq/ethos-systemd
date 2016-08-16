#!/bin/bash 

LOCALPATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd $LOCALPATH

source /etc/environment

if [ "${NODE_ROLE}" == "worker" ]; then
    . /etc/profile.d/etcdctl.sh
fi

source $LOCALPATH/../lib/lock_helpers.sh

assert_root

[ -d /var/lib/skopos ] || ( mkdir -p /var/lib/skopos && [ -d /var/lib/skopos ] ) || die "can't make /var/lib/skopos"

need_reboot(){
    test -f /var/lib/skopos/needs_reboot
}

if [ -e /var/lib/skopos/rebooting ]; then
    log "Unlocking cluster reboot lock"
    unlock_reboot
    if [ $? -eq 0 ];then
	log "AWKWARD.  we were rebooting do to needs reboot but we can't unlock_reboot which we held.  Did someone unlock it: proceeding as if and ignoring"
    fi
    rm -f /var/lib/skopos/rebooting
    rm -f /var/lib/skops/needs_reboot
    if [ "REBOOT" == "$(host_state)" ] ; then
	# This shouldn't happen but if the host lock reads REBOOT then something odd
	# happened.  So unlock and make sure there are no rules left in the iptables SKOPOS chain
	#
        if [ 0 -lt $(iptables -t filter -nL -v | grep -c 'Chain SKOPOS') ]; then
	    
	    iptables -t filter -F SKOPOS
	fi
	unlock_host "REBOOT"
    fi
    
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
		value=$($LOCALPATH/drain.sh drain "REBOOT")
		status=$?
		if [ $status -eq 0 ] || [ 0 -lt $(echo "$value"| grep -c "No docker instances") ]; then
		    log "drain succeeded. rebooting host_locks sez: $(host_state)"
		    touch /var/lib/skopos/rebooting
		    shutdown -r now
		else
		    log "Can't drain.  Patiently waiting."
		    sleep 1
		fi
	    done
	else
	    log "Can't get reboot lock. sleeping"
	    sleep 1
	fi
    fi
    sleep 60
done

   
       
