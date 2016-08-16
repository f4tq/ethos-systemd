#!/bin/bash 

set -x

LOCALPATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd $LOCALPATH

source /etc/environment

if [ "${NODE_ROLE}" == "worker" ]; then
    . /etc/profile.d/etcdctl.sh
fi

source $LOCALPATH/../lib/lock_helpers.sh

die(){
    if [ ! -z "$1" ]; then
	> echo "$1"
    fi
    exit -1
}

[ -d /var/lib/skopos ] || ( mkdir -p /var/lib/skopos && [ -d /var/lib/skopos ] ) || die "can't make /var/lib/skopos"

need_reboot(){
    val=$(etcdctl get /adobe.com/settings/mock_reboot 2>&1 /dev/null)
    
    if [ $? -eq 0 -a "true" == "$val" ];then
	2> echo "mock_reboot"
	/bin/true
    else
	if [ 0 -lt $(update_engine_client -update 2>&1 |grep -c NEED_REBOOT) ] ;then
	    echo "Detect real reboot"
	    /bin/true
	else
	    /bin/false
	fi
    fi
}

if [ -e /var/lib/skopos/rebooting ]; then
    log "Unlocking cluster reboot lock"
    unlock_reboot
    if [ $? -eq 0 ];then
	rm -f /var/lib/skopos/rebooting
    fi
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

if $(need_reboot) ; then
   # To complete update, we must reboot.
   # drain first
   while : ; do
       lock_reboot
       if [ $? -eq 0 ]; then
	   #on_exit 'unlock_reboot'
	   while : ; do 
	       # we hold the tier lock for reboot
	       value=$($LOCALPATH/drain.sh drain "REBOOT")
	       status=$?
	       if [ $status -eq 0 -o  ( 0 -lt $(echo "$value"| grep -c "No docker instances") )  ]; then
		   log "drain succeeded. rebooting"
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
   done
fi
   
       
