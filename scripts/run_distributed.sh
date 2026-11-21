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
export BENDERS_IMPLEMENTATION

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

RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)_SGE${SGE_JOB_ID:-$$}"
if [[ -n "${OPENEMPIRE_LIVE_LOG_BASE:-}" ]]; then
    LIVE_LOG_BASE="$OPENEMPIRE_LIVE_LOG_BASE"
elif [[ -d /storage ]]; then
    LIVE_LOG_BASE="/storage/OpenEMPIRE/benders_live"
else
    LIVE_LOG_BASE="$PWD/benders_live"
fi
export OPENEMPIRE_LIVE_LOG_DIR="$LIVE_LOG_BASE/$RUN_ID"
mkdir -p "$OPENEMPIRE_LIVE_LOG_DIR/gurobi/master" \
         "$OPENEMPIRE_LIVE_LOG_DIR/gurobi/sp"

MAIN_LOG="$OPENEMPIRE_LIVE_LOG_DIR/main.log"
touch "$MAIN_LOG"

cat > "$OPENEMPIRE_LIVE_LOG_DIR/status.txt" <<EOF
RUNNING
run_id=$RUN_ID
implementation=$BENDERS_IMPLEMENTATION
EOF

echo "Live logs: $OPENEMPIRE_LIVE_LOG_DIR"
echo "Main log:  $MAIN_LOG"

cleanup_live_status() {
    exit_code=$?
    if [[ $exit_code -ne 0 && -f "$OPENEMPIRE_LIVE_LOG_DIR/status.txt" ]]; then
        cat > "$OPENEMPIRE_LIVE_LOG_DIR/status.txt" <<EOF
ABORTED
run_id=$RUN_ID
implementation=$BENDERS_IMPLEMENTATION
exit_code=$exit_code
EOF
    fi
}
trap cleanup_live_status EXIT

julia --project=. "$RUN_SCRIPT" "$@" 2>&1 | tee -a "$MAIN_LOG"
