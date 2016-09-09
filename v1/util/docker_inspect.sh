

tmpdir=${TMPDIR-/tmp}/skopos-$RANDOM-$$
mkdir -p $tmpdir
# Cached files                                                                                                                                                                                                                               
DOCKER_INSPECT="$tmpdir/docker_inspect_$(date +%s)"
DOCKER_INSPECT_DIR="$tmpdir/dir"

update_docker_inspect(){
    mkdir -p ${DOCKER_INSPECT_DIR}
    for i in $(docker ps -q); do
      docker inspect $i > ${DOCKER_INSPECT_DIR}/$i.json
    done
    declare -a jsons
    jsons=($(ls -1 ${DOCKER_INSPECT_DIR}/*.json 2>/dev/null) )
    echo '[' > ${DOCKER_INSPECT}
    if [ ${#jsons[@]} -gt 0 ]; then # if the list is not empty
       cat "${jsons[0]}" >> ${DOCKER_INSPECT} # concatenate the first file to the manifest...
       unset jsons[0]                     # and remove it from the list
       for f in "${jsons[@]}"; do         # iterate over the rest
          echo "," >>${DOCKER_INSPECT}
          cat "$f" >>${DOCKER_INSPECT}
       done
    fi
    echo ']' >> $DOCKER_INSPECT
    cat ${DOCKER_INSPECT} | jq '.'
}                                                                                                                                                                                                                                            
update_docker_inspect
