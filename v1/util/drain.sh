#!/bin/bash 

# This script assumes you already hold the appropriate lock
# It will check to make sure and error out if the lock holder doesn't contain this host's machine-id `cat /etc/machine-id`
#

LOCALPATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source $LOCALPATH/../lib/drain_helpers.sh

assert_root


#
# control node have mesos/marathon in docker instances for ethos
# and running natively for dcos
#
drain_control(){
    if [ ! -z "$1" ];then
	# Get docker info
	update_docker_inspect
    fi
    
    case "$1" in
	drain_tcp)
	    drain_tcp
	    ;;
	drain_docker)
	    drain_docker
	    ;;
	drain)
	    drain $2
	    ;;
	connections)
	    show_marathon_connections
	    ;;
	show_fw_rules)
	    generate_marathon_fw_rules
	    
	    ;;
	*)
	    cat <<EOF
Usage: drain the host
     Tier: ${NODE_ROLE}

     drain_tcp - syn blocks mesos-master, marathon,zk and etcd to force leadership to another node
     drain_docker - takes 
     drain <option token>  
              - locks host-lock with "DRAIN|<token>" 
		 - if it's not already locked.  
	     - locks the drain cluster-wide lock
	     - grabs docker data
	     - stops mesos
	     - call drain_tcp which works with host and bridge network types
	     - calls drain_docker which calls docker stop, waits a period of time to ensure all instances stop, then calls docker kill
	     - unlocks cluster-wide lock
	     - unlocks host lock
      show_fw_rules - show fw rules that would be used to drain this host
      connections - show all the connections targeted for draining
EOF
	    ;;
    esac
}

drain_worker(){
    if [ ! -z "$1" ];then
	# Get docker info
	
	if [ -z "$(update_docker_inspect)" ]; then
	    # TODO: error for now, but actually edge case.
	    # Nothing is running so just drain
	    finish_ok "No docker instances"
	fi
	if [ -z "$(  update_slave_info )" ] ;then
	    finish_ok "No slave info. Is mesos-slave running?"
	fi
	# Getting the slave Id.
	SLAVE_ID=$( slave_info | jq -r .id)
	if [ -z "${SLAVE_ID}" ]; then
	    #
	    # it is weird to call this ok as there is always a slave it if the slave is running.
	    # 
	    finish_ok "No slave id found.  Is the mesos-slave running?"
	fi
	SLAVE_HOST=$( slave_info | jq -r .hostname)
	
	# Get marathon info filtered by this slave
	THIS_SLAVES_MARATHON_JOBS=$(update_marathon_jobs $SLAVE_ID)
    fi
    
    case "$1" in
	
	marathon_jobs)
	    marathon_jobs
	    ;;
	marathon_docker_ids)
	    show_marathon_docker_ids
	    marat
	    ;;
	marathon_docker_pids)
	    show_marathon_docker_pids
	    ;;
	connections)
	    show_marathon_connections
	    ;;
	show_fw_rules)
	    generate_marathon_fw_rules
	    
	    ;;
	host_ports)
	    host_ports
	    ;;
	just_ports)
	    just_ports
	    ;;
	drain_tcp)
	    drain_tcp
	    ;;
	drain_docker)
	    drain_docker
	    ;;
	drain)
	    drain $2
	    ;;
	
	*)
	    cat <<EOF 
Usage: drain {marathon_jobs|marathon_docker_ids|marathon_docker_pids|connections|show_fw_rules|host_ports|just_ports|drain_tcp|drain_docker|drain}
     Tier: ${NODE_ROLE}

     Drains a mesos & marathon managed node where the tasks are docker instances in bridged or host network mode

     On worker nodes, like this, only docker jobs associated with mesos slaves are drained.

     Ethos assumptions:  All endpoints are in etcd and that all nodes have access to etcd.

     host_ports - outputs the pipe separated list ip:ports for this listening on this slave
     just_ports - is just the ports separated by pipes for grep
     marathon_jobs - outputs json with the mesos_task_id
     marathon_docker_ids -- terse list of docker instance ids
     marathon_docker_pids -- list of pids 
     connections -- show all ESTABLISHED connection for this host related to marathon tasks.  Both 'host' and 'bridged'
     marathon_docker_jobs - takes the output of marathon_jobs and search docker_inspect in a xref into the .Config.Env for the task id.  Mesos sets the task id into the docker instances it starts.
     show_fw_rules - no-op that shows the listeners for each docker pid.  Used to block marathon with iptables
     drain_tcp - stops the mesos slave and waits for all the ports coming from host_ports in an ESTABLISHED state to drop to zero.
     drain_docker - takes 
     drain <option token>  
              - locks host-lock with "DRAIN|<token>" 
		 - if it's not already locked.  
	     - locks the drain cluster-wide lock
	     - grabs mesos-slave,docker, and marathon data
	     - stops mesos
	     - call drain_tcp which works with host and bridge network types
	     - calls drain_docker which calls docker stop, waits a period of time to ensure all instances stop, then calls docker kill
	     - unlocks cluster-wide lock
	     - unlocks host lock


EOF
            exit 1
            ;;
    esac
    
}



if [ "${NODE_ROLE}" == "worker" ]; then
    #>&2 echo "No mesos drain for non-worker role ${NODE_ROLE}"
    drain_worker $*
elif  [ "${NODE_ROLE}" == "control" ] || [ "${NODE_ROLE}" == "proxy" ]; then
    drain_control $*
fi
