#!/bin/bash
LOCALPATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source /etc/environment

if [ -f /etc/profile.d/etcdctl.sh ]; then
    . /etc/profile.d/etcdctl.sh
fi

source $LOCALPATH/../lib/lock_helpers.sh

assert_root

log "Started update-check ..."

test -d /var/lib/skopos || mkdir -p /var/lib/skopos

if !( grep -q '^REBOOT_STRATEGY=off' /etc/coreos/update.conf ) ; then
    #
    # THIS section is a hack until and infrastructure commit add
    # coreos:
    #    reboot-strategy: off
    #
    #  The benefit of the infrastructue commit will be that REBOOT_STRATEGY=off will exit *before* update-engine starts
    #  Without update-engine observing REBOOT_STRATEGY=off, updates needs reboots will not be drained...
    #   
    #
    grep -q '^REBOOT_STRATEGY=' /etc/coreos/update.conf  &&  sed -i 's/^REBOOT_STRATEGY=.*/REBOOT_STRATEGY=off/' /etc/coreos/update.conf || echo 'REBOOT_STRATEGY=off' >> /etc/coreos/update.conf
    # update-engine needs full stop or it will just reboot if it needs to
    while (systemctl is-active update-engine.service) ; do
	systemctl stop update-engine.service
    done
    systemctl stop locksmithd
    systemctl mask locksmithd
    
    systemctl start update-engine.service
    
fi


if [ 0 -lt $(update_engine_client -update 2>&1 |grep -c NEED_REBOOT) ] ;then
    log "CoreOS signaling reboot required"
    touch /var/lib/skopos/needs_reboot
else
    log "CoreOS signaling no reboot required"
fi

