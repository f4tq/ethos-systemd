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
	if [ 0 -ne $(update_engine_client -update 2>&1 |grep -c NEED_REBOOT) ] ;then
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
	       $LOCALPATH/drain.sh drain
	       status=$?
	       if [ $? -eq 0 ]; then
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
   
       
