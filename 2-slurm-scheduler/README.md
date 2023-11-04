## The Slurm Scheduler

### The NFS Folder

We first set up the NFS network disk to share files across nodes.

```
# For the manager node
$ sudo apt install ntpdate nfs-kernel-server -y

# Create a shared folder /mnt/slurmfs
$ sudo mkdir /mnt/slurmfs
$ sudo chown nobody.nogroup /mnt/slurmfs
$ sudo chmod -R 777 /mnt/slurmfs

# Auto-mount the NFS folder
$ sudo vim /etc/exports

    /mnt/slurmfs    <lan network>(rw,sync,no_root_squash,no_subtree_check)
    /mnt/slurmfs    192.168.1.0/24(rw,sync,no_root_squash,no_subtree_check)

$ sudo exportfs -a
$ sudo systemctl restart nfs-kernel-server

# Test (Share a file)
$ touch /mnt/slurmfs/manager
```

```
# For each compute node (Replace the MANAGER_IP)
$ sudo apt install ntpdate nfs-common -y
$ sudo mkdir /mnt/slurmfs
$ sudo chown nobody.nogroup /mnt/slurmfs
$ sudo mount MANAGER_IP:/mnt/slurmfs /mnt/slurmfs

$ Auto-mount the NFS folder
$ sudo vim /etc/fstab
    <manager node ip>:/mnt/slurmfs    /mnt/slurmfs    nfs    defaults   0 0
    192.168.1.219:/mnt/slurmfs    /mnt/slurmfs    nfs    defaults   0 0

$ sudo mount -a

$ Test (Share a file)
$ touch /mnt/slurmfs/compute
```

Now both the manager node and compute nodes should have access to the folder `/mnt/slurmfs`.

### Install Slurm

We need to install the slurm server on the manager node and the sclurm client on each compute node.

```
# For the manager
$ sudo apt install slurm-wlm -y
$ cd /etc/slurm-llnl
$ sudo cp /usr/share/doc/slurm-client/examples/slurm.conf.simple.gz .
$ sudo gzip -d slurm.conf.simple.gz
$ sudo mv slurm.conf.simple slurm.conf

# You can also use slurm_no_acct.conf in this GitHub repo
$ sudo vim /etc/slurm-llnl/slurm.conf

    ClusterName=proxmox
    SlurmctldHost=manager
    NodeName=compute01 NodeAddr=192.168.1.181 CPUs=1 State=UNKNOWN
    NodeName=compute02 NodeAddr=192.168.1.152 CPUs=1 State=UNKNOWN
    PartitionName=mac Nodes=compute[01-02] Default=YES MaxTime=INFINITE State=UP

# You can also use cgroup.conf in this GitHub repo
$ sudo vim /etc/slurm-llnl/cgroup.conf

    CgroupMountpoint="/sys/fs/cgroup"
    CgroupAutomount=yes
    CgroupReleaseAgentDir="/etc/slurm-llnl/cgroup"
    ConstrainCores=no
    TaskAffinity=no
    ConstrainRAMSpace=yes
    ConstrainSwapSpace=no
    ConstrainDevices=no
    AllowedRamSpace=100
    AllowedSwapSpace=0
    MaxRAMPercent=100
    MaxSwapPercent=100
    MinRAMSpace=30

$ sudo cp /etc/slurm-llnl/slurm.conf /etc/slurm-llnl/cgroup.conf /mnt/slurmfs/
$ sudo cp /etc/munge/munge.key /mnt/slurmfs/

$ sudo systemctl enable munge
$ sudo systemctl restart munge

$ sudo systemctl enable slurmctld
$ sudo systemctl restart slurmctld

# Test muge communication
$ munge -n | unmunge
```

```
# For each compute node
$ sudo apt install slurmd slurm-client -y

$ sudo cp /mnt/slurmfs/munge.key /etc/munge/munge.key
$ sudo cp /mnt/slurmfs/slurm.conf /etc/slurm-llnl/slurm.conf
$ sudo cp /mnt/slurmfs/cgroup* /etc/slurm-llnl

$ sudo systemctl enable munge
$ sudo systemctl restart munge

$ sudo systemctl enable slurmd
$ sudo systemctl restart slurmd

# Test muge communication
$ munge -n | unmunge
```

If everything works, you should see the cluster info:

```
$ sinfo -N

NODELIST   NODES    PARTITION   STATE
compute01      1     proxmox*    idle
compute02      1     proxmox*    idle
```

If you get this error, here are some useful commands to fix the problem.

```
ubuntu@compute02:~$ sinfo -N
slurm_load_partitions: Zero Bytes were transmitted or received
```

```
# For the manager

# Check if the manager is Up
$ scontrol ping

# If the manager is down, restart munge on each node since the key was changed.
$ sudo systemctl restart munge

# For the manager, check sclurmctld
$ sudo slurmctld -D -vvvvvv

# For each compute node, check slurmd
$ sudo slurmd -D -vvvvv
```

Now we can use `sbatch`, `squeue`, `sstat`, but `sacct` won't display completed job info.

To use `sacct`, we need to enable slurm accounting, which needs a MySQL database.

### Optional (Slurm Accounting)

To enable slurm accounting, we need to install the mariadb/mysql database.

```
# For the manager node
$ sudo apt-get -y install slurmdbd mariadb-server

$ sudo vim /etc/mysql/mariadb.conf.d/50-server.cnf
    bind-address            = 0.0.0.0

    innodb_buffer_pool_size=512M
    innodb_log_file_size=64M
    innodb_lock_wait_timeout=900

$ sudo systemctl enable mariadb
$ sudo systemctl restart mariadb
```

Then, we need to set up the password and database for slurm application.

```
$ sudo mysql_secure_installation
$ sudo mysql -u root -p
    > grant all on slurm_acct_db.* TO 'slurm'@'%' identified by 'my_password' with grant option;
    > create database slurm_acct_db;
    > grant all on slurm_jobcomp_db.* TO 'slurm'@'%' identified by 'my_password' with grant option;
    > create database slurm_jobcomp_db;
```

And set up the `slurmdbd` service. 

```
# You can also use slurmdbd.conf in this GitHub repo
$ sudo vim /etc/slurm-llnl/slurmdbd.conf
    AuthType=auth/munge

    DbdHost=manager
    DbdAddr=192.168.1.219
    DbdPort=6819
    DebugLevel=info

    LogFile=/var/log/slurm-llnl/slurmdbd.log
    PidFile=/var/run/slurmdbd.pid

    SlurmUser=slurm
    StorageType=accounting_storage/mysql
    StorageHost=manager
    StorageUser=slurm
    StoragePass=my_password
    StorageLoc=slurm_acct_db

$ sudo systemctl enable slurmdbd
$ sudo systemctl restart slurmdbd

# You can also use slurm_acct.conf in this GitHub repo
$ sudo vim /etc/slurm-llnl/slurm.conf
    # LOGGING AND ACCOUNTING
    AccountingStorageHost=manager
    AccountingStorageLoc=slurm_acct_db
    AccountingStorageUser=slurm
    AccountingStorageType=accounting_storage/slurmdbd
    AccountingStoragePort=6819

    JobCompType=jobcomp/mysql
    JobCompHost=manager
    JobCompUser=slurm
    JobCompPass=my_password
    JobContainerType=job_container/none
    JobAcctGatherType=jobacct_gather/linux

$ sudo cp /etc/slurm-llnl/slurm.conf /mnt/slurmfs/slurm.conf
$ sudo systemctl restart slurmctld
```

```
# For each compute node
$ sudo cp /mnt/slurmfs/slurm.conf /etc/slurm-llnl/slurm.conf
$ sudo systemctl restart slurmd
```

```
# Check if the cluster is added to the manager
$ sacctmgr list cluster
   Cluster     ControlHost  ControlPort   RPC     Share GrpJobs       GrpTRES GrpSubmit MaxJobs       MaxTRES MaxSubmit     MaxWall                  QOS   Def QOS
---------- --------------- ------------ ----- --------- ------- ------------- --------- ------- ------------- --------- ----------- -------------------- ---------
   proxmox   192.168.1.219         6817  8704         1                                                                                           normal

# If not, the cluster can be added using sacctmgr
$ sudo sacctmgr add cluster proxmox
```

If the cluster cannot be added to the manager, please make sure the IP address of each node is added to `/etc/hosts`:

```
# /etc.hosts on both the manager node and compute nodes
192.168.1.219 manager
192.168.1.181 cpmpute01
192.168.1.152 compute02
```
Other useful commands for debugging.

```
$ sacctmgr show configuration
$ sacctmgr list cluster

$ scontrol show nodes
$ scontrol show job
```

Congradulations! Now you have a HPC cluster running Slurm.

### Optional (Swap Area)

```
## Swap Area

$ sudo fallocate -l 1G /swapfile
$ sudo mkswap /swapfile
$ sudo swapon /swapfile
$ echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
$ sudo sysctl vm.swappiness=10
$ echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.conf
```
