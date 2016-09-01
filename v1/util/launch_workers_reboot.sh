#!/usr/bin/bash -x

#
# This schedules unit runs on every worker.  It simply triggers an update of the worker tier
#
#

BINPATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source $BINPATH/../lib/drain_helpers.sh

assert_root
unit_name=worker-reboot-$(date +%s).service

json=$tmpdir/test.json

cat <<EOF > $json
{
    "name": "${unit_name}",
    "desiredState": "launched",
    "options": [
        { "section": "Unit", "name": "Description", "value": "Trigger a reboot"},
        { "section": "Unit", "name": "Requires", "update-os.service"},

        { "section": "Service", "name": "Type", "value": "oneshot"},
        { "section": "Service", "name": "User", "value": "root"},
        { "section": "Service", "name": "RemainAfterExit", "value": "yes"},
        { "section": "Service", "name": "StandardOutput", "value": "journal+console"},
        { "section": "Service", "name": "ExecStart", "value": "/usr/bin/touch /var/lib/skopos/needs_reboot"},
        { "section": "X-Fleet", "name": "Global", "value": "true"},
        { "section": "X-Fleet", "name": "MachineMetadata", "value": "role=wprker"}
    ]
}
EOF
curl -v --unix-socket /var/run/fleet.sock -H 'Content-Type: application/json' -X PUT -d@$json http:/fleet/fleet/v1/units/${unit_name}

>&2 cat << EOF
Useful followups sans fleetctl:

 - Start
sudo curl -v --unix-socket /var/run/fleet.sock -H 'Content-Type: application/json' -X PUT -d'{"desiredState": "launched"}'  http://fleet/fleet/v1/units/${unit_name}
    -or-
sudo fleetctl start ${unit_name}
 
 - Status
sudo curl -vs --unix-socket /var/run/fleet.sock  http://fleet/fleet/v1/state?machineID=`cat /etc/machine-id` | jq '.states[]'
    -or-
sudo fleetctl status ${unit_name}

 - Delete unit
sudo curl -v --unix-socket /var/run/fleet.sock  -X DELETE http://fleet/fleet/v1/units/${unit_name}

 - logs
sudo journalctl -u ${unit_name} 

# Cleanup

-f4tq 
EOF

