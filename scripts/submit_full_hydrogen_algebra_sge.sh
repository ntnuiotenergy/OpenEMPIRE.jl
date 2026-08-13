#!/bin/bash
#$ -S /bin/bash
#$ -cwd
#$ -V

# Submit matching full-scale, build-only Hydrogen/CO2 algebra fingerprints.
# The jobs build each model and stream canonical hashes; they never invoke a solver
# and never write operational result CSVs.

set -euo pipefail

SIDE=${SIDE:-}
AUDIT_DIR=${AUDIT_DIR:-/storage/users/torgrif/hydrogen_algebra_audit_20260813_c5ef8cf}
CONFIG_FILE=${CONFIG_FILE:-config/run_int_full_hydrogen.yaml}
DATA_DIR=${DATA_DIR:-data/full_model_int}
PYTHON=${PYTHON:-$HOME/.conda/envs/empire_env/bin/python}
INTERNAL_REPO=${INTERNAL_REPO:-/storage/users/torgrif/InternalEMPIRE-hydrogen-full-20260811-1352}
INTERNAL_RUNNER=${INTERNAL_RUNNER:-run_EMPIRE_int_full_gas.py}
JULIA_NODE=${JULIA_NODE:-}
INTERNAL_NODE=${INTERNAL_NODE:-}

function valid_target_node() {
	[[ "$1" =~ ^compute-6-(2[4-9]|[34][0-9])$ ]]
}

function available_nodes() {
	qhost | awk '
		$1 ~ /^compute-6-(2[4-9]|[34][0-9])$/ && $7 != "-" {
			printf "%s %s\n", $7, $1
		}' | sort -g | awk '{print $2}'
}

if [[ -z "$JOB_ID" ]]; then
	[[ -z "$SIDE" ]] || {
		echo "ERROR: SIDE is reserved for the submitted jobs."
		exit 1
	}
	command -v qsub >/dev/null 2>&1 || {
		echo "ERROR: qsub not found. Run this on Solstorm."
		exit 1
	}
	mapfile -t nodes < <(available_nodes)
	if [[ -z "$JULIA_NODE" ]]; then
		JULIA_NODE=${nodes[0]:-}
	fi
	if [[ -z "$INTERNAL_NODE" ]]; then
		for node in "${nodes[@]}"; do
			if [[ "$node" != "$JULIA_NODE" ]]; then
				INTERNAL_NODE=$node
				break
			fi
		done
	fi
	valid_target_node "$JULIA_NODE" || {
		echo "ERROR: JULIA_NODE must be compute-6-24 through compute-6-49."
		exit 1
	}
	valid_target_node "$INTERNAL_NODE" || {
		echo "ERROR: INTERNAL_NODE must be compute-6-24 through compute-6-49."
		exit 1
	}
	[[ "$JULIA_NODE" != "$INTERNAL_NODE" ]] || {
		echo "ERROR: use distinct nodes for the two memory-intensive model builds."
		exit 1
	}
	mkdir -p logs
	echo "Julia node:          $JULIA_NODE"
	echo "InternalEMPIRE node: $INTERNAL_NODE"
	qsub -N h2alg_jl -l hostname="$JULIA_NODE" -o logs -e logs \
		-v SIDE=julia,AUDIT_DIR="$AUDIT_DIR",CONFIG_FILE="$CONFIG_FILE",DATA_DIR="$DATA_DIR" \
		"$0"
	qsub -N h2alg_ie -l hostname="$INTERNAL_NODE" -o logs -e logs \
		-v SIDE=internal,AUDIT_DIR="$AUDIT_DIR",PYTHON="$PYTHON",INTERNAL_REPO="$INTERNAL_REPO",INTERNAL_RUNNER="$INTERNAL_RUNNER" \
		"$0"
	exit 0
fi

mkdir -p "$AUDIT_DIR"
echo "side=$SIDE"
echo "job_id=$JOB_ID"
echo "host=$(hostname)"
echo "start=$(date --iso-8601=seconds)"

case "$SIDE" in
	julia)
		module load Julia/1.9.3 2>/dev/null || module load julia/1.9.3 2>/dev/null || true
		julia --project=. scripts/write_hydrogen_algebra_fingerprint.jl \
			"$CONFIG_FILE" "$DATA_DIR" "$AUDIT_DIR/julia.fingerprint"
		;;
	internal)
		[[ -x "$PYTHON" ]] || {
			echo "ERROR: Python executable not found: $PYTHON"
			exit 1
		}
		[[ -f "$INTERNAL_REPO/$INTERNAL_RUNNER" ]] || {
			echo "ERROR: InternalEMPIRE runner not found: $INTERNAL_REPO/$INTERNAL_RUNNER"
			exit 1
		}
		export MPLCONFIGDIR="$AUDIT_DIR/matplotlib"
		mkdir -p "$MPLCONFIGDIR"
		"$PYTHON" -u scripts/run_internalempire_hydrogen.py \
			--internal-repo "$INTERNAL_REPO" \
			--runner "$INTERNAL_RUNNER" \
			--output-dir "$AUDIT_DIR/internal_work" \
			--no-raw-solution \
			--algebra-fingerprint "$AUDIT_DIR/internal.fingerprint"
		;;
	*)
		echo "ERROR: unknown SIDE: $SIDE"
		exit 1
		;;
esac

echo "end=$(date --iso-8601=seconds)"
