#!/usr/bin/bash 

#
# This schedules a unit
#
#

BINPATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source $BINPATH/../lib/drain_helpers.sh

assert_root
unit_name=booster-draining-$(cat /etc/machine-id)-$(date +%s).service

json=$tmpdir/test.json


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


cat <<EOF > $json
{
    "name": "${unit_name}",
    "desiredState": "launched",
    "options": [
        { "section": "Unit", "name": "Description", "value": "Draining Launched by Booster"},
        { "section": "Service", "name": "Type", "value": "oneshot"},
        { "section": "Service", "name": "User", "value": "root"},
        { "section": "Service", "name": "RemainAfterExit", "value": "no"},
        { "section": "Service", "name": "StandardOutput", "value": "journal+console"},
        { "section": "Service", "name": "ExecStart", "value": "/bin/bash -xc '/home/core/ethos-systemd/v1/util/booster-drain.sh --notify ${notify} --machine-id ${machindId}'"},
        { "section": "X-Fleet", "name": "MachineID", "value": "$(cat /etc/machine-id)"}
    ]
}
EOF
curl -v --unix-socket /var/run/fleet.sock -H 'Content-Type: application/json' -X PUT -d@$json http:/fleet/fleet/v1/units/${unit_name}

>&2 cat << EOF
Useful followups sans fleetctl:

 - Start
sudo curl -v --unix-socket /var/run/fleet.sock -H 'Content-Type: application/json' -X PUT -d'{"desiredState": "launched"}'  http://fleet/fleet/v1/units/${unit_name}

 - Status
sudo curl -vs --unix-socket /var/run/fleet.sock  http:/fleet/fleet/v1/state?machineID=`cat /etc/machine-id` | jq '.states[]'

 - Delete unit
sudo curl -v --unix-socket /var/run/fleet.sock  -X DELETE http:/fleet/fleet/v1/units/${unit_name}

 - Find show unit names
sudo curl -vs --unix-socket /var/run/fleet.sock  http:/fleet/fleet/v1/units  | jq -r '.units[]|.name'

 - Find booster units
sudo curl -vs --unix-socket /var/run/fleet.sock  http:/fleet/fleet/v1/units  | jq '.units[]|select(.name | contains("booster-draining"))|.'

 - logs
sudo journalctl -u ${unit_name} 

# Cleanup

for i in $(sudo curl -s --unix-socket /var/run/fleet.sock  http:/fleet/fleet/v1/units  | jq -r '.units[]|select(.name | contains("booster-draining"))|.name'); do sudo curl -v --unix-socket /var/run/fleet.sock  -X DELETE http:/fleet/fleet/v1/units/$i;done

# Debugging
Use 2 shells. Replace all the above --unix-sockets /var/run/fake.sock.  

toolbox:
  dnf install -y socat tcpdump
  socat -v unix-listen:/media/root/var/run/fake.sock,fork unix-connect:/media/root/var/run/fleet.sock

-f4tq 
EOF

