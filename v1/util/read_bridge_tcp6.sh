#!/bin/bash 

# When the container is in bridge mode, you can't see any of the connections
# from the docker host i.e. coreos.
# 
# Instead, you need to get the get the official container instance pid from docker inspect 
# then 
#  
only32=true

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
    if ${only32}; then
	echo "$i1"
    else
	echo "$i4::$i3::$i2::$i1"
    fi
}

decodeAddress(){
    addr=$1
    addr_host=$(echo ${addr} | cut -d':' -f1 )
    addr_port=$(echo ${addr} | cut -d':' -f2 )
    echo -n "$(dump64 ${addr_host}):$(hex32ToInt ${addr_port:2:2}${addr_port:0:2})"
}

:<<EOF
Docker Bridged mode; 

x=docker inspect -f '{{State.pid}}'; cat /proc/$x/net/tcp6


  sl  local_address                         remote_address                        st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode
   0: 00000000000000000000000000000000:2329 00000000000000000000000000000000:0000 0A 00000000:00000000 00:00000000 00000000     0        0 4081442 1 0000000000000000 100 0 0 10 0
   1: 00000000000000000000000000000000:1F90 00000000000000000000000000000000:0000 0A 00000000:00000000 00:00000000 00000000     0        0 4081444 1 0000000000000000 100 0 0 10 0
   2: 0000000000000000FFFF0000030011AC:1F90 0000000000000000FFFF0000801C10AC:8C58 01 00000000:00000000 02:0000343D 00000000     0        0 6868046 2 0000000000000000 20 4 32 10 -1
   3: 0000000000000000FFFF0000030011AC:1F90 0000000000000000FFFF0000801C10AC:8E36 01 00000000:00000000 02:00003BD6 00000000     0        0 6869046 2 0000000000000000 20 4 32 10 -1
   4

enum {
    TCP_ESTABLISHED = 1,
    TCP_SYN_SENT,
    TCP_SYN_RECV,
    TCP_FIN_WAIT1,
    TCP_FIN_WAIT2,
    TCP_TIME_WAIT,
    TCP_CLOSE,
    TCP_CLOSE_WAIT,
    TCP_LAST_ACK,
    TCP_LISTEN,
    TCP_CLOSING,    /* Now a valid state */

    TCP_MAX_STATES  /* Leave at the end! */
};
EOF
while read num dest_host_port src_host_port st _ _ _ _ _ inode _; do
    
    if [[ ${dest_host_port} =~ ^[0-9a-fA-F]{32}:[0-9a-fA-F]{4}$  ]] && [[ ${src_host_port} =~ ^[0-9a-fA-F]{32}:[0-9a-fA-F]{4}$  ]]  ;then
	st_num=$(printf "%d" 0x$st)
	case "$st" in
	    "0A")
	    # Listen
	    # skip list
		     
	    ;;
	    "01")
		printf "%s %s\n" $(decodeAddress ${src_host_port}) $(decodeAddress ${dest_host_port})
	    ;;
	    *)
		# skip TCP_FIN_WAIT*/TCP_SYN*/TCP_CLOS*/*ACK
	esac
    fi
done < "${1:-/dev/stdin}"

