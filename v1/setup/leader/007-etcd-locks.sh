#!/usr/bin/bash -x

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source $DIR/../../lib/lock_helpers.sh

set -x

# Setup cluster wide locks

cluster_init

