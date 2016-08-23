#!/usr/bin/bash -x

source /etc/environment


SCALOCK_ADMIN_PASSWORD=$(etcdctl get /aqua/config/password)

# Wait for web ui to be active
WEB_ACTIVE=$(curl http://localhost:8083/api)

while [[ -z $WEB_ACTIVE ]]; do
  echo "Waiting for web UI to become active"
  WEB_ACTIVE=$(curl http://localhost:8083/api)
  sleep 5;
done

sudo curl -H "Content-Type: application/json" -u administrator:$SCALOCK_ADMIN_PASSWORD -X POST -d '{"name":"core-user rule","description": "Core User is Admin of all containers","role":"administrator","resources":{"containers":["*"],"images":["*"],"volumes":["*"],"networks":["*"]},"accessors":{"users":["core"]}}' http://localhost:8083/api/v1/adminrules
