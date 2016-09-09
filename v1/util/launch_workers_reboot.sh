#!/usr/bin/bash

#
# This schedules unit runs on every worker.  It simply triggers an update of the worker tier
#
# - Changed from a global unit to individual machine units as booster growth will schedule a unit if control=worker
# - Also, by scheduling individual units,  The unit can destroy itself after it's mission which is to kick off update...
#
# set -x is used in ExecStart so that a trace of the generated units are left behind.
# You can always tell the unit ran by checking for /var/lib/skopos/*.done.  They may be removed if desired.
#

BINPATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source $BINPATH/../lib/drain_helpers.sh

assert_root
: ${tier:=worker}

dt=$(date +%s)
for machineId in $(fleetctl list-machines --full | grep "role=$tier" | awk '{print $1}'); do
    unit_name=$tier-reboot-${dt}-${machineId}.service

    json=/tmp/$tier-reboot-${dt}-${machineId}.json

    cat <<EOF > $json
{
    "name": "${unit_name}",
    "desiredState": "launched",
    "options": [
        { "section": "Unit", "name": "Description", "value": "Trigger a $tier reboot for machine $machineId"},
        { "section": "Unit", "name": "Requires", "value":"update-os.service"},
        { "section": "Unit", "name": "ConditionPathExists", "value":"!/var/lib/skopos/${unit_name}.done"},
        { "section": "Service", "name": "Type", "value": "oneshot"},
        { "section": "Service", "name": "User", "value": "root"},
        { "section": "Service", "name": "RemainAfterExit", "value": "no"},
        { "section": "Service", "name": "StandardOutput", "value": "journal+console"},
        { "section": "Service", "name": "ExecStart", "value": "/bin/bash -c 'set -x; /usr/bin/touch /var/lib/skopos/needs_reboot;  touch /var/lib/skopos/${unit_name}.done'"},
        { "section": "X-Fleet", "name": "MachineID", "value": "$machineId"}
   ]
}
EOF
    curl  -v --unix-socket /var/run/fleet.sock -H 'Content-Type: application/json' -X PUT -d@$json http://fleet/fleet/v1/units/${unit_name}
done

>&2 cat << EOF
Useful followups sans fleetctl:

 - Start
sudo curl -v --unix-socket /var/run/fleet.sock -H 'Content-Type: application/json' -X PUT -d'{"desiredState": "launched"}'  http://fleet/fleet/v1/units/${unit_name}
    -or-
for machineId in $(fleetctl list-machines --full | grep "role=$tier" | awk '{print $1}' | tr '\r\n' ' '); do sudo fleetctl status $tier-reboot-${dt}-\${machineId}.service ;done

 

 - Status
sudo curl -vs --unix-socket /var/run/fleet.sock  http:/fleet/fleet/v1/units  | jq '.units[]|select(.name | contains("$tier-reboot-${dt}"))|.'   

for machineId in $(fleetctl list-machines --full | grep "role=$tier" | awk '{print $1}' | tr '\r\n' ' '); do sudo fleetctl status $tier-reboot-${dt}-\${machineId}.service ;done


- Deleta all
for i in $(sudo curl -s --unix-socket /var/run/fleet.sock  http:/fleet/fleet/v1/units  | jq -r '.units[]|select(.name | contains("$tier-reboot-${dt}"))|.name'); do sudo curl -v --unix-socket /var/run/fleet.sock  -X DELETE http:/fleet/fleet/v1/units/$i;done

for machineId in $(fleetctl list-machines --full | grep "role=$tier" | awk '{print $1}' | tr  '\r\n' ' '); do sudo fleetctl destroy $tier-reboot-${dt}-\${machineId}.service ;done

 - logs 
  WARNING: the units created here cleanup after they run.  fleet and etcdctl ls --recursive /_coreos will have nothing on them.  To examine logs, use ansible

for machineId in $(fleetctl list-machines --full | grep "role=$tier" | awk '{print $1}' |  tr  '\r\n' ' ') ; do sudo fleetctl journal $tier-reboot-${dt}-\${machineId}.service ;done


- Using ansible 
    For inventory, see https://git.corp.adobe.com:fortescu/Mesos4Dexi/inventory-ethos-f4tq

export INVENTORY=/home/fortescu/Mesos4Dexi/inventory-ethos-f4tq/

from osx, 

for machineId in $(fleetctl list-machines --full | grep "role=$tier" | awk '{print $1}' |  tr  '\r\n' ' ') ; do 
  ansible coreos_workers -i \$INVENTORY  -m raw -a 'bash -c "journalctl -u fleet.service --no-pager  | grep "tier-reboot-${dt}-\${machineId}.service" 
done

# Cleanup

-f4tq 
EOF

