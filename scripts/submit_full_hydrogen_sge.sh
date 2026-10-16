#!/bin/bash
#$ -S /bin/bash
#$ -cwd
#$ -V
#$ -o logs/julia_hydrogen_full_$JOB_ID.out
#$ -e logs/julia_hydrogen_full_$JOB_ID.err

# Submit the certified 2055 / 5-scenario / 168-hour Hydrogen/CO2 parity run.
# Run from a dedicated OpenEMPIRE.jl staging tree on Solstorm. Results are
# always written under /storage/users, never the login-node home directory.

DATASET=${DATASET:-full_model_int}
CONFIG_FILE=${CONFIG_FILE:-config/run_int_full_hydrogen.yaml}
INPUT_FORMAT=${INPUT_FORMAT:-csv}
JULIA_CMD=${JULIA_CMD:-julia}
JULIA_SOLVER=${JULIA_SOLVER:-Gurobi}
JULIA_SEED=${JULIA_SEED:-1}
RESULTS_DIR=${RESULTS_DIR:-/storage/users/torgrif/int_full_hydrogen_jl}
TARGET_NODE=${TARGET_NODE:-}

function valid_target_node() {
	[[ "$1" =~ ^compute-6-(2[4-9]|[34][0-9])$ ]]
}

function choose_target_node() {
	if [[ -n "$TARGET_NODE" ]]; then
		valid_target_node "$TARGET_NODE" || {
			echo "ERROR: TARGET_NODE must be compute-6-24 through compute-6-49."
			exit 1
		}
		printf '%s\n' "$TARGET_NODE"
		return
	fi

	qhost | awk '
		$1 ~ /^compute-6-(2[4-9]|[34][0-9])$/ && $7 != "-" {
			printf "%s %s\n", $7, $1
		}' | sort -g | head -1 | awk '{print $2}'
}

if [[ -z "$JOB_ID" ]]; then
	mkdir -p logs
	command -v qsub >/dev/null 2>&1 || {
		echo "ERROR: qsub not found. Run this on Solstorm."
		exit 1
	}

	SELECTED_NODE=$(choose_target_node)
	if [[ -z "$SELECTED_NODE" ]]; then
		echo "ERROR: no reachable compute-6-24+ node found in qhost."
		exit 1
	fi

	echo "Selected node: $SELECTED_NODE"
	qsub -l hostname="$SELECTED_NODE" \
		-v DATASET="$DATASET",CONFIG_FILE="$CONFIG_FILE",INPUT_FORMAT="$INPUT_FORMAT",JULIA_CMD="$JULIA_CMD",JULIA_SOLVER="$JULIA_SOLVER",JULIA_SEED="$JULIA_SEED",RESULTS_DIR="$RESULTS_DIR",TARGET_NODE="$SELECTED_NODE" \
		"$0"
	echo "Submitted. Monitor logs/julia_hydrogen_full_<JOB_ID>.out"
	exit 0
fi

echo "================================================"
echo "OpenEMPIRE.jl full Hydrogen/CO2 parity run"
echo "Job ID:       $JOB_ID"
echo "Hostname:     $(hostname)"
echo "Dataset:      $DATASET"
echo "Config:       $CONFIG_FILE"
echo "Results:      $RESULTS_DIR"
echo "Start time:   $(date)"
echo "================================================"

mkdir -p logs "$RESULTS_DIR"
module load gurobi/13.0 2>/dev/null || module load gurobi/12.0 2>/dev/null || true
# Solstorm's Julia modules change over time: 1.9.3 was removed, and a hard-coded
# load that ends in "|| true" fails silently, leaving the job to run with no Julia
# at all and die later on a missing package. Try the supported versions newest
# first and stop immediately if none of them load.
for _julia_version in 1.12.2 1.11.2 1.11.1 1.10.0; do
	module load "Julia/$_julia_version" 2>/dev/null && break
	module load "julia/$_julia_version" 2>/dev/null && break
done
command -v "${JULIA_CMD:-julia}" >/dev/null 2>&1 || {
	echo "ERROR: could not load a Julia module (tried 1.12.2 1.11.2 1.11.1 1.10.0)," >&2
	echo "       and ${JULIA_CMD:-julia} is not on PATH." >&2
	echo "       Available: $(module avail 2>&1 | grep -io 'julia/[0-9.]*' | tr '\n' ' ')" >&2
	exit 1
}
echo "julia=$("${JULIA_CMD:-julia}" --version)"
export JULIA_PKG_UNPACK_REGISTRY=true

"$JULIA_CMD" --version
echo "GRB_LICENSE_FILE=${GRB_LICENSE_FILE:-not set}"

if ! "$JULIA_CMD" --project=. -e 'import OpenEMPIRE, JuMP, Gurobi' >/dev/null 2>&1; then
	echo "Instantiating Julia project ($(date))..."
	"$JULIA_CMD" --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.precompile()' || exit 1
fi

"$JULIA_CMD" --project=. scripts/run_julia_empire.jl \
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
exit "$EXIT_CODE"
