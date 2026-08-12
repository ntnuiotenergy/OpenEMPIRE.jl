#!/bin/bash
#$ -S /bin/bash
#$ -cwd
#$ -V
#$ -o logs/julia_industry_full_$JOB_ID.out
#$ -e logs/julia_industry_full_$JOB_ID.err

# Submit the certified 2055 / 5-scenario / 168-hour Industry parity run.
# Industry runs use only Solstorm's 503 GiB compute-4 nodes, leaving the
# compute-6 nodes to the already-running Hydrogen pair.

DATASET=${DATASET:-full_model_int}
CONFIG_FILE=${CONFIG_FILE:-config/run_int_full_industry.yaml}
INPUT_FORMAT=${INPUT_FORMAT:-csv}
JULIA_CMD=${JULIA_CMD:-julia}
JULIA_SOLVER=${JULIA_SOLVER:-Gurobi}
JULIA_SEED=${JULIA_SEED:-1}
RESULTS_DIR=${RESULTS_DIR:-/storage/users/torgrif/int_full_industry_jl}
TARGET_NODE=${TARGET_NODE:-}

function valid_target_node() {
	[[ "$1" =~ ^compute-4-(5[0-3]|5[5-8])$ ]]
}

function choose_target_node() {
	if [[ -n "$TARGET_NODE" ]]; then
		valid_target_node "$TARGET_NODE" || {
			echo "ERROR: TARGET_NODE must be a 503 GiB compute-4 node (50-53 or 55-58)."
			exit 1
		}
		printf '%s\n' "$TARGET_NODE"
		return
	fi

	qhost | awk '
		$1 ~ /^compute-4-(5[0-3]|5[5-8])$/ && $7 != "-" && $8 == "503.0G" {
			printf "%s %s %s\n", $7, $9, $1
		}' | sort -k1,1g -k2,2h | head -1 | awk '{print $3}'
}

if [[ -z "$JOB_ID" ]]; then
	mkdir -p logs
	command -v qsub >/dev/null 2>&1 || {
		echo "ERROR: qsub not found. Run this on Solstorm."
		exit 1
	}

	SELECTED_NODE=$(choose_target_node)
	if [[ -z "$SELECTED_NODE" ]]; then
		echo "ERROR: no reachable 503 GiB compute-4 node found in qhost."
		exit 1
	fi

	echo "Selected 503 GiB node: $SELECTED_NODE"
	qsub -l hostname="$SELECTED_NODE" \
		-v DATASET="$DATASET",CONFIG_FILE="$CONFIG_FILE",INPUT_FORMAT="$INPUT_FORMAT",JULIA_CMD="$JULIA_CMD",JULIA_SOLVER="$JULIA_SOLVER",JULIA_SEED="$JULIA_SEED",RESULTS_DIR="$RESULTS_DIR",TARGET_NODE="$SELECTED_NODE" \
		"$0"
	echo "Submitted. Monitor logs/julia_industry_full_<JOB_ID>.out"
	exit 0
fi

echo "================================================"
echo "OpenEMPIRE.jl full Industry parity run"
echo "Job ID:       $JOB_ID"
echo "Hostname:     $(hostname)"
echo "Dataset:      $DATASET"
echo "Config:       $CONFIG_FILE"
echo "Results:      $RESULTS_DIR"
echo "Start time:   $(date)"
echo "================================================"

mkdir -p logs "$RESULTS_DIR"
module load gurobi/13.0 2>/dev/null || module load gurobi/12.0 2>/dev/null || true
module load Julia/1.9.3 2>/dev/null || module load julia/1.9.3 2>/dev/null || true
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
