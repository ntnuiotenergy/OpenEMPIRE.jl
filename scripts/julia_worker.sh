#!/bin/bash

source /etc/profile

module load rocks-openmpi
module load Julia/1.12.2
module load gurobi/13.0

exec julia "$@"