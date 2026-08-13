#!/bin/bash
#$ -S /bin/bash
#$ -cwd
#$ -V

# Submit exactly two full-scale, build-only Industry algebra fingerprint jobs.

set -euo pipefail

SIDE=${SIDE:-}

function snapshot_commit() {
	if git rev-parse HEAD >/dev/null 2>&1; then
		git rev-parse HEAD
	elif [[ -f SNAPSHOT_COMMIT ]]; then
		cat SNAPSHOT_COMMIT
	else
		echo "ERROR: cannot determine staged snapshot commit." >&2
		return 1
	fi
}

AUDIT_COMMIT=${AUDIT_COMMIT:-$(snapshot_commit)}
AUDIT_DIR=${AUDIT_DIR:-/storage/users/torgrif/industry-algebra-audit-${AUDIT_COMMIT}-$(date +%Y%m%d)}
LOG_DIR=${LOG_DIR:-$AUDIT_DIR/logs}
CONFIG_FILE=${CONFIG_FILE:-config/run_int_full_industry.yaml}
DATA_DIR=${DATA_DIR:-data/full_model_int}
PYTHON=${PYTHON:-$HOME/.conda/envs/empire_env/bin/python}
INTERNAL_REPO=${INTERNAL_REPO:-/storage/users/torgrif/InternalEMPIRE-industry-full-20260812}
INTERNAL_RUNNER=${INTERNAL_RUNNER:-run_EMPIRE_int_full_gas.py}
JULIA_NODE=${JULIA_NODE:-}
INTERNAL_NODE=${INTERNAL_NODE:-}

function valid_target_node() {
	[[ "$1" =~ ^compute-6-(2[4-9]|[34][0-9])$ ]]
}

function available_nodes() {
	qhost | awk '
		$1 ~ /^compute-6-(2[4-9]|[34][0-9])$/ && $8 ~ /^[0-9.]+G$/ {
			memory = $8
			sub(/G$/, "", memory)
			if (memory + 0 >= 350) printf "%s %s\n", $7, $1
		}' | sort -g | awk '{print $2}'
}

function verify_memory() {
	local node=$1
	local memory
	memory=$(qhost -h "$node" | awk '$1 == "'"$node"'" {print $8}')
	[[ "$memory" =~ ^([0-9.]+)G$ ]] || {
		echo "ERROR: cannot verify memory for $node (reported '$memory')."
		exit 1
	}
	awk 'BEGIN {exit !('"${BASH_REMATCH[1]}"' >= 350)}' || {
		echo "ERROR: $node has only $memory; require at least 350G."
		exit 1
	}
	echo "$node memory=$memory"
}

if [[ -z "${JOB_ID:-}" ]]; then
	[[ -z "$SIDE" ]] || {
		echo "ERROR: SIDE is reserved for submitted jobs."
		exit 1
	}
	command -v qsub >/dev/null 2>&1 || {
		echo "ERROR: qsub not found. Run this on Solstorm."
		exit 1
	}
	[[ "$(snapshot_commit)" == "$AUDIT_COMMIT" ]] || {
		echo "ERROR: AUDIT_COMMIT does not match the staged checkout."
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
		echo "ERROR: the two builds require distinct nodes."
		exit 1
	}
	verify_memory "$JULIA_NODE"
	verify_memory "$INTERNAL_NODE"
	mkdir -p "$LOG_DIR" "$AUDIT_DIR"
	{
		echo "audit_commit=$AUDIT_COMMIT"
		echo "config=$CONFIG_FILE"
		echo "data=$DATA_DIR"
		echo "internal_repo=$INTERNAL_REPO"
		echo "internal_runner=$INTERNAL_RUNNER"
		echo "julia_node=$JULIA_NODE"
		echo "internal_node=$INTERNAL_NODE"
	} >"$AUDIT_DIR/submission.txt"
	qsub -N indalg_jl -l hostname="$JULIA_NODE" -o "$LOG_DIR" -e "$LOG_DIR" \
		-v SIDE=julia,AUDIT_DIR="$AUDIT_DIR",AUDIT_COMMIT="$AUDIT_COMMIT",CONFIG_FILE="$CONFIG_FILE",DATA_DIR="$DATA_DIR" \
		"$0"
	qsub -N indalg_ie -l hostname="$INTERNAL_NODE" -o "$LOG_DIR" -e "$LOG_DIR" \
		-v SIDE=internal,AUDIT_DIR="$AUDIT_DIR",AUDIT_COMMIT="$AUDIT_COMMIT",PYTHON="$PYTHON",INTERNAL_REPO="$INTERNAL_REPO",INTERNAL_RUNNER="$INTERNAL_RUNNER" \
		"$0"
	exit 0
fi

mkdir -p "$AUDIT_DIR"
echo "side=$SIDE"
echo "job_id=$JOB_ID"
echo "host=$(hostname)"
echo "commit=$AUDIT_COMMIT"
echo "start=$(date --iso-8601=seconds)"

case "$SIDE" in
	julia)
		module load Julia/1.9.3 2>/dev/null || module load julia/1.9.3 2>/dev/null || true
		JULIA_DATA="$AUDIT_DIR/julia_data"
		[[ ! -e "$JULIA_DATA" ]] || {
			echo "ERROR: Julia audit data copy already exists: $JULIA_DATA"
			exit 1
		}
		cp -R "$DATA_DIR" "$JULIA_DATA"
		julia --project=. scripts/write_industry_algebra_fingerprint.jl \
			"$CONFIG_FILE" "$JULIA_DATA" "$AUDIT_DIR/julia.fingerprint"
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
			--industry --no-raw-solution \
			--industry-algebra-fingerprint "$AUDIT_DIR/internal.fingerprint"
		;;
	*)
		echo "ERROR: unknown SIDE: $SIDE"
		exit 1
		;;
esac

echo "end=$(date --iso-8601=seconds)"
