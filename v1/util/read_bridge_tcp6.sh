#!/bin/bash 

# When the container is in bridge mode, you can't see any of the connections
# from the docker host i.e. coreos.
# 
# Instead, you need to get the get the official container instance pid from docker inspect 
# then 
#  

# 2 bytes per 2 hex chars

intToIp32() {
    iIp=$1
    printf  "%s.%s.%s.%s" $(($iIp>>24)) $(($iIp>>16&255)) $(($iIp>>8&255)) $(($iIp&255))
}

hex32ToInt() {
    hex=$1
    printf "%d" 0x${hex:6:2}${hex:4:2}${hex:2:2}${hex:0:2}
}
dump64(){
    src_host_port=$1
    a1=$(hex32ToInt  ${src_host_port:24:8})
    a2=$(hex32ToInt ${src_host_port:16:8})
    a3=$(hex32ToInt ${src_host_port:8:8})
    a4=$(hex32ToInt ${src_host_port:0:8})
    #echo "a1: >$a1< a2: >$a2< a3: >$a3< a4: >$a4<"
    i1=$(intToIp32  $a1)
    i2=$(intToIp32  $a2)
    i3=$(intToIp32  $a3)
    i4=$(intToIp32  $a4)
    #echo "i1: >$i1< i2: >$i2< i3: >$i3< i4: >$i4<"
    
    echo "$i4::$i3::$i2::$i1"
}

decodeAddress(){
    addr=$1
    addr_host=$(echo ${addr} | cut -d':' -f1 )
    addr_port=$(echo ${addr} | cut -d':' -f2 )
    echo -n "$(dump64 ${addr_host}):$(hex32ToInt ${addr_port:2:2}${addr_port:0:2})"
}

while read num dest_host_port src_host_port _ _ _ _ _ _ inode _; do
    
    if [[ ${dest_host_port} =~ ^[0-9a-fA-F]{32}:[0-9a-fA-F]{4}$  ]] && [[ ${src_host_port} =~ ^[0-9a-fA-F]{32}:[0-9a-fA-F]{4}$  ]]  ;then
        printf "%s %s\n" $(decodeAddress ${src_host_port}) $(decodeAddress ${dest_host_port})
    else
        echo "Skipping num: ${num} dest:'${dest_host_port}' src:'${src_host_port}' "
    fi
done < "${1:-/dev/stdin}"

