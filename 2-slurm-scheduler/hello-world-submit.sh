#!/bin/sh
#SBATCH --export=ALL # export all environment variables to the batch job.
#SBATCH -p mac # submit to the serial queue
#SBATCH --time=00:10:00 # Maximum wall time for the job.
#SBATCH --nodes=1 # specify number of nodes.
#SBATCH --ntasks-per-node=1 # specify number of processors per node
#SBATCH --mail-type=END # send email at job completion
#SBATCH --output=/mnt/slurmfs/hello-world.o
#SBATCH --error=/mnt/slurmfs/hello-world.e
#SBATCH --job-name=hello-world

## print start date and time
echo Job started on:
date -u

echo "hello-world"

## print node job run on
echo -n "This script is running on "
hostname

sleep 60
## print end date and time
echo Job ended on:
date -u
