#!/usr/bin/bash -x
sudo touch /etc/audit/rules.d/89-audit.rules
sudo chmod 666 /etc/audit/rules.d/89-audit.rules

cat << EOF > /etc/audit/rules.d/89-audit.rules
-w /usr/bin/docker -k docker
-w /var/lib/docker -k docker
-w /etc/docker -k docker
-w /usr/lib64/systemd/system/docker.service -k docker
-w /usr/lib64/systemd/system/docker.socket -k docker
-w /etc/default/docker -k docker
-w /etc/docker/daemon.json -k docker
-w /usr/bin/docker-containerd -k docker
-w /usr/bin/docker-runc -k docker
EOF

sudo chmod 644 /etc/audit/rules.d/89-audit.rules
sudo systemctl restart audit-rules.service
