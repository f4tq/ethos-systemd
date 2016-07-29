#!/usr/bin/bash -x

# NOTE: this script will need to be sudo'ed for access to /var/lib/docker

echo "Removing dead containers & volumes"
docker rm $(docker ps -a -q) 2> /dev/null | xargs -n 1 -IXX echo "docker: Removing dead container XX"  
 
echo "Removing images"
docker rmi -f $(docker images -q -a -f dangling=true) 2> /dev/null | xargs -n 1 -IXX echo "docker: Removing dead image XX"  

FSDRIVER=$(docker info|grep Storage|cut -d: -f2|tr -d [:space:])
echo "Driver $FSDRIVER"
echo "---- Complete ----"

sudo free -h
if [ "$FSDRIVER" = "devicemapper" ]; then
    sudo lvdisplay | grep Allocated | xargs -n 1 -IXX echo "docker lvm XX"
    docker info | grep Data | xargs -n 1 -IXX echo "docker XX"
else
    sudo df -Th
fi
