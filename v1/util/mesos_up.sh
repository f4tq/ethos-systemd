#!/usr/bin/bash 

LOCALPATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source $LOCALPATH/../lib/drain_helpers.sh

tmpdir=${TMPDIR-/tmp}/skopos-$RANDOM-$$
mkdir -p $tmpdir
on_exit 'rm -rf  "$tmpdir" '


if [ ! -z "$( curl -SsL ${MESOS_CREDS} ${MESOS_URL}/maintenance/status | jq --arg ip ${LOCAL_IP} --arg host $(hostname --fqdn) '.down_machines[]|select( .ip ==$ip  and .hostname==$host )' 2>/dev/null)" ]; then
    # good.this host is down. 
    cat <<EOF > $tmpdir/up-host.json
[
        { "hostname" : "$(hostname --fqdn)", "ip" : "${LOCAL_IP}" }
]
EOF

    if [ 0 -lt $(curl -Ls -v -H "Content-type: application/json" -X POST -d @$tmpdir/up-host.json ${MESOS_CREDS} ${MESOS_URL}/machine/up 2>&1| grep -c 'HTTP.*200.*OK') ] ; then
	error_log "successfully up ${LOCAL_IP}"
	exit 0
    else
	error "failed to up ${LOCAL_IP}"
    fi
else
    log "${LOCAL_IP} not down"
    exit 0
fi


