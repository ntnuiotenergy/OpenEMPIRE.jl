#!/bin/bash
#$ -S /bin/bash
#$ -cwd
#$ -V
#$ -o logs/julia_full_$JOB_ID.out
#$ -e logs/julia_full_$JOB_ID.err

# Run-infrastructure script, deliberately NOT tracked by git: it exists to launch
# the 2030 / 2-scenario full_model_int comparison against InternalEMPIRE and is
# not part of any delivery branch.
#
# Differences from scripts/run_empire_julia_basic_sge.sh, which it otherwise
# mirrors:
#   - targets compute-6-24 and up (the fastest nodes) instead of compute-4-5x
#   - picks the node by qhost load average, not by qstat job count. Most Solstorm
#     load is invisible to qstat because the other sanctioned workflow is manual
#     (screen + ssh compute-x-y), and a node that is *down* reports zero jobs.
#   - writes results to /storage/users, per the acceptable-use policy: /home is
#     "not for storing large data-files or similar".
#
# Usage (from the repo root on Solstorm):  sh scripts/submit_int_2030_sge.sh

DATASET=full_model_int
CONFIG_FILE=config/run_int_full_offshore.yaml
INPUT_FORMAT=csv
JULIA_CMD=${JULIA_CMD:-julia}
JULIA_SOLVER=${JULIA_SOLVER:-Gurobi}
JULIA_SEED=${JULIA_SEED:-1}
RESULTS_DIR=${RESULTS_DIR:-/storage/users/torgrif/int_full_offshore_jl}

if [ -z "$JOB_ID" ]; then
	mkdir -p logs

	if ! command -v qsub >/dev/null 2>&1; then
		echo "ERROR: qsub not found. Run this on Solstorm."
		exit 1
	fi

	# Lowest 1-minute load average among compute-6-24..6-49 that is actually up.
	# qhost prints '-' for LOAD on unreachable nodes, so those are skipped.
	BEST_NODE=$(qhost | awk '
		$1 ~ /^compute-6-(2[4-9]|[34][0-9])$/ && $7 != "-" {
			printf "%s %s\n", $7, $1
		}' | sort -g | head -1 | awk '{print $2}')

	if [ -z "$BEST_NODE" ]; then
		echo "ERROR: no reachable compute-6-24+ node found in qhost."
		exit 1
	fi

	echo "Node load (compute-6-24 and up, lowest first):"
	qhost | awk '$1 ~ /^compute-6-(2[4-9]|[34][0-9])$/ && $7 != "-" {printf "  %-16s load %8s  mem %s/%s\n", $1, $7, $9, $8}' | sort -k3 -g | head -6
	echo "Selected node: ${BEST_NODE}"

	qsub -l hostname=${BEST_NODE} \
		-v JULIA_CMD="$JULIA_CMD",JULIA_SOLVER="$JULIA_SOLVER",JULIA_SEED="$JULIA_SEED",RESULTS_DIR="$RESULTS_DIR" \
		"$0"
	echo "Submitted. Monitor with qstat and logs/julia_full_<JOB_ID>.out"
	exit 0
fi

echo "================================================"
echo "OpenEMPIRE.jl - full_model_int to 2030, 2 scenarios, all modules"
echo "Job ID:       $JOB_ID"
echo "Hostname:     $(hostname)"
echo "Config:       $CONFIG_FILE"
echo "Results:      $RESULTS_DIR"
echo "Start time:   $(date)"
echo "================================================"

mkdir -p logs "$RESULTS_DIR"

# Julia 1.12.2 is unusable on these nodes (its bundled 7z fails), so 1.9.3 first.
module load gurobi/13.0 2>/dev/null || module load gurobi/12.0 2>/dev/null || true
module load Julia/1.9.3 2>/dev/null || module load julia/1.9.3 2>/dev/null || true

$JULIA_CMD --version
echo "GRB_LICENSE_FILE=${GRB_LICENSE_FILE:-not set}"

if ! $JULIA_CMD --project=. -e 'import OpenEMPIRE, JuMP, Gurobi' >/dev/null 2>&1; then
	echo "Instantiating Julia project ($(date))..."
	$JULIA_CMD --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.precompile()' || exit 1
	echo "Instantiate finished ($(date))"
fi

$JULIA_CMD --project=. scripts/run_julia_empire.jl \
	--dataset="$DATASET" \
	--config="$CONFIG_FILE" \
	--format="$INPUT_FORMAT" \
	--solver="$JULIA_SOLVER" \
	--seed="$JULIA_SEED" \
	--fixed-sample \
	--results="$RESULTS_DIR"

EXIT_CODE=$?
echo "================================================"
echo "Run completed. Exit code: $EXIT_CODE"
echo "End time: $(date)"
echo "================================================"
exit $EXIT_CODE
