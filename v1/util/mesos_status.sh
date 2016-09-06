#!/usr/bin/bash 
LOCALPATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source $LOCALPATH/../lib/drain_helpers.sh

tmpdir=${TMPDIR-/tmp}/skopos-$RANDOM-$$
mkdir -p $tmpdir
on_exit 'rm -rf  "$tmpdir" '

curl -SsL -X GET ${MESOS_CREDS} ${MESOS_ELB}/maintenance/status
