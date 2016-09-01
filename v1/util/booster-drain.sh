#!/usr/bin/bash

#
# booster-drain.
#    schedules a draining systemd unit  
#    
#

BINPATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source $BINPATH/../lib/drain_helpers.sh

assert_root
usage(){
    if [ ! -z "$1" ];then
	>&2 echo $1
    fi
    cat <<EOF >&2

booster drain script.  Calls and optional url on completion with the MachineID and pass or fail
      --notify|-n <url>
      --machineId|-m <fleet valid machine id>  
 
     Environment variables
        - NOTIFY - Optional. Interpreted as a url.  Called as:
               curl $NOTIFY $MACHINEID.
        - MACHINEID  - REQUIRED. default is the contents of /etc/machine-id.  Must be a valid machine id for fleet.  --machineId switch overrides the environment
   
EOF
}

notify=${NOTIFY:-mock}
machineId=${MACHINEID:-$(cat /etc/machine-id)}

while [[ $# -gt 1 ]]
do
    key="$1"

    case $key in

	-n|--notify)
	    notify="$2"
	    shift # past argument
	    ;;
	-m|--machineId)
	    machineId="$2"
	    shift # past argument
	    ;;
	*)
	    # unknown option
	    usage "Don't understand '$key'"
	    ;;
    esac
    shift # past argument or value
done
if [ -z "${machineId}" ];then
    usage "No machine id"
fi

while : ; do
    lock_booster
    if [ $? -eq 0 ]; then
	on_exit 'unlock_booster'
	while : ; do
	    # we hold the tier lock for reboot
	    $BINPATH/drain.sh drain "BOOSTER"
	    status=$?
	    if [ $status -eq 0 ] ; then
		log "booster|drain succeeded. rebooting host_locks sez: $(host_state)"
		iptables -F  SKOPOS
		touch /var/lib/skopos/booster_drained
		if [ "$notify" != "mock" ];then
		    curl -sL $mock?machineId=$machineId
		fi
		exit 0
	    else
		log "Can't drain.  Patiently waiting."
		sleep 1
	    fi
	done
    else
	log "Can't get booster lock. sleeping"
    fi
    sleep 5
done
