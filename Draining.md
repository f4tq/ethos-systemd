# Skopos
Skopos constitutes the orderly draining and rebooting of CoreOS worker nodes with the goal of no disruption to the Mesos created *docker* container instances running on them & balanced (meaning at least 2 instances) running on *different* nodes within the balancer space.
It is highly recommended that `[[ hostname UNIQUE ]]` marathon constraint with instance count of at least 2 be used for effective use of this PR. 

As docker provides a means to create user defined networks that can be wholey isolated, this project specifically targets docker instances running with *bridged* and *host* networks - as defined by docker.

## Other Assumptions
### General
- The system uses CoreOS
- The system uses AWS (for now)
- etcd is deployed to the control tier with at least 3 nodes
- etcd is accessible from all nodes in the cluster
- fleet functions on all nodes in the cluster
- The mesos slave runs on all nodes in the worker tier
- The mesos masters run in the control tier
- Zookeeper runs on the same node as the mesos-master
- Only docker instances managed by Mesos are drained in the worker tier
- Mesos master and slave are controlled by systemd units and these units are used to manage the Mesos life-cycle
- The system has enough available resources to handle all resources deriving from a drained node
- Only Marathon and Mesos processes are `drained` in the control tier.  

> Due to mesos 0.27 maintenance API issues, the graceful shutdown (full draining) is unsupported in this release.  However orderly draining of the proxy and control tiers is supported

- `Booster draining` resulting from scale down activity is an end of life task for the host
- Inbounds connections to mesos instantiated apps are targeted by this process for tapering and elimination. 
- Outbound connections are the responsibilty of the app instance.  However, this PR process accomodates that shutdown by sending SIGTERM (via docker stop) then waits 300 seconds before sending SIGKILL (via docker kill).

> marathon-lb supports docker instance labeling that, in the future, be used to control the time between `SIGTERM` and `SIGKILL`


## Limitations
- Marathon is currently unable to handle inverse offers from Mesos.
  - Inverse offers are sent by mesos when a node is scheduled for maintenance

##Requirements
- [etcd-locks](https://github.com/adobe-platform/etcd-locks%20etcd-locks) can be pulled from the adobe-platform docker registry/
## Quick start
- With this PR, the update-os.sh process starts via a fleet unit and is intended to run forever.
- Without further action, nothing will happen.
- To cause a reboot on a single host, visit that host and run
```
core@coreos: touch /var/lib/skopos/needs_reboot
```
- To cause the entire worker tier to reboot after draining in an orderly fashion, visit any (worker,proxy,control) node (they all have fleet) and run:
```
core@coreos:/home/core $ sudo ethos-systemd/v1/util/launch_worker_reboot.sh
```
- To cause the core node you're alreay on to drain, booster style, run:
```
core@coreos:/home/core $ sudo ethos-systemd/v1/util/launch_booster_drain.sh
```

## Components
### Standard components
- etcd
- fleet

### Skopos components
Skopos constitutes a locking system and a lot of scripts to handle the draining process.
#### Docker images
##### [etcd-locks](https://github.com/adobe-platform/etcd-locks)

- `etcd-locks` provides a locking system that allows for a configurable number of simultaenous lock holders
- they are akin to semaphores
- locks have values or *tokens*
> cluster-wide lock token values are the machine-id (`cat /etc/machine-id`)
- skopos uses 2 types of locks: cluster-wide and host.
- cluster-wide locks have groups or tiers with a configurable number of simultaneous lock holder per-*group*.
> For instance, the *reboot* lock used for update-os.sh has 3 groups: control, proxy, and workers with simultaneous lock holders defaulting to 1,1 & 1 respectively.  In a large cluster, the worker group may allow for 2 or more simultaneous holders.

> groups names are arbitrary though.
  - see ethos-system/v1/util/lockctl.sh to see how they're configured for skopos.
  - host locks are named after the machine-id.
    - they are intended to help mediate conflicting operations occurring within a single host.
        -  such as guarding from `update-os` and `booster-drain` from occurring at the same time and causing kaos.
    - skopos host lock token values are *REBOOT*, *DRAIN*,*BOOSTER*


#### Scripts
All scripts in skopos are placed in [ethos-systemd](http://github.com/f4tq/ethos-systemd).
Many scripts source [drain_helpers](http://github.com/f4tq/ethos-systemd/v1/lib/drain_helpers.sh) but all source [lock_helpers](http://github.com/f4tq/ethos-systemd/v1/lib/lock_helpers.sh).

##### [update-os.sh](http://github.com/f4tq/ethos-systemd/v1/util/update-os.sh)
 - Single run fleet units that trigger the update-os.sh on each node.  Currently, that amounts to touching /var/lib/skopos/needs_reboot
 
 - Triggers on fleet, systemd unit per worker node
   ```
   fleetctl list-machines | grep role=worker| awk '{print $1}'
   ```
 - Fleet global units don't work since they're hard to destroy.  In the face of auto-scaling, they can have the unintended consequence of starting a reboot on a new node
 
 - Each unit's ExecStart destroys the fleet unit that it's part of as it's last action
 
 - The units leave no trace except on purpose.
 
##### [drain.sh](http://github.com/f4tq/ethos-systemd/v1/util/drain.sh)
Drives the draining process for control,  proxy, and worker tiers.  It uses all locking primitives, schedules mesos maintenance,  uses marathon api, docker and uses iptables to drain connections.

##### [launch_workers_reboot.sh](http://github.com/f4tq/ethos-systemd/v1/util/launch-booster-drain.sh)
Creates a dynamic `oneshot` fleet unit targeting all worker nodes.  In this iteration, it simply touches `/var/lib/skopos/needs_reboot` on all worker nodes.

##### [launch_booster_drain.sh](http://github.com/f4tq/ethos-systemd/v1/util/launch-booster-drain.sh)
- Creates a pure oneshot fleet unit to drive booster draining using only curl, the fleet socket (`/var/run/fleet.socket`) and the value CoreOS machine id (`/etc/machine-id`).
- The created unit targets only the machine-id it's created with.  It explicitely destroys the fleet unit (i.e. itself) it creates via ExecStart 
- The script understands both cli switches and environment variables:
   - Environment variables
      -  `NOTIFY`
      -  `MACHINEID`
   - Command line switches

    `--notify`
	   - default: 'mock' is a no-op
    `--machine-id`
           - default: `cat /etc/machine-id`

The fleet unit invokes [booster-drain.sh](http://github.com/f4tq/ethos-systemd/v1/util/booster-drain.sh)

##### Examples

- Via docker
   - Passing Environment, Mounting /var/run/fleet.socket
   
To satisfy this script, a docker image would include this script then be run  like this:
```
docker run -e MACHINEID=`cat /etc/machine-id` -v /var/run/fleet.socket:/var/run/fleet.socket  adobe-platform/booster
# /usr/local/bin/launch-booster-drain.sh
```
- From any ethos node targets the node its run.
```
sudo ethos-systemd/v1/util/launch_booster_drain.sh --notify http://www.google.com
```
##### From any ethos

####  [booster-drain.sh](http://github.com/f4tq/ethos-systemd/v1/util/booster-drain.sh)
The target of the fleet-unit created by  [launch-booster-drain.sh](http://github.com/f4tq/ethos-systemd/v1/util/launch-booster-drain.sh).

It acquires the cluster-wide, tier specific `booster` lock.  It the then calls `drain.sh` with 'BOOSTER' (used with the host lock) and drives the drain.
If the `--notify` is used,  and is not `mock` then the url is invoked with the machine-id on completion.
####  [lockctl.sh](http://github.com/f4tq/ethos-systemd/v1/util/lockctl.sh)
Provides a cli for locking, unlocking, state retrieval for host and cluster wide locks.
#### Mesos API related
These scripts are used to schedule downtime for mesos master & slaves from the perspective of the node it's executed on.  It determines the 'leader', forms the JSON with the node's context and performs the action.
##### [mesos_sched_drain.sh](http://github.com/f4tq/ethos-systemd/v1/util/mesos_sched_drain.sh)
#####[mesos_down.sh](http://github.com/f4tq/ethos-systemd/v1/util/mesos_down.sh)
#####[mesos_up.sh](http://github.com/f4tq/ethos-systemd/v1/util/mesos_up.sh)
#####[mesos_status.sh](http://github.com/f4tq/ethos-systemd/v1/util/mesos_status.sh)

#### Support scripts
##### Helpers
###### [lock_helpers.sh](http://github.com/f4tq/ethos-systemd/lock_helpers.sh)
 These bash helpers provide wrappers around the `etcd-locks` docker image.
  They also establish an `exit` hook that provides exit chaining used extensively to clear iptables, free locks, free temp files, etc in case of unexpected exits.
###### [drain_helpers.sh](http://github.com/f4tq/ethos-systemd/drain_helpers.sh)
  Contains script for draining tcp and docker instances.

####[read_tcp6](http://github.com/f4tq/ethos-systemd/v1/util/read_tcp6.sh)
This script decodes established connections for docker instances running in bridged network mode.  Such connections are not reported by `netstat` as they are routed by iptables using `PREROUTING` and `FORWARDING` chains in the `nat` and `filter` tables respectively.

To use this with docker, you get the pid and process tree of the image report via `docker inspect` then `cat /proc/$pid/net/tcp6` to this script.
> drain obviously make heavy use of this to measure remaining connections

## Process
This section gives an overview of important processes.

### [update-os.sh](github.com/adobe-platform/v1/util/update-os.sh)
The main process mediates system reboots primarily due to CoreOS updates.

- If the current node holds the cluster-wide reboot lock on service startup:
  - Ensure zookeeper is up and healthy
  - Ensure mesos is up and healthy
  - Flush the SKOPOS table `iptables`
  - Tell Mesos that maintenance is complete
     - By calling Mesos maintenance API `/maintenance/up`
  - Release cluster-wide reboot-lock
- Wait for reboot trigger
- On reboot trigger occurance
   	- currently, the presence of the file `/var/lib/skopos/needs_reboot` 
- wait forever for cluster-wide `reboot lock` for tier
- invoke [drain script](http://github.com/adobe-platform/ethos-system/util/drain.sh) with token `REBOOT`
- on success, reboot *holding* drain lock

> Note: it is *very* important that the node re-establish itself *after* reboot *before* unlock reboot.

### [drain.sh](http://github.com/adobe-platform/ethos-system/util/drain.sh) script
CLI with mulitple options available for standalone use.  It's primary callers are update-os.sh and booster-drain.sh.

#### options

##### drain
The primary option.  This script usually called by booster-drain.sh or update-os.sh.
The *drain* takes optional value that which gets used as the host lock value by etcd-locks.  It is useful to use a verb to describe what called for drain.   drain values:
- *DRAIN*
The default.
- *REBOOT*
Value passed by update-os.sh when invoking `drain.sh drain REBOOT`
- *BOOSTER*
Value passed by booster-drain.sh.  Ex. `drain.sh drain BOOSTER`

###### Process
- setup
  - Determine Mesos unit for tier
    - If a mesos slave node, cross-reference mesos api, marathon api and docker api to yield target pids, ports, and instances tied to host.

- acquire the *host lock* using token value(*DRAIN*,*REBOOT*, or *BOOSTER*)
> Waits until acquired

   - register an on exit `lockctl unlock_host [DRAIN|BOOSTER|REBOOT]` once acquired

- if mesos-slave is 0.28 or less,  stop mesos-slave
> Note:  After 0.28, the mesos api is used to schedule draining which keeps new offers from arriving.  Unfortunately, using the mesos api */maintenance/down* call - before 0.28.1 - abruptly takes not only the mesos-slave process down but all docker dependents *without* draining
- call function drain_tcp
   - if the node is in the control tier,
         - Force Marathon leader away for node if necessary (waits)
	    - Use Mesos maintenance api to schedule, then down the node
	    > Note: Again after Mesos 0.28

   - Create iptables Chain `SKOPOS` on the PREROUTING (nat table) and filter (INPUT &FORWARD) chains
   > Note: this chain does not survive reboot - and shouldn't -  unless someone calls `iptables-save`

   - Create iptables rules derived from marathon, docker, mesos, and read_tcp data for both `bridge` and `host` docker networks
   > Note: at this point existing connections will continue while new connect attempts are refused.  Also, this works for the control tier with the lone exception that long-running connections ignore Mesos maintenance settings.

   - If the control tier, poll the mesos ELB endpoint and `/redirect`  api call until the current not is not a value.
      - Count down until the connection count reaches zero of 300 seconds elapses.

- call drain_docker
Drain docker calls
- unlock   *host lock*


##### show_fw_rules
Shows the firewall rules that *will* be used during draining.
###### Example
```
core@ip-172-16-26-239 ~ $ sudo ethos-systemd/v1/util/drain.sh show_fw_rules
iptables -A SKOPOS -p tcp -m string --algo bm --string ELB-HealthChecker -j REJECT
iptables -A SKOPOS -p tcp --syn --dport 8080 -d 0.0.0.0/0 -j REJECT
iptables -A SKOPOS -p tcp --syn --dport 5050 -d 0.0.0.0/0 -j REJECT
drain.sh show_fw_rules
```
##### connections
Shows the total number of connections open to resources targeted for the tier.
For the worker,  aka mesos-slave nodes, this is a measure of the *mesos* initiated docker instances.  All other docker instances are not counted.
###### Examples
```
core@ip-172-16-26-239 ~ $ sudo ethos-systemd/v1/util/drain.sh connections
172.16.26.239:5050 172.16.26.237:38506
172.16.26.239:5050 172.16.26.239:42362
172.16.26.239:5050 172.16.27.239:59845
172.16.26.239:5050 172.16.26.164:15168
172.16.26.239:5050 172.16.24.142:2619
172.16.26.239:5050 172.16.24.195:1245
```

### booster_drain.sh
- Follows a similar process to update-os.sh except that it needn't consider rebooting and reversing any action taken as it's action is end of life for the host.

- Acquire the cluster-wide *booster_drain* lock
- Call drain.sh with 'BOOSTER'
  - See drain.sh
  > Note: At this point all mesos driven docker containers are down as is the mesos unit (slave or master).  iptables rules



## Support
In order to show the draining, there must be load.  To create that load:
### [dcos-tests](https://github.com/f4tq/dcos-tests)
http server project whose api accepts urls that sleep for the user provide period to simulate long running processes.
It also accepts a time period where it optionally sleeps after receiving `SIGTERM` after closing it's listener.   Existing connections remain in process and are allowed to finish if the period is long enough.
### locust
locust is stood up in master-slave mode on the control tiers.
#### [test-drain.py](https://github.com/adobe-platform/skopos/blob/fleet/locust-1/test_drain.py)
#### [ansible driven build/start/stop](https://git.corp.adobe.com/fortescu/Mesos4Dexi/blob/master/drain_test.yml#L244)

## [drain_process.md](https://github.com/adobe-platform/skopos/blob/fleet/drain_process.md)


# Troubleshooting
All the following commands are performed with ansible

### Start update-os.sh with fleet
```
ansible coreos_control -i $INVENTORY  -m raw -a 'bash -c "set -x ; LOCALIP=$(curl -sS http://169.254.169.254/latest/meta-data/local-ipv4);  ( etcdctl member list  | grep \$LOCALIP | grep -q isLeader=true ) && fleetctl start update-os.service" '
```

### Stop update-os.sh with fleet
```
ansible coreos_control -i $INVENTORY  -m raw -a 'bash -c "set -x ; LOCALIP=$(curl -sS http://169.254.169.254/latest/meta-data/local-ipv4);  ( etcdctl member list  | grep \$LOCALIP | grep -q isLeader=true ) && fleetctl stop update-os.service" '
```

### Reset all locks, iptables wrt skopos
Stop update-os.sh first
```
ansible coreos_control:coreos_workers -i $INVENTORY  -m raw -a 'bash -c "rm -f /var/lib/skopos/needs_reboot; iptables -F SKOPOS; ethos-systemd/v1/util/mesos_up.sh; ethos-systemd/v1/util/lockctl.sh unlock_reboot; ethos-systemd/v1/util/lockctl.sh unlock_host REBOOT"'  -s
```
### Monitor progress of workers reboot
```
ansible coreos_workers -i $INVENTORY   -m raw -a 'bash -c "echo \"Reboot Lock holder: \$(ethos-systemd/v1/util/lockctl.sh reboot_state)\"; echo \"Booster Lock holder: \$(ethos-systemd/v1/util/lockctl.sh booster_state)\";echo \"MachineID: \$(cat /etc/machine-id)\" ; echo \"HostState: \$(ethos-systemd/v1/util/lockctl.sh host_state)\"; echo \"Load: \$(cat /proc/loadavg)\";echo \"Active Conns: \$(ethos-systemd/v1/util/drain.sh connections | wc -l )\"; ls -l /var/lib/skopos; echo \"mesos_status: \$(ethos-systemd/v1/util/mesos_status.sh)\"; echo -n \"uptime: \";uptime "; iptables -nL SKOPOS -v' -s
```

### Output last 25 lines of `journald -u update-os.service` across worker tier
```
ansible coreos_workers -i $INVENTORY  -m raw -a 'bash -c "journalctl -u update-os.service --no-pager  | tail -25 "' 
```



>
> Written with [StackEdit](https://stackedit.io/).
