#!/bin/bash

host_mode_listening(){
    pid=$1
    ps --forest -o pid= $(ps -e --no-header -o pid,ppid|awk -vp=$pid 'function r(s){print s;s=a[s];while(s){sub(",","",s);t=s;sub(",.*","",t);sub("[0-9]+","",s);r(t)}}{a[$2]=a[$2]","$1}END{r(p)}')
}
listening_tcp(){
    sudo netstat -tnlp | grep $(host_mode_listening $1| xargs -n 1 -IXX echo " -e XX") | awk '{print $4}'| sed 's/0.0.0.0/[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/'
}
listening_patterns(){
    listening_tcp $1 | xargs -n 1 -I XX echo " -e XX"
}
echo "listening_tcp $(listening_tcp $1)"
echo "listening_patterns: $(listening_patterns $1)"

set -x
ss -t -o state established   | grep -c -E $(listening_patterns $1)
