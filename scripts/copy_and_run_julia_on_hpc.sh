#!/bin/bash

if [ "$#" -ne 1 ]; then
	echo "Usage: $(basename "$0") <cluster_name>"
	echo "Cluster name should usually be: Solstorm"
	exit 1
fi

CLUSTER="$1"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_DIR="$SCRIPT_DIR/.."
CONFIG_FILE="$LOCAL_DIR/config/cluster.json"
SAMPLE_CONFIG_FILE="$LOCAL_DIR/config/cluster.sample.json"

if ! command -v jq >/dev/null 2>&1; then
	echo "ERROR: jq is required to read config/cluster.json."
	echo "Install jq locally or copy/run manually with scp and qsub."
	exit 1
fi

if [ ! -f "$CONFIG_FILE" ]; then
	mkdir -p "$(dirname "$CONFIG_FILE")"
	cp "$SAMPLE_CONFIG_FILE" "$CONFIG_FILE"
	echo "Config file not found. Created $CONFIG_FILE from the sample."
	echo "Edit it with your Solstorm username and rerun this script."
	exit 1
fi

REMOTE_USER=$(jq -r ".$CLUSTER.REMOTE_USER" "$CONFIG_FILE")
REMOTE_SERVER=$(jq -r ".$CLUSTER.REMOTE_SERVER" "$CONFIG_FILE")
REMOTE_DIR=$(jq -r ".$CLUSTER.REMOTE_DIR" "$CONFIG_FILE")
SCHEDULER_SCRIPT=$(jq -r ".$CLUSTER.SCHEDULER_SCRIPT" "$CONFIG_FILE")
JULIA_SOLVER=$(jq -r ".$CLUSTER.JULIA_SOLVER // \"HiGHS\"" "$CONFIG_FILE")
JULIA_SEED=$(jq -r ".$CLUSTER.JULIA_SEED // \"1\"" "$CONFIG_FILE")
JULIA_OPTIMIZE=$(jq -r ".$CLUSTER.JULIA_OPTIMIZE // \"true\"" "$CONFIG_FILE")
JULIA_FIXED_SAMPLE=$(jq -r ".$CLUSTER.JULIA_FIXED_SAMPLE // \"false\"" "$CONFIG_FILE")
JULIA_CMD=$(jq -r ".$CLUSTER.JULIA_CMD // \"julia\"" "$CONFIG_FILE")
JULIA_SGE_HOSTS=${JULIA_SGE_HOSTS:-$(jq -r ".$CLUSTER.JULIA_SGE_HOSTS // \"\"" "$CONFIG_FILE")}
# Performance/RAM instrumentation: local env overrides cluster.json, default off.
EMPIRE_PERF=${EMPIRE_PERF:-$(jq -r ".$CLUSTER.EMPIRE_PERF // \"\"" "$CONFIG_FILE")}
EMPIRE_PERF_INTERVAL=${EMPIRE_PERF_INTERVAL:-$(jq -r ".$CLUSTER.EMPIRE_PERF_INTERVAL // \"\"" "$CONFIG_FILE")}

if [[ "$REMOTE_USER" == "null" || "$REMOTE_SERVER" == "null" || "$REMOTE_DIR" == "null" || "$SCHEDULER_SCRIPT" == "null" ]]; then
	echo "ERROR: Missing configuration for cluster '$CLUSTER' in $CONFIG_FILE"
	exit 1
fi

cd "$LOCAL_DIR" || exit 1

TAR_FLAGS=""
if [[ "$(uname)" == "Darwin" ]]; then
	export COPYFILE_DISABLE=1
	TAR_FLAGS="--no-xattrs --no-mac-metadata --no-fflags"
fi

echo "Creating transfer archive..."
tar $TAR_FLAGS \
	--exclude='./.git' \
	--exclude='./.git/*' \
	--exclude='./.vscode' \
	--exclude='./.vscode/*' \
	--exclude='./results' \
	--exclude='./results/*' \
	--exclude='./logs' \
	--exclude='./logs/*' \
	--exclude='./Manifest.toml' \
	--exclude='*/._*' \
	--exclude='*__pycache__*' \
	-cvzf openempire_jl.tar.gz *

echo "Creating remote directory: $REMOTE_DIR"
ssh "$REMOTE_USER@$REMOTE_SERVER" "mkdir -p $REMOTE_DIR"

echo "Copying archive to $REMOTE_SERVER..."
scp openempire_jl.tar.gz "$REMOTE_USER@$REMOTE_SERVER:$REMOTE_DIR"

echo "Extracting archive on remote..."
ssh "$REMOTE_USER@$REMOTE_SERVER" <<EOF
    cd $REMOTE_DIR
    rm -f Manifest.toml
    tar --warning=no-unknown-keyword -xvzf openempire_jl.tar.gz
    rm openempire_jl.tar.gz
    chmod +x scripts/*
EOF

rm "$LOCAL_DIR/openempire_jl.tar.gz"

echo "Transfer complete."

if [[ "$CLUSTER" == "Solstorm" ]]; then
	echo "Starting SGE job on Solstorm..."
	ssh "$REMOTE_USER@$REMOTE_SERVER" \
		"cd $REMOTE_DIR && JULIA_SOLVER='$JULIA_SOLVER' JULIA_SEED='$JULIA_SEED' JULIA_OPTIMIZE='$JULIA_OPTIMIZE' JULIA_FIXED_SAMPLE='$JULIA_FIXED_SAMPLE' JULIA_CMD='$JULIA_CMD' JULIA_SGE_HOSTS='$JULIA_SGE_HOSTS' EMPIRE_PERF='$EMPIRE_PERF' EMPIRE_PERF_INTERVAL='$EMPIRE_PERF_INTERVAL' sh $SCHEDULER_SCRIPT"
else
	echo "Files copied. No scheduler command is defined for cluster '$CLUSTER'."
fi
