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
$ sudo vim /etc/slurm-llnl/slurm.conf

    SlurmctldHost=manager
    NodeName=compute01 NodeAddr=192.168.1.181 CPUs=1 State=UNKNOWN
    NodeName=compute02 NodeAddr=192.168.1.152 CPUs=1 State=UNKNOWN
    PartitionName=mycluster Nodes=comoute[01-02] Default=YES MaxTime=INFINITE State=UP

$ sudo vim /etc/slurm-llnl/cgroup.conf

    CgroupMountpoint="/sys/fs/cgroup"
    CgroupAutomount=yes
    CgroupReleaseAgentDir="/etc/slurm-llnl/cgroup"
    AllowedDevicesFile="/etc/slurm-llnl/cgroup_allowed_devices_file.conf"
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

$ sudo vim /etc/slurm-llnl/cgroup_allowed_devices_file.conf

    /dev/null
    /dev/urandom
    /dev/zero
    /dev/sda*
    /dev/cpu/*/*
    /dev/pts/*
    /mnt/slurmfs/*

$ sudo cp /etc/slurm-llnl/slurm.conf /etc/slurm-llnl/cgroup.conf /etc/slurm-llnl/cgroup_allowed_devices_file.conf /mnt/slurmfs/
$ sudo cp /etc/munge/munge.key /mnt/slurmfs/

$ sudo systemctl enable munge
$ sudo systemctl start munge

$ sudo systemctl enable slurmctld
$ sudo systemctl start slurmctld
```

```
# For each compute node
$ sudo apt install slurmd slurm-client -y

$ sudo cp /mnt/slurmfs/munge.key /etc/munge/munge.key
$ sudo cp /mnt/slurmfs/slurm.conf /etc/slurm-llnl/slurm.conf
$ sudo cp /mnt/slurmfs/cgroup* /etc/slurm-llnl

$ sudo systemctl enable munge
$ sudo systemctl start munge

$ sudo systemctl enable slurmd
$ sudo systemctl start slurmd
```

If everything works, you should see the cluster info:

```
$ sinfo -N

NODELIST   NODES    PARTITION   STATE
compute01      1   mycluster*    idle
compute02      1   mycluster*    idle
```

Here are some useful commands for debugging if the cluster status is incorrect.

```
# For the manager

$ scontrol ping
$ sudo slurmctld -D -vvvvvv

# For each compute node
$ sudo slurmd -D -vvvvv
$ sudo slurmd -D -N $(hostname -s)
```

### Optional (Accounting)


```
# For the manager node
$ sudo apt-get -y install slurmdbd mariadb-server

$ sudo vim /etc/mysql/mariadb.conf.d/50-server.cnf
    bind-address            = 0.0.0.0

    innodb_buffer_pool_size=512M
    innodb_log_file_size=64M
    innodb_lock_wait_timeout=900

$ sudo systemctl enable mariadb
$ sudo systemctl start mariadb

$ sudo mysql_secure_installation
$ sudo mysql -u root -p
    > grant all on slurm_acct_db.* TO 'slurm'@'%' identified by 'my_password' with grant option;
    > create database slurm_acct_db;

$ sudo vim /etc/slurm-llnl/slurmdbd.conf
    ArchiveEvents=yes
    ArchiveJobs=yes
    ArchiveResvs=yes
    ArchiveSteps=no
    ArchiveSuspend=no
    ArchiveTXN=no
    ArchiveUsage=no
    #ArchiveScript=/usr/sbin/slurm.dbd.archive
    AuthInfo=/var/run/munge/munge.socket.2
    AuthType=auth/munge

    DbdHost=manager
    DebugLevel=info
    PurgeEventAfter=1month
    PurgeJobAfter=12month
    PurgeResvAfter=1month
    PurgeStepAfter=1month
    PurgeSuspendAfter=1month
    PurgeTXNAfter=12month
    PurgeUsageAfter=24month
    LogFile=/var/log/slurmdbd.log
    PidFile=/var/run/slurmdbd.pid

    StorageType=accounting_storage/mysql
    StorageHost=manager
    StoragePass=my_password
    StorageUser=slurm
    StorageLoc=slurm_acct_db

$ sudo systemctl enable slurmdbd
$ sudo systemctl start slurmdbd

$ sudo vim /etc/slurm-llnl/slurm.conf
    # LOGGING AND ACCOUNTING
    AccountingStorageHost=manager
    AccountingStorageLoc=slurm_acct_db
    AccountingStorageUser=slurm
    AccountingStorageType=accounting_storage/slurmdbd

    JobCompType=jobcomp/mysql
    JobCompHost=manager
    JobCompUser=slurm
    JobCompPass=my_password
    JobContainerType=job_container/none
    JobAcctGatherType=jobacct_gather/linux

$ sudo mysql -u root -p
    > grant all on slurm_jobcomp_db.* TO 'slurm'@'%' identified by 'my_password' with grant option;
    > create database slurm_jobcomp_db;

$ sudo cp /etc/slurm-llnl/slurm.conf /mnt/slurmfs/slurm.conf
$ sudo systemctl restart slurmctld

$ scontrol show nodes
$ scontrol show job
```


```
# For each compute node
$ sudo cp /mnt/slurmfs/slurm.conf /etc/slurm-llnl/slurm.conf
$ sudo systemctl restart slurmd
```

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
