#!/usr/bin/bash -x

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source $DIR/../../../../lib/helpers.sh
source /etc/environment

etcd-set /aqua/config/db-path "${POSTGRES_DB_PATH::-5}"
etcd-set /aqua/config/db-name "scalock_ten"
etcd-set /aqua/config/db-audit-name "slk_audit_ten"
etcd-set /aqua/config/aqua-token "aquatoken"
etcd-set /aqua/config/user "administrator"
etcd-set /aqua/config/password "password"
etcd-set /aqua/config/gateway-host "$AQUA_INTERNAL_ELB"
etcd-set /aqua/config/gateway-external "https://$AQUA_EXTERNAL_DNS"
