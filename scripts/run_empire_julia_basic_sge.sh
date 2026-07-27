#!/bin/bash
#$ -S /bin/bash
#$ -cwd
#$ -V
#$ -o logs/julia_empire_$JOB_ID.out
#$ -e logs/julia_empire_$JOB_ID.err
#$ -l hostname="compute-6-24|compute-6-25|compute-6-26|compute-6-27|compute-6-28|compute-6-29|compute-6-30|compute-6-31|compute-6-32|compute-6-33|compute-6-34|compute-6-35|compute-6-36|compute-6-37|compute-6-38|compute-6-39|compute-6-40|compute-6-41|compute-6-42|compute-6-43|compute-6-44|compute-6-45|compute-6-46|compute-6-47|compute-6-48|compute-6-49"

# Basic SGE script for running OpenEMPIRE.jl on Solstorm.
#
# Usage:
#   sh scripts/run_empire_julia_basic_sge.sh <dataset> [config_file] [input_format]
#   qsub scripts/run_empire_julia_basic_sge.sh <dataset> [config_file] [input_format]
#
# Examples:
#   sh scripts/run_empire_julia_basic_sge.sh test
#   sh scripts/run_empire_julia_basic_sge.sh europe_v51 config/testrun.yaml csv
#
# Environment variables:
#   JULIA_CMD       Julia executable, default: julia
#   JULIA_SOLVER    Solver name passed to scripts/run_julia_empire.jl, default: HiGHS.
#                   Supported values: HiGHS, Gurobi, none
#   JULIA_SEED      Scenario RNG seed, default: 1
#   JULIA_OPTIMIZE  true/false, default: true
#   JULIA_FIXED_SAMPLE  true/false, default: false. If true, pass
#                       --fixed-sample and require ScenarioData/sampling_key.csv.
#   JULIA_SGE_HOSTS Host expression for SGE, default:
#                   compute-6-24|compute-6-25|compute-6-26|compute-6-27|compute-6-28|compute-6-29|compute-6-30|compute-6-31|compute-6-32|compute-6-33|compute-6-34|compute-6-35|compute-6-36|compute-6-37|compute-6-38|compute-6-39|compute-6-40|compute-6-41|compute-6-42|compute-6-43|compute-6-44|compute-6-45|compute-6-46|compute-6-47|compute-6-48|compute-6-49

DATASET=${1:-test}
CONFIG_FILE=${2:-config/testrun.yaml}
INPUT_FORMAT=${3:-csv}
JULIA_CMD=${JULIA_CMD:-julia}
JULIA_SOLVER=${JULIA_SOLVER:-HiGHS}
JULIA_SEED=${JULIA_SEED:-1}
JULIA_OPTIMIZE=${JULIA_OPTIMIZE:-true}
JULIA_FIXED_SAMPLE=${JULIA_FIXED_SAMPLE:-false}
JULIA_SGE_HOSTS=${JULIA_SGE_HOSTS:-compute-6-24|compute-6-25|compute-6-26|compute-6-27|compute-6-28|compute-6-29|compute-6-30|compute-6-31|compute-6-32|compute-6-33|compute-6-34|compute-6-35|compute-6-36|compute-6-37|compute-6-38|compute-6-39|compute-6-40|compute-6-41|compute-6-42|compute-6-43|compute-6-44|compute-6-45|compute-6-46|compute-6-47|compute-6-48|compute-6-49}

function split_sge_hosts() {
	local host_expr="$1"
	host_expr="${host_expr//\"/}"
	IFS='|' read -ra SGE_HOST_CANDIDATES <<< "$host_expr"
}

function jobs_on_node() {
	local node="$1"
	if ! command -v qstat >/dev/null 2>&1; then
		echo 0
		return
	fi
	qstat -u "*" 2>/dev/null | awk -v node="$node" 'index($0, node) > 0 { count++ } END { print count + 0 }'
}

function sge_queue_state() {
	local node="$1"
	local queue_line
	queue_line="$(qstat -f -q "*@${node}.local" 2>/dev/null | awk '/^[[:alnum:]_.-]+@/ { print; exit }')"
	if [[ -z "$queue_line" ]]; then
		queue_line="$(qstat -f -q "*@${node}" 2>/dev/null | awk '/^[[:alnum:]_.-]+@/ { print; exit }')"
	fi
	if [[ -z "$queue_line" ]]; then
		printf 'missing\n'
		return
	fi
	awk '{ if (NF >= 6) print $6; else print "ok" }' <<< "$queue_line"
}

function sge_host_is_usable() {
	local state="$1"
	[[ "$state" == "ok" ]] && return 0
	[[ "$state" == *a* || "$state" == *u* || "$state" == *d* || "$state" == *E* || "$state" == *s* ]] && return 1
	return 0
}

function choose_sge_host() {
	local host_expr="$1"
	local best_node=""
	local best_jobs=999999
	local node jobs state

	split_sge_hosts "$host_expr"
	echo "Checking high-memory node usage..." >&2
	for node in "${SGE_HOST_CANDIDATES[@]}"; do
		[[ -n "$node" ]] || continue
		state="$(sge_queue_state "$node")"
		if ! sge_host_is_usable "$state"; then
			echo "  ${node}: skipped, queue state=${state}" >&2
			continue
		fi
		jobs="$(jobs_on_node "$node")"
		echo "  ${node}: ${jobs} visible running jobs" >&2
		if [[ "$jobs" -lt "$best_jobs" ]]; then
			best_jobs="$jobs"
			best_node="$node"
		fi
	done

	[[ -n "$best_node" ]] || return 1
	if [[ "$best_jobs" -eq 0 ]]; then
		echo "Selected free node: $best_node" >&2
	else
		echo "No fully free node found; selected least busy node: $best_node (${best_jobs} visible running jobs)" >&2
	fi
	printf '%s\n' "$best_node"
}

function submit_with_node_selection() {
	local selected_host
	selected_host="$(choose_sge_host "$JULIA_SGE_HOSTS")" || {
		echo "ERROR: No suitable node found from JULIA_SGE_HOSTS=$JULIA_SGE_HOSTS"
		exit 1
	}

	echo "Submitting to selected SGE host: ${selected_host}"
	qsub \
		-l hostname="$selected_host" \
		-v JULIA_CMD="$JULIA_CMD",JULIA_SOLVER="$JULIA_SOLVER",JULIA_SEED="$JULIA_SEED",JULIA_OPTIMIZE="$JULIA_OPTIMIZE",JULIA_FIXED_SAMPLE="$JULIA_FIXED_SAMPLE",JULIA_SGE_HOSTS="$JULIA_SGE_HOSTS",EMPIRE_PERF="${EMPIRE_PERF:-}",EMPIRE_PERF_INTERVAL="${EMPIRE_PERF_INTERVAL:-}" \
		"$0" "$DATASET" "$CONFIG_FILE" "$INPUT_FORMAT"
	echo "Job submitted to ${selected_host}. Use 'qstat' to monitor status."
}

if [ -z "$JOB_ID" ]; then
	echo "Submitting OpenEMPIRE.jl job for dataset: $DATASET"
	mkdir -p logs

	if ! command -v qsub >/dev/null 2>&1; then
		echo "ERROR: qsub was not found. Run this script on Solstorm, or use scripts/copy_and_run_julia_on_hpc.sh from your local machine."
		exit 1
	fi

	if command -v flock >/dev/null 2>&1; then
		(
			flock 9
			submit_with_node_selection
		) 9>/tmp/openempire_sge_node_select.lock
	else
		submit_with_node_selection
	fi
	exit 0
fi

echo "================================================"
echo "OpenEMPIRE.jl Basic Run on Solstorm"
echo "================================================"
echo "Job ID:       $JOB_ID"
echo "Hostname:     $(hostname)"
echo "Dataset:      $DATASET"
echo "Config:       $CONFIG_FILE"
echo "Input format: $INPUT_FORMAT"
echo "Julia cmd:    $JULIA_CMD"
echo "Solver:       $JULIA_SOLVER"
echo "Seed:         $JULIA_SEED"
echo "Optimize:     $JULIA_OPTIMIZE"
echo "Fixed sample: $JULIA_FIXED_SAMPLE"
echo "Start time:   $(date)"
echo "================================================"

mkdir -p logs

echo "Loading optional Solstorm modules..."
module load gurobi/13.0 2>/dev/null || module load gurobi/12.0 2>/dev/null || true
module load Julia/1.9.3 2>/dev/null || module load julia/1.9.3 2>/dev/null || module load Julia/1.10.0 2>/dev/null || module load julia/1.10.0 2>/dev/null || module load Julia/1.11.2 2>/dev/null || module load julia/1.11.2 2>/dev/null || module load Julia 2>/dev/null || module load julia 2>/dev/null || true
export JULIA_PKG_UNPACK_REGISTRY=true

if ! command -v "$JULIA_CMD" >/dev/null 2>&1; then
	echo "ERROR: Julia executable not found: $JULIA_CMD"
	echo "Try:"
	echo "  module avail Julia"
	echo "  module avail julia"
	echo "  JULIA_CMD=/path/to/julia sh scripts/run_empire_julia_basic_sge.sh test"
	exit 1
fi

echo "Julia version:"
$JULIA_CMD --version

if [[ "$JULIA_SOLVER" == "Gurobi" ]]; then
	echo "Checking Gurobi availability..."
	if command -v gurobi_cl >/dev/null 2>&1; then
		gurobi_cl --version || true
	else
		echo "gurobi_cl not found in PATH. Gurobi.jl may still use its artifact, but Solstorm license discovery may depend on the gurobi module."
	fi
	echo "GRB_LICENSE_FILE=${GRB_LICENSE_FILE:-not set}"
fi

function check_julia_project() {
	if [[ "$JULIA_SOLVER" == "Gurobi" ]]; then
		$JULIA_CMD --project=. -e 'import OpenEMPIRE; import JuMP; import HiGHS; import Gurobi'
	else
		$JULIA_CMD --project=. -e 'import OpenEMPIRE; import JuMP; import HiGHS'
	fi
}

function instantiate_julia_project() {
	$JULIA_CMD --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.precompile()'
}

echo "Checking Julia project dependencies..."
if ! check_julia_project >/dev/null 2>&1; then
	echo "Dependencies are not ready; instantiating Julia project..."
	echo "Dependency setup start time: $(date)"
	echo "This can take several minutes on a fresh Solstorm environment."
	if ! instantiate_julia_project; then
		echo "Julia project instantiation failed with:"
		$JULIA_CMD --version || true
		if [[ "$JULIA_CMD" == "julia" ]]; then
			echo "Trying fallback Julia module because the current module could not instantiate the project..."
			module unload Julia/1.9.3 2>/dev/null || true
			module unload julia/1.9.3 2>/dev/null || true
			module unload Julia/1.10.0 2>/dev/null || true
			module unload julia/1.10.0 2>/dev/null || true
			module unload Julia/1.11.2 2>/dev/null || true
			module unload julia/1.11.2 2>/dev/null || true
			module load Julia/1.10.0 2>/dev/null || module load julia/1.10.0 2>/dev/null || module load Julia/1.11.2 2>/dev/null || module load julia/1.11.2 2>/dev/null || true
			echo "Fallback Julia version:"
			$JULIA_CMD --version || true
			if ! check_julia_project >/dev/null 2>&1 && ! instantiate_julia_project; then
				echo "ERROR: Julia project instantiation failed after fallback."
				exit 1
			fi
		else
			echo "ERROR: Julia project instantiation failed."
			exit 1
		fi
	fi
	echo "Dependency setup finished: $(date)"
else
	echo "Julia project dependencies are already available."
fi

OPTIMIZE_FLAG=""
if [[ "$JULIA_OPTIMIZE" == "false" || "$JULIA_OPTIMIZE" == "0" || "$JULIA_OPTIMIZE" == "no" ]]; then
	OPTIMIZE_FLAG="--no-optimize"
fi

FIXED_SAMPLE_FLAG=""
if [[ "$JULIA_FIXED_SAMPLE" == "true" || "$JULIA_FIXED_SAMPLE" == "1" || "$JULIA_FIXED_SAMPLE" == "yes" ]]; then
	SAMPLING_KEY="data/$DATASET/ScenarioData/sampling_key.csv"
	if [[ ! -f "$SAMPLING_KEY" ]]; then
		echo "ERROR: JULIA_FIXED_SAMPLE=true requires $SAMPLING_KEY"
		exit 1
	fi
	FIXED_SAMPLE_FLAG="--fixed-sample"
fi

# Optional performance/RAM instrumentation (opt-in via EMPIRE_PERF=1). Wraps the
# run in the external RSS sampler; the in-process perf.json is gated on the same
# env var inside scripts/run_julia_empire.jl. SGE accounting is collected
# afterwards with scripts/perf/collect_qacct.sh $JOB_ID.
PERF_PREFIX=""
case "${EMPIRE_PERF:-}" in
	1 | true | yes | on)
		PERF_MEM="logs/perf_mem_${JOB_ID}.csv"
		PERF_SUM="logs/perf_mem_${JOB_ID}.json"
		PERF_INTERVAL="${EMPIRE_PERF_INTERVAL:-1.0}"
		# memwatch needs Python 3 (the node's /usr/bin/python is Python 2). Prefer an
		# explicit override, then any python3-capable interpreter, then the conda
		# empire_env interpreter that the Python port uses.
		PERF_PY="${EMPIRE_PERF_PYTHON:-}"
		if [ -z "$PERF_PY" ]; then
			for cand in python3 python; do
				if command -v "$cand" >/dev/null 2>&1 && "$cand" -c 'import sys; sys.exit(0 if sys.version_info[0] >= 3 else 1)' 2>/dev/null; then
					PERF_PY=$(command -v "$cand")
					break
				fi
			done
		fi
		if [ -z "$PERF_PY" ] && [ -x "$HOME/.conda/envs/empire_env/bin/python" ]; then
			PERF_PY="$HOME/.conda/envs/empire_env/bin/python"
		fi
		if [ -z "$PERF_PY" ]; then
			echo "WARNING: no Python 3 found for memwatch; running without the external RSS sampler."
		else
			echo "Performance sampling enabled -> $PERF_MEM (interval ${PERF_INTERVAL}s, $PERF_PY)"
			PERF_PREFIX="$PERF_PY scripts/perf/memwatch.py --interval $PERF_INTERVAL --out $PERF_MEM --summary $PERF_SUM --label julia-${DATASET} --"
		fi
		;;
esac

echo "================================================"
echo "Starting OpenEMPIRE.jl run"
echo "================================================"

$PERF_PREFIX $JULIA_CMD --project=. scripts/run_julia_empire.jl \
	--dataset="$DATASET" \
	--config="$CONFIG_FILE" \
	--format="$INPUT_FORMAT" \
	--solver="$JULIA_SOLVER" \
	--seed="$JULIA_SEED" \
	$FIXED_SAMPLE_FLAG \
	$OPTIMIZE_FLAG

EXIT_CODE=$?

if [ -n "$PERF_PREFIX" ]; then
	echo "Performance sampler summary: $PERF_SUM"
	echo "Collect SGE accounting once available with: sh scripts/perf/collect_qacct.sh $JOB_ID"
fi

echo "================================================"
echo "OpenEMPIRE.jl run completed"
echo "Exit code: $EXIT_CODE"
echo "End time: $(date)"
echo "================================================"

exit $EXIT_CODE
