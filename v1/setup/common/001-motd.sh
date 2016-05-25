#!/bin/bash -x

source /etc/environment

echo "-------Beginning writing MOTD-------"

if [ ! -d /etc/motd.d ]; then
    sudo mkdir /etc/motd.d
fi

TEXT="Mesos Cluster\nAccount: ${NODE_TIER}\nTier: ${NODE_ROLE}\nProduct: ${NODE_PRODUCT}"
sudo echo -e  $TEXT > /etc/motd.d/node-info.conf

echo "-------Done writing MOTD-------"
