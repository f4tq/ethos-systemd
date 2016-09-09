#!/bin/bash
LOCALPATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source /etc/environment

if [ -f /etc/profile.d/etcdctl.sh ]; then
    . /etc/profile.d/etcdctl.sh
fi

source $LOCALPATH/../lib/lock_helpers.sh

assert_root

log "Started..."
# update timer

if [ 0 -lt $(update_engine_client -update 2>&1 |grep -c NEED_REBOOT) ] ;then
    log "CoreOS signaling reboot required"
    touch /var/lib/skopos/needs_reboot
else
    log "CoreOS signaling no reboot required"
fi

