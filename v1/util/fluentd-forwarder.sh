#!/usr/bin/bash

if [[ -f /etc/profile.d/etcdctl.sh ]];
  then source /etc/profile.d/etcdctl.sh;
fi

source /etc/environment

IMAGE=$(etcdctl get /images/fluentd)
FLUENTD_FORWARDER_PORT=$(etcdctl get /logging/config/fluentd-forwarder-port)
FLUENTD_MONITOR_PORT=$(etcdctl get /logging/config/fluentd-monitor-port)

/usr/bin/docker run \
  --name fluentd-forwarder \
  -p $FLUENTD_FORWARDER_PORT:5170 \
  -p $FLUENTD_MONITOR_PORT:24220 \
  -e FLUENTD_CONF=fluentd-universal.conf \
  -e FLUENTD_ETHOSPLUGIN_CACHE_SIZE=$(etcdctl get /logging/config/fluentd-ethosplugin-cache-size) \
  -e FLUENTD_ETHOSPLUGIN_CACHE_TTL=$(etcdctl get /logging/config/fluentd-ethosplugin-cache-ttl) \
  -e FLUENTD_ETHOSPLUGIN_GET_TAG_FLAG=$(etcdctl get /logging/config/fluentd-ethosplugin-get-tag-flag) \
  -e FLUENTD_ETHOSPLUGIN_CONTAINER_TAG=$(etcdctl get /logging/config/fluentd-ethosplugin-container-tag) \
  -e FLUENTD_ETHOSPLUGIN_LOGTYPE_RULE="$(etcdctl get /logging/config/fluentd-ethosplugin-logtype-rule)" \
  -e FLUENTD_HTTPEXT_BUFFER_TYPE=$(etcdctl get /logging/config/fluentd-httpext-buffer-type) \
  -e FLUENTD_HTTPEXT_BUFFER_QUEUE_LIMIT=$(etcdctl get /logging/config/fluentd-httpext-buffer-queue-limit) \
  -e FLUENTD_HTTPEXT_BUFFER_CHUNK_LIMIT=$(etcdctl get /logging/config/fluentd-httpext-buffer-chunk-limit) \
  -e FLUENTD_HTTPEXT_FLUSH_INTERVAL=$(etcdctl get /logging/config/fluentd-httpext-flush-interval) \
  -e FLUENTD_HTTPEXT_FLUSH_AT_SHUTDOWN=$(etcdctl get /logging/config/fluentd-httpext-flush-at-shutdown) \
  -e FLUENTD_HTTPEXT_RETRY_WAIT=$(etcdctl get /logging/config/fluentd-httpext-retry-wait) \
  -e FLUENTD_HTTPEXT_MAX_RETRY_WAIT=$(etcdctl get /logging/config/fluentd-httpext-max-retry-wait) \
  -e FLUENTD_HTTPEXT_RETRY_LIMIT=$(etcdctl get /logging/config/fluentd-httpext-retry-limit) \
  -e FLUENTD_HTTPEXT_DISABLE_RETRY_LIMIT=$(etcdctl get /logging/config/fluentd-httpext-disable-retry-limit) \
  -e FLUENTD_HTTPEXT_SPLUNK_URL=$(etcdctl get /logging/config/fluentd-httpext-splunk-url) \
  -e FLUENTD_HTTPEXT_HTTP_METHOD=$(etcdctl get /logging/config/fluentd-httpext-http-method) \
  -e FLUENTD_HTTPEXT_SERIALIZER=$(etcdctl get /logging/config/fluentd-httpext-serializer) \
  -e FLUENTD_HTTPEXT_USE_SSL=$(etcdctl get /logging/config/fluentd-httpext-use-ssl) \
  -e FLUENTD_HTTPEXT_OPEN_TIMEOUT=$(etcdctl get /logging/config/fluentd-httpext-open-timeout) \
  -e FLUENTD_HTTPEXT_READ_TIMEOUT=$(etcdctl get /logging/config/fluentd-httpext-read-timeout) \
  -e FLUENTD_HTTPEXT_RATE_LIMIT_MSEC=$(etcdctl get /logging/config/fluentd-httpext-rate-limit-msec) \
  -e FLUENTD_HTTPEXT_RAISE_ON_ERROR=$(etcdctl get /logging/config/fluentd-httpext-raise-on-error) \
  -e FLUENTD_HTTPEXT_RAISE_ON_HTTP_FAILURE=$(etcdctl get /logging/config/fluentd-httpext-raise-on-http-failure) \
  -e FLUENTD_HTTPEXT_IGNORE_HTTP_STATUS_CODE=$(etcdctl get /logging/config/fluentd-httpext-ignore-http-status-code) \
  -e FLUENTD_HTTPEXT_AUTHENTICATION=$(etcdctl get /logging/config/fluentd-httpext-authentication) \
  -e FLUENTD_HTTPEXT_USERNAME=$(etcdctl get /logging/config/fluentd-httpext-username) \
  -e FLUENTD_HTTPEXT_PASSWORD=$(etcdctl get /logging/config/fluentd-httpext-password) \
  -e FLUENTD_HTTPEXT_SPLUNK_HEC_TOKEN="$(etcdctl get /logging/config/fluentd-httpext-splunk-hec-token)" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  $IMAGE
