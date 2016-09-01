#!/usr/bin/bash -x

#
# This schedules a unit
#
#

LOCALPATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source $LOCALPATH/drain_helpers.sh

assert_root
unit_name=booster-draining-$(cat /etc/machine-id)-$(date +%s).service

json=/tmp/test.json

cat <<EOF > $json
{
    "name": "${unit_name}",
    "desiredState": "loaded",
    "options": [
        { "section": "Unit", "name": "Description", "value": "Draining Launched by Booster"},
        { "section": "Service", "name": "Type", "value": "oneshot"},
        { "section": "Service", "name": "User", "value": "root"},
        { "section": "Service", "name": "RemainAfterExit", "value": "no"},
        { "section": "Service", "name": "RestartSec", "value": "5"},
        { "section": "Service", "name": "StandardOutput", "value": "journal+console"},
        { "section": "Service", "name": "ExecStartPre", "value": "/bin/bash -cx 'test -z \"\$(/home/core/ethos-systemd/v1/util/lockctl.sh host_state)\"'"},
        { "section": "Service", "name": "ExecStart", "value": "/bin/bash -xc '/home/core/ethos-systemd/v1/util/drain.sh drain BOOSTER'"},
        { "section": "Service", "name": "ExecStartPost", "value": "/bin/bash -cx 'test -z \"\$(/home/core/ethos-systemd/v1/util/lockctl.sh host_state)\" || /home/core/ethos-systemd/v1/util/lockctl.sh unlock_host BOOSTER'"},
        { "section": "X-Fleet", "name": "MachineID", "value": "$(cat /etc/machine-id)"}
    ]
}
EOF
curl -v --unix-socket /var/run/fleet.sock -H 'Content-Type: application/json' -X PUT -d@$json http:/fleet/fleet/v1/units/${unit_name}

>&2 cat << EOF
Useful followups:

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

-f4tq 
EOF

