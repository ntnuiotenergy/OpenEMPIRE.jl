#!/bin/bash
#$ -S /bin/bash
#$ -cwd
#$ -V
#$ -o logs/internal_hydrogen_full_$JOB_ID.out
#$ -e logs/internal_hydrogen_full_$JOB_ID.err

# Submit the matching InternalEMPIRE Hydrogen/CO2 run through the read-only
# wrapper. The wrapper patches runner paths and solver options in memory; it does
# not edit the staged InternalEMPIRE checkout.

PYTHON=${PYTHON:-$HOME/.conda/envs/empire_env/bin/python}
INTERNAL_REPO=${INTERNAL_REPO:-/storage/users/torgrif/InternalEMPIRE-hydrogen-parity-20260811}
INTERNAL_RUNNER=${INTERNAL_RUNNER:-run_EMPIRE_int_full_gas.py}
OUTPUT_DIR=${OUTPUT_DIR:-/storage/users/torgrif/int_full_hydrogen_ie}
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
		-v PYTHON="$PYTHON",INTERNAL_REPO="$INTERNAL_REPO",INTERNAL_RUNNER="$INTERNAL_RUNNER",OUTPUT_DIR="$OUTPUT_DIR",TARGET_NODE="$SELECTED_NODE" \
		"$0"
	echo "Submitted. Monitor logs/internal_hydrogen_full_<JOB_ID>.out"
	exit 0
fi

echo "================================================"
echo "InternalEMPIRE full Hydrogen/CO2 parity run"
echo "Job ID:       $JOB_ID"
echo "Hostname:     $(hostname)"
echo "Reference:    $INTERNAL_REPO"
echo "Runner:       $INTERNAL_RUNNER"
echo "Output:       $OUTPUT_DIR"
echo "Start time:   $(date)"
echo "================================================"

mkdir -p logs "$OUTPUT_DIR"
module load gurobi/13.0 2>/dev/null || module load gurobi/12.0 2>/dev/null || true
echo "GRB_LICENSE_FILE=${GRB_LICENSE_FILE:-not set}"

if [[ ! -x "$PYTHON" ]]; then
	echo "ERROR: Python executable not found: $PYTHON"
	exit 1
fi
if [[ ! -f "$INTERNAL_REPO/$INTERNAL_RUNNER" ]]; then
	echo "ERROR: InternalEMPIRE runner not found: $INTERNAL_REPO/$INTERNAL_RUNNER"
	exit 1
fi

"$PYTHON" -c 'import pandas, pyomo; print("pyomo", pyomo.version.version)'
"$PYTHON" -u scripts/run_internalempire_hydrogen.py \
	--internal-repo "$INTERNAL_REPO" \
	--runner "$INTERNAL_RUNNER" \
	--output-dir "$OUTPUT_DIR" \
	--no-raw-solution

EXIT_CODE=$?
echo "================================================"
echo "Run completed. Exit code: $EXIT_CODE"
echo "End time: $(date)"
echo "================================================"
exit "$EXIT_CODE"
