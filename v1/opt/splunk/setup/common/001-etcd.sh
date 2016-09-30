#!/usr/bin/bash -x

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source $DIR/../../../../lib/helpers.sh
source /etc/environment

#ELB rebuilt w/ logging tier
etcd-set /environment/LOGGING_ELB $FLUENTD_INTERNAL_ELB
