#!/bin/bash
#$ -S /bin/bash
# Generate a sampling key on a Solstorm compute node without constructing the model.

set -euo pipefail

DATASET=${DATASET:-full_model_int}
CONFIG_FILE=${CONFIG_FILE:-config/run_int_full_gas_3sce.yaml}
JULIA_CMD=${JULIA_CMD:-julia}
JULIA_SEED=${JULIA_SEED:-2}
RESULTS_DIR=${RESULTS_DIR:-/storage/users/torgrif/int_full_gas_3sce_seed2_keygen}

module load Julia/1.9.3 2>/dev/null || module load julia/1.9.3 2>/dev/null || true

echo "Generating shared sampling key"
echo "Host:    $(hostname)"
echo "Dataset: $DATASET"
echo "Config:  $CONFIG_FILE"
echo "Seed:    $JULIA_SEED"
echo "Results: $RESULTS_DIR"

"$JULIA_CMD" --project=. scripts/run_julia_empire.jl \
	--dataset="$DATASET" \
	--config="$CONFIG_FILE" \
	--format=csv \
	--solver=none \
	--seed="$JULIA_SEED" \
	--generate-only \
	--results="$RESULTS_DIR"
