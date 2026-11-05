#!/bin/bash
set -euo pipefail

# Find the SGE job belonging to the shell that launched this script
SPOOL_DIR="/opt/gridengine/default/spool/$(hostname -s)/active_jobs"
SHELL_PID="$PPID"

HOSTFILE=""

for f in "$SPOOL_DIR"/*/job_pid; do
    if [[ -r "$f" ]] && [[ "$(cat "$f")" == "$SHELL_PID" ]]; then
        HOSTFILE="${f%/job_pid}/pe_hostfile"
        break
    fi
done

if [[ -z "$HOSTFILE" || ! -r "$HOSTFILE" ]]; then
    echo "ERROR: Could not find the hostfile for the current SGE allocation."
    exit 1
fi

export SGE_PE_HOSTFILE="$HOSTFILE"

echo "Using SGE hostfile: $SGE_PE_HOSTFILE"
cat "$SGE_PE_HOSTFILE"

#exec julia --project=. scripts/run_dist_benders_scenario.jl "$@"
#exec julia --project=. scripts/run_dist_benders_inv_period.jl "$@"

# Select the distributed Benders run script
BENDERS_IMPLEMENTATION="${BENDERS_IMPLEMENTATION:-investment_period}"

case "$BENDERS_IMPLEMENTATION" in
    investment_period)
        RUN_SCRIPT="scripts/run_dist_benders_inv_period.jl"
        ;;
    scenario)
        RUN_SCRIPT="scripts/run_dist_benders_scenario.jl"
        ;;
    *)
        echo "ERROR: Unknown BENDERS_IMPLEMENTATION: $BENDERS_IMPLEMENTATION"
        echo "Expected 'investment_period' or 'scenario'."
        exit 1
        ;;
esac

echo "Using Benders implementation: $BENDERS_IMPLEMENTATION"
echo "Running script: $RUN_SCRIPT"

exec julia --project=. "$RUN_SCRIPT" "$@"
