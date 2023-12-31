## HPC Applications

We can use `Module` to manage software environments on HPC (eg. CUDA, Python, Julia, etc).

### MPICH

```
$ srun --nodes=2 sudo apt install openmpi-bin openmpi-common libopenmpi3 libopenmpi-dev -y
```

### Module

```
# On the manager
$ srun --nodes=2 sudo apt install build-essential tcl-dev tcl -y

# For each compute node
$ curl -LJO https://github.com/cea-hpc/modules/releases/download/v5.3.1/modules-5.3.1.tar.gz
$ tar xfz modules-5.3.1.tar.gz
$ cd modules-5.3.1
$ ./configure
$ make
$ sudo make install
$ sudo ln -s /usr/local/Modules/init/profile.sh /etc/profile.d/modules.sh
$ sudo ln -s /usr/local/Modules/init/profile.csh /etc/profile.d/modules.csh
```

THE END !
