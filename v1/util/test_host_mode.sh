#!/bin/bash

listen=false
established=true
pid=0

host_mode_listening(){
    ps --forest -o pid= $(ps -e --no-header -o pid,ppid|awk -vp=$pid 'function r(s){print s;s=a[s];while(s){sub(",","",s);t=s;sub(",.*","",t);sub("[0-9]+","",s);r(t)}}{a[$2]=a[$2]","$1}END{r(p)}')
}
listening_tcp(){
    sudo netstat -tnlp | grep $(host_mode_listening $pid| xargs -n 1 -IXX echo " -e XX")
}
listening_patterns(){
    set -x
    listening_tcp $pid | awk '{print $4}'| awk -F: '{printf "\":%d \"\n",$NF}' | xargs -n 1 -I XX echo " -e XX"
}



function usage(){
    if [ ! "$1" ];then
	echo "$1"
    fi
            cat <<EOF

$0 Dump connections stored in /proc/<your pid>/net/tcp6
 Options:
   -L Dump listeners.  Default: false
   -E Dump established. Default: true
   -p <pid> REQUIRED
EOF
        exit -1
}

while getopts p:LE opt; do

    case $opt in
	L)
	    echo "LISTEN"
            listen=true
            ;;
	E)
            established=false
            ;;
	p)
	    pid=$OPTARG
	    ;;
	*)
            usage "unknown option '$opt"
            ;;
    esac
done

if [ ! $listen -a ! $established ]; then
  usage "Please choose listen (-L ) or established (-E)"
fi
if [ 0 -eq $pid ];then
    usage "You must include a pid -p"
fi
shift "$((OPTIND - 1))"

#echo "listen: $listen"
#echo "established: $established"

if $listen; then
    for hp in $(listening_tcp $pid |awk '{print $4}'); do
	port=$(echo $hp | grep -o '[^:]*$')
	host=$(echo $hp | sed "s/:$port\$//")
#	echo "host: $host"
	#	echo "port: $port"
	case $host in
	    '::'|'0.0.0.0'|'*')
		host='*'
	esac
	echo "$host;$port"
    done
else
    echo "NOT Listen"
    ss -t -o state established   | grep -c -E $(listening_patterns $pid)
fi
