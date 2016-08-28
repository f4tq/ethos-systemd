#!/usr/bin/bash 
LOCALPATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source $LOCALPATH/../lib/drain_helpers.sh

tmpdir=${TMPDIR-/tmp}/skopos-$RANDOM-$$
mkdir -p $tmpdir
on_exit 'rm -rf  "$tmpdir" '

if [ ! -z "$( curl -SsL ${MESOS_CREDS} ${MESOS_URL}/maintenance/status | jq --arg ip ${LOCAL_IP} --arg host $(hostname --fqdn) '.draining_machines[]|select( .id| (.ip ==$ip  and .hostname==$host) )' 2>/dev/null)" ]; then
    cat <<EOF > $tmpdir/down-host.json
[
        { "hostname" : "$(hostname --fqdn)", "ip" : "${LOCAL_IP}" }
]
EOF
    if [ 0 -lt $(curl  -Ls -v -H "Content-type: application/json" -X POST -d @$tmpdir/down-host.json  ${MESOS_CREDS} ${MESOS_URL}/machine/down 2>&1 | grep -c 'HTTP.*200.*OK') ] && \
	   [ ! -z "$( curl -SsL ${MESOS_CREDS} ${MESOS_URL}/maintenance/status | jq --arg ip ${LOCAL_IP} --arg host $(hostname --fqdn) '.down_machines[]|select( .ip ==$ip  and .hostname==$host )')" ]; then
	log "${LOCAL_IP} is down"
	exit 0
    else
	error "${LOCAL_IP} unable to schedule drain"
    fi
elif [ ! -z "$( curl -SsL ${MESOS_CREDS} ${MESOS_URL}/maintenance/status | jq --arg ip ${LOCAL_IP} --arg host $(hostname --fqdn) '.down_machines[]|select( .ip ==$ip  and .hostname==$host )' 2>/dev/null)" ]; then
    log "${LOCAL_IP} in already down"
    exit 0
else
    error "${LOCAL_IP} Not scheduled for downtime"
fi


