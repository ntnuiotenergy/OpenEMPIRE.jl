#!/bin/bash
#$ -S /bin/bash
#$ -cwd
#$ -V
#$ -o logs/internal_industry_full_$JOB_ID.out
#$ -e logs/internal_industry_full_$JOB_ID.err

# Submit the matched InternalEMPIRE Industry run through the read-only wrapper.
# Industry runs use only Solstorm's 503 GiB compute-4 nodes.

PYTHON=${PYTHON:-$HOME/.conda/envs/empire_env/bin/python}
INTERNAL_REPO=${INTERNAL_REPO:-/storage/users/torgrif/InternalEMPIRE-industry-parity}
INTERNAL_RUNNER=${INTERNAL_RUNNER:-run_EMPIRE_int_full_gas.py}
OUTPUT_DIR=${OUTPUT_DIR:-/storage/users/torgrif/int_full_industry_ie}
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
		-v PYTHON="$PYTHON",INTERNAL_REPO="$INTERNAL_REPO",INTERNAL_RUNNER="$INTERNAL_RUNNER",OUTPUT_DIR="$OUTPUT_DIR",TARGET_NODE="$SELECTED_NODE" \
		"$0"
	echo "Submitted. Monitor logs/internal_industry_full_<JOB_ID>.out"
	exit 0
fi

echo "================================================"
echo "InternalEMPIRE full Industry parity run"
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
	--no-raw-solution \
	--industry

EXIT_CODE=$?
echo "================================================"
echo "Run completed. Exit code: $EXIT_CODE"
echo "End time: $(date)"
echo "================================================"
exit "$EXIT_CODE"
