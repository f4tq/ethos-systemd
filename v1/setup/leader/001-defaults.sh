#!/usr/bin/bash -x

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source /etc/environment
source $DIR/../../lib/helpers.sh

echo "-------Leader node, beginning writing all default values to etcd-------"

######################
#     IMAGES
######################

# TODO: this overloads the machine

etcd-set /images/secrets-downloader     "index.docker.io/behance/docker-aws-secrets-downloader:v1.1.0"
etcd-set /images/klam-ssh               "index.docker.io/behance/klam-ssh:v1"

etcd-set /images/chronos                "index.docker.io/mesosphere/chronos:chronos-2.4.0-0.1.20150828104228.ubuntu1404-mesos-0.27.0-0.2.190.ubuntu1404"
etcd-set /images/flight-director        "index.docker.io/behance/flight-director:cb14c9003da97171409974c103de6a017db023c0"
etcd-set /images/marathon               "index.docker.io/mesosphere/marathon:v0.15.1"
etcd-set /images/mesos-master           "index.docker.io/mesosphere/mesos-master:0.27.0-0.2.190.ubuntu1404"
etcd-set /images/zk-exhibitor           "index.docker.io/behance/docker-zk-exhibitor:v1.0.0"
etcd-set /images/cfn-signal             "index.docker.io/behance/docker-cfn-bootstrap:v1.0.0"
etcd-set /images/jenkins                "index.docker.io/jenkins:1.651.1"
etcd-set /images/booster                "index.docker.io/behance/booster:0.1"

etcd-set /images/capcom                 "index.docker.io/behance/capcom:3ddcfe360a95adcf97d4e9f3a98f9e59057e55c6"
etcd-set /images/proxy                  "index.docker.io/nginx:1.9.5"
etcd-set /images/control-proxy          "index.docker.io/behance/apigateway:v0.0.1"

etcd-set /images/mesos-slave            "index.docker.io/mesosphere/mesos-slave:0.27.0-0.2.190.ubuntu1404"

etcd-set /images/etcd-locks              "index.docker.io/adobeplatform/etcd-locks:v0.1"

######################
#      CAPCOM
######################

etcd-set /bootstrap.service/capcom              true
etcd-set /capcom/config/applications            '[]'
etcd-set /capcom/config/host                    127.0.0.1
etcd-set /capcom/config/db-path                 ./capcom.db
etcd-set /capcom/config/kv-store-server-address http://$CAPCOM_KV_ENDPOINT
etcd-set /capcom/config/kv-ttl                  10
etcd-set /capcom/config/log-level               "info"
etcd-set /capcom/config/log-location            "stdout"
etcd-set /capcom/config/port                    2002
etcd-set /capcom/config/proxy                   nginx
etcd-set /capcom/config/proxy-config-file       /etc/nginx/nginx.conf
etcd-set /capcom/config/proxy-enabled           true
etcd-set /capcom/config/proxy-restart-script    /restart_nginx_docker.sh
etcd-set /capcom/config/proxy-timeout           60000
etcd-set /capcom/config/proxy-docker-command    "nginx -g 'daemon off;'"
etcd-set /capcom/config/ssl-cert-location       ""


######################
#  FLIGHT DIRECTOR
######################

etcd-set /bootstrap.service/flight-director true
etcd-set /flight-director/config/api-server-port 2001
etcd-set /flight-director/config/chronos-master "$FLIGHT_DIRECTOR_CHRONOS_ENDPOINT"
etcd-set /flight-director/config/db-name "$FLIGHT_DIRECTOR_DB_NAME"
etcd-set /flight-director/config/db-engine mysql
etcd-set /flight-director/config/db-path "$FLIGHT_DIRECTOR_DB_PATH"
etcd-set /flight-director/config/db-username "$FLIGHT_DIRECTOR_DB_USERNAME"
etcd-set /flight-director/config/dockercfg-location file:///root/.dockercfg
etcd-set /flight-director/config/debug false
etcd-set /flight-director/config/event-interface ''
etcd-set /flight-director/config/event-port 2001
etcd-set /flight-director/config/fixtures "prod"
etcd-set /flight-director/config/kv-server http://localhost:2379
etcd-set /flight-director/config/log-level "info"
etcd-set /flight-director/config/log-location "stdout"
etcd-set /flight-director/config/log-marathon-api-calls false
etcd-set /flight-director/config/marathon-master "$FLIGHT_DIRECTOR_MARATHON_ENDPOINT"
etcd-set /flight-director/config/mesos-master "$FLIGHT_DIRECTOR_MESOS_ENDPOINT"
etcd-set /flight-director/config/marathon-master-protocol http
etcd-set /flight-director/config/allow-marathon-unverified-tls false
etcd-set /flight-director/config/mesos-master-protocol http
etcd-set /flight-director/config/authorizer-type airlock
etcd-set /flight-director/config/iam-role-label com.swipely.iam-docker.iam-profile


######################
#     ZOOKEEPER
######################

etcd-set /bootstrap.service/zookeeper true

etcd-set /zookeeper/config/exhibitor/s3-prefix  "zk"
etcd-set /zookeeper/config/exhibitor/s3-bucket  $EXHIBITOR_S3BUCKET
etcd-set /zookeeper/config/ensemble-size        $CONTROL_CLUSTER_SIZE
etcd-set /zookeeper/config/endpoint             $ZOOKEEPER_ENDPOINT
etcd-set /zookeeper/config/username             "zk"
etcd-set /zookeeper/config/password             "password"


######################
#        MESOS
######################

etcd-set /mesos/config/username ethos

######################
#       BOOSTER
######################

etcd-set /booster/config/enabled 0

######################
#      SERVICES
######################

etcd-set /environment/services "sumologic datadog"

######################
#      skopos
######################

# effects number of simulataneous lock holder per-tier for coreos updates
etcd-set /adobe.com/settings/etcd-locks/coreos_updates/num_worker 1
etcd-set /adobe.com/settings/etcd-locks/coreos_updates/num_control 1
etcd-set /adobe.com/settings/etcd-locks/coreos_updates/num_proxy 1



echo "-------Leader node, done writing all default values to etcd-------"
