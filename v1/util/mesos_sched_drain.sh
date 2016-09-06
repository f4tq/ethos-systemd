#!/usr/bin/bash 
LOCALPATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source $LOCALPATH/../lib/drain_helpers.sh

tmpdir=${TMPDIR-/tmp}/skopos-$RANDOM-$$
mkdir -p $tmpdir
on_exit 'rm -rf  "$tmpdir" '

# json block needed to schedule downtime with mesos
cat <<EOF > $tmpdir/mesos-master.json 
{
  "windows" : [
    {
      "machine_ids" : [
        { "hostname" : "$(hostname --fqdn)", "ip" : "${LOCAL_IP}" }
      ],
       "unavailability" : {
        "start" : { "nanoseconds" : $(date -d "+1 seconds" +%s)000000000 },
        "duration" : { "nanoseconds" : 3600000000000 }
      }
    }
  ]
}
EOF

# schedule the window for this host

# if we're not in the schedule, it failed and likely because the target mesos host is not the master
# check status

if (curl -L -H "Content-type: application/json" -X POST -d @$tmpdir/mesos-master.json ${MESOS_CREDS} ${MESOS_ELB}/maintenance/schedule 2>/dev/null) ; then
    if  [ ! -z "$(curl -SsL -X GET ${MESOS_CREDS} ${MESOS_ELB}/maintenance/status | jq --arg ip ${LOCAL_IP} --arg host $(hostname --fqdn) '.draining_machines[]|select( .id| (.ip ==$ip  and .hostname==$host) )')" ]; then
	#put success message out on stderr
	error_log "successfully scheduled draining"
	exit 0
    else
	error "unable to schedule draining"

    fi
else
    error  "unable to schedule draining.  Is mesos up?"
fi
	    

