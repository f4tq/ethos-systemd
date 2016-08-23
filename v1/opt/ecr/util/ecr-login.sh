#!/usr/bin/bash -x

source /etc/profile.d/etcdctl.sh
source /etc/environment

IMAGE=$(etcdctl get /images/ecr-login)
REGISTRY_ACCOUNT=$(etcdctl get /ECR/config/registry-account)
AWS_REGION=$(etcdctl get /ECR/config/region)
DOCKER_CFG_LOCATION="/home/core/.dockercfg"

# Remove old docker container
docker rm -f ecr-login || :

function copyAndExit() {
	sudo cp $DOCKER_CFG_LOCATION /root/.dockercfg
	exit 0
}

if [[ -n "$REGISTRY_ACCOUNT" ]]; then
    for REG_NUM in $REGISTRY_ACCOUNT
    do
        docker rm ecr-login

        # Hack workaround - IAM proxy does not become useable on instance until after container is pulled and live (~2 min)
        # If this tries to run before that the service will fail
        if [[ "$NODE_ROLE" = "worker" ]]; then
            ECR_CFG=$(docker run --label com.swipely.iam-docker.iam-profile="$CONTAINERS_ROLE" --name ecr-login -e "TEMPLATE=templates/dockercfg.tmpl" -e "AWS_REGION=$AWS_REGION" -e "REGISTRIES=$REG_NUM" $IMAGE)

            while [ $? != 0 ]; do
                echo "Waiting for IAM proxy to become live before launching ECR..."
                sleep 5;
                docker rm ecr-login
                ECR_CFG=$(docker run --label com.swipely.iam-docker.iam-profile="$CONTAINERS_ROLE" --name ecr-login -e "TEMPLATE=templates/dockercfg.tmpl" -e "AWS_REGION=$AWS_REGION" -e "REGISTRIES=$REG_NUM" $IMAGE)
            done
        else
            ECR_CFG=$(docker run --label com.swipely.iam-docker.iam-profile="$CONTAINERS_ROLE" --name ecr-login -e "TEMPLATE=templates/dockercfg.tmpl" -e "AWS_REGION=$AWS_REGION" -e "REGISTRIES=$REG_NUM" $IMAGE)
        fi

        if [[ -z $ECR_CFG ]]; then
            echo "ECR config could not be obtained"
            continue;
        fi

        ECR_CFG_REGISTRY=$(echo $ECR_CFG | jq 'keys[0]')

        if [[ -z $ECR_CFG_REGISTRY ]]; then
            echo "ECR config did not contain valid registry"
            continue;
        fi

        ECR_CFG_CONTENTS=$(echo $ECR_CFG | jq ".$ECR_CFG_REGISTRY")

        if [[ -z $ECR_CFG_CONTENTS ]]; then
            echo "ECR config did not contain valid contents"
            continue;
        fi

        # If a dockercfg file doesn't already exist (odd), we can just write and exit
        if [[ ! -f $DOCKER_CFG_LOCATION || ! -s $DOCKER_CFG_LOCATION ]]; then
            echo "$ECR_CFG" > $DOCKER_CFG_LOCATION
            continue;
        fi

        # Otherwise, need to append or modify the new config to existing
        EXISTING_CFG=$(cat $DOCKER_CFG_LOCATION)
        NEW_CONFIG=$(echo $EXISTING_CFG | jq ".$ECR_CFG_REGISTRY=$ECR_CFG_CONTENTS")

        echo $NEW_CONFIG > $DOCKER_CFG_LOCATION
    done

    copyAndExit
else
	echo "No registry account set"
	exit 0
fi