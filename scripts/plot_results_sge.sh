#!/bin/bash
#$ -S /bin/bash
#$ -cwd
#$ -V
#$ -o logs/plot_results_$JOB_ID.out
#$ -e logs/plot_results_$JOB_ID.err
# Julia writes @info to stderr, so progress lands in the .err file while the .out
# shows only the banner and looks stalled. Merge the streams into the .out.
#$ -j y
#$ -l hostname="compute-6-24|compute-6-25|compute-6-26|compute-6-27|compute-6-28|compute-6-29|compute-6-30|compute-6-31|compute-6-32|compute-6-33|compute-6-34|compute-6-35|compute-6-36|compute-6-37|compute-6-38|compute-6-39|compute-6-40|compute-6-41|compute-6-42|compute-6-43|compute-6-44|compute-6-45|compute-6-46|compute-6-47|compute-6-48|compute-6-49"

# Build the result dashboard for a finished run, on a compute node.
#
# Usage:
#   sh scripts/plot_results_sge.sh <run_dir> [dataset_dir]
#
# Examples:
#   sh scripts/plot_results_sge.sh results/julia_runs/20260731_153253_europe_v51 data/europe_v51
#   sh scripts/plot_results_sge.sh results/julia_runs/20260803_122535_test
#
# Solstorm's administrators ask that all computation runs on compute nodes rather
# than the login server. Building the dashboard for a European run reads the
# operational table end to end — a few minutes of CPU and a few hundred MB of
# RAM — so it goes through the queue like any other job.
#
# This needs no solve: it reads the CSVs an earlier run already wrote.
# scripts/plot_results.jl is the same work run directly, for a local machine.
#
# Environment variables:
#   JULIA_CMD   Julia executable, default: julia

RUN_DIR=${1:-}
DATASET_DIR=${2:-}
JULIA_CMD=${JULIA_CMD:-julia}

if [ -z "$RUN_DIR" ]; then
	echo "Usage: $0 <run_dir> [dataset_dir]"
	echo "  <run_dir>      a finished run, e.g. results/julia_runs/20260731_153253_europe_v51"
	echo "  [dataset_dir]  optional, adds the input plots and transmission maps"
	exit 1
fi

if [ -z "$JOB_ID" ]; then
	if [ ! -d "$RUN_DIR" ]; then
		echo "ERROR: run directory not found: $RUN_DIR"
		exit 1
	fi

	if ! command -v qsub >/dev/null 2>&1; then
		echo "ERROR: qsub was not found. Run this on Solstorm, or run scripts/plot_results.jl directly."
		exit 1
	fi

	mkdir -p logs
	echo "Submitting dashboard build for: $RUN_DIR"
	qsub -v JULIA_CMD="$JULIA_CMD" "$0" "$RUN_DIR" "$DATASET_DIR"
	echo "Submitted. Monitor with 'qstat'; output goes to logs/plot_results_<job_id>.out"
	exit 0
fi

echo "================================================"
echo "OpenEMPIRE.jl dashboard build"
echo "================================================"
echo "Job ID:     $JOB_ID"
echo "Hostname:   $(hostname)"
echo "Run:        $RUN_DIR"
echo "Dataset:    ${DATASET_DIR:-<none, input plots and maps skipped>}"
echo "Start time: $(date)"
echo "================================================"

module load Julia 2>/dev/null || module load julia 2>/dev/null || true

if ! command -v "$JULIA_CMD" >/dev/null 2>&1; then
	echo "ERROR: Julia executable not found: $JULIA_CMD"
	echo "Try: module avail Julia"
	exit 1
fi

# An empty second argument is not the same as no second argument: plot_results.jl
# treats anything present as a dataset path.
if [ -n "$DATASET_DIR" ]; then
	$JULIA_CMD --project=. scripts/plot_results.jl "$RUN_DIR" "$DATASET_DIR"
else
	$JULIA_CMD --project=. scripts/plot_results.jl "$RUN_DIR"
fi

EXIT_CODE=$?

echo "================================================"
echo "Dashboard build completed"
echo "Exit code: $EXIT_CODE"
echo "End time:  $(date)"
echo "================================================"

exit $EXIT_CODE
