#!/bin/bash
#$ -S /bin/bash
#$ -cwd
#$ -V
#$ -o logs/julia_empire_$JOB_ID.out
#$ -e logs/julia_empire_$JOB_ID.err
#$ -l hostname="compute-4-51|compute-4-52|compute-4-53|compute-4-55|compute-4-56"

# Basic SGE script for running OpenEMPIRE.jl on Solstorm.
#
# Usage:
#   sh scripts/run_empire_julia_basic_sge.sh <dataset> [config_file] [input_format]
#   qsub scripts/run_empire_julia_basic_sge.sh <dataset> [config_file] [input_format]
#
# Examples:
#   sh scripts/run_empire_julia_basic_sge.sh test
#   sh scripts/run_empire_julia_basic_sge.sh europe_v51 data/test_excel/testrun.yaml csv
#
# Environment variables:
#   JULIA_CMD       Julia executable, default: julia
#   JULIA_SOLVER    Solver name passed to scripts/run_julia_empire.jl, default: HiGHS.
#                   Supported values: HiGHS, Gurobi, none
#   JULIA_SEED      Scenario RNG seed, default: 1
#   JULIA_OPTIMIZE  true/false, default: true
#   JULIA_FIXED_SAMPLE  true/false, default: false. If true, pass
#                       --fixed-sample and require ScenarioData/sampling_key.csv.

DATASET=${1:-test}
CONFIG_FILE=${2:-data/test_excel/testrun.yaml}
INPUT_FORMAT=${3:-csv}
JULIA_CMD=${JULIA_CMD:-julia}
JULIA_SOLVER=${JULIA_SOLVER:-HiGHS}
JULIA_SEED=${JULIA_SEED:-1}
JULIA_OPTIMIZE=${JULIA_OPTIMIZE:-true}
JULIA_FIXED_SAMPLE=${JULIA_FIXED_SAMPLE:-false}

if [ -z "$JOB_ID" ]; then
	echo "Submitting OpenEMPIRE.jl job for dataset: $DATASET"
	mkdir -p logs

	if ! command -v qsub >/dev/null 2>&1; then
		echo "ERROR: qsub was not found. Run this script on Solstorm, or use scripts/copy_and_run_julia_on_hpc.sh from your local machine."
		exit 1
	fi

	HIGH_MEM_NODES=("compute-4-51" "compute-4-52" "compute-4-53" "compute-4-55" "compute-4-56")

	echo "Checking availability of high-memory nodes..."
	BEST_NODE=""
	MIN_LOAD=999999

	for node in "${HIGH_MEM_NODES[@]}"; do
		JOBS_ON_NODE=$(qstat -u "*" 2>/dev/null | grep "${node}" | wc -l)
		if ! [[ "$JOBS_ON_NODE" =~ ^[0-9]+$ ]]; then
			JOBS_ON_NODE=0
		fi

		if [ "$JOBS_ON_NODE" -lt "$MIN_LOAD" ]; then
			MIN_LOAD=$JOBS_ON_NODE
			BEST_NODE=$node
		fi

		echo "  ${node}: ${JOBS_ON_NODE} jobs"
	done

	if [ -z "$BEST_NODE" ]; then
		echo "ERROR: No suitable node found!"
		exit 1
	fi

	echo "Selected node: ${BEST_NODE} (${MIN_LOAD} jobs)"
	qsub \
		-l hostname=${BEST_NODE} \
		-v JULIA_CMD="$JULIA_CMD",JULIA_SOLVER="$JULIA_SOLVER",JULIA_SEED="$JULIA_SEED",JULIA_OPTIMIZE="$JULIA_OPTIMIZE",JULIA_FIXED_SAMPLE="$JULIA_FIXED_SAMPLE" \
		"$0" "$DATASET" "$CONFIG_FILE" "$INPUT_FORMAT"
	echo "Job submitted to ${BEST_NODE}. Use 'qstat' to monitor status."
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

echo "================================================"
echo "Starting OpenEMPIRE.jl run"
echo "================================================"

$JULIA_CMD --project=. scripts/run_julia_empire.jl \
	--dataset="$DATASET" \
	--config="$CONFIG_FILE" \
	--format="$INPUT_FORMAT" \
	--solver="$JULIA_SOLVER" \
	--seed="$JULIA_SEED" \
	$FIXED_SAMPLE_FLAG \
	$OPTIMIZE_FLAG

EXIT_CODE=$?

echo "================================================"
echo "OpenEMPIRE.jl run completed"
echo "Exit code: $EXIT_CODE"
echo "End time: $(date)"
echo "================================================"

exit $EXIT_CODE
