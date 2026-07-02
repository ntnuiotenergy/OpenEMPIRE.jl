#!/bin/bash

set -euo pipefail

function usage() {
	cat <<'USAGE'
Usage:
  scripts/copy_and_run_julia_on_hpc.sh <cluster_name> [options]

Cluster config:
  <cluster_name>               Usually: Solstorm

Run options:
  --run PATH                   Run profile YAML, e.g. config/runs/2045_3sce_northsea.yaml
  --dataset NAME               Dataset to run, e.g. test or europe_v51
  --config PATH                Run config, e.g. config/run_2045_3sce.yaml
  --format FORMAT              Input format, default when --dataset is used: csv
  --solver NAME                Solver passed to the Julia runner
  --seed N                     Scenario seed
  --optimize                   Solve the model
  --no-optimize                Build/generate without solving
  --fixed-sample               Use data/<dataset>/ScenarioData/sampling_key.csv
  --no-fixed-sample            Generate a new sampling key
  --julia-cmd PATH             Julia executable on Solstorm
  --sge-hosts EXPR             SGE hostname expression
  --perf                       Enable EMPIRE_PERF=1
  --no-perf                    Disable EMPIRE_PERF
  --perf-interval SECONDS      Memory sampler interval
  --dry-run                    Print resolved run settings without copying/submitting

Examples:
  scripts/copy_and_run_julia_on_hpc.sh Solstorm \
    --run config/runs/2045_3sce_northsea.yaml

Run profiles use a flat YAML mapping with scalar values. Values in a run profile
can be overridden by explicit flags. If no run profile or run options are
provided, the script preserves the older behavior and runs the SCHEDULER_SCRIPT
string from config/cluster.json as-is.
USAGE
}

function die() {
	echo "ERROR: $*" >&2
	exit 1
}

function shell_quote() {
	printf "'%s'" "$(printf "%s" "$1" | sed "s/'/'\\\\''/g")"
}

function require_value() {
	[[ "$#" -ge 2 && -n "$2" && "$2" != --* ]] || die "$1 requires a value"
}

function resolve_path() {
	local path="$1"
	if [[ "$path" = /* ]]; then
		printf '%s\n' "$path"
	else
		printf '%s/%s\n' "$LOCAL_DIR" "$path"
	fi
}

function truthy() {
	case "$1" in
		true | 1 | yes | on)
			return 0
			;;
		*)
			return 1
			;;
	esac
}

function trim() {
	local value="$1"
	value="${value#"${value%%[![:space:]]*}"}"
	value="${value%"${value##*[![:space:]]}"}"
	printf '%s\n' "$value"
}

function unquote_yaml_scalar() {
	local value
	value="$(trim "$1")"
	if [[ "$value" == \"*\" && "$value" == *\" ]]; then
		value="${value:1:${#value}-2}"
	elif [[ "$value" == \'*\' && "$value" == *\' ]]; then
		value="${value:1:${#value}-2}"
	fi
	printf '%s\n' "$value"
}

function assign_profile_value() {
	local key="$1"
	local value="$2"
	case "$key" in
		dataset)
			PROFILE_DATASET="$value"
			;;
		config)
			PROFILE_CONFIG="$value"
			;;
		format)
			PROFILE_FORMAT="$value"
			;;
		solver)
			PROFILE_SOLVER="$value"
			;;
		seed)
			PROFILE_SEED="$value"
			;;
		optimize)
			PROFILE_OPTIMIZE="$value"
			;;
		fixed_sample)
			PROFILE_FIXED_SAMPLE="$value"
			;;
		julia_cmd)
			PROFILE_JULIA_CMD="$value"
			;;
		sge_hosts)
			PROFILE_SGE_HOSTS="$value"
			;;
		perf)
			PROFILE_PERF_SET=true
			if truthy "$value"; then
				PROFILE_PERF="1"
			else
				PROFILE_PERF=""
			fi
			;;
		perf_interval)
			PROFILE_PERF_INTERVAL="$value"
			;;
		*)
			die "Unsupported run profile key: $key"
			;;
	esac
}

function load_run_profile() {
	local profile_path="$1"
	local line
	local key
	local value

	while IFS= read -r line || [[ -n "$line" ]]; do
		line="$(trim "${line%%#*}")"
		[[ -z "$line" ]] && continue
		if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*:[[:space:]]*(.*)$ ]]; then
			key="${BASH_REMATCH[1]}"
			value="$(unquote_yaml_scalar "${BASH_REMATCH[2]}")"
			assign_profile_value "$key" "$value"
		else
			die "Run profile supports only flat 'key: value' entries: $line"
		fi
	done < "$profile_path"
}

if [[ "$#" -gt 0 && ( "$1" == "-h" || "$1" == "--help" ) ]]; then
	usage
	exit 0
fi

if [ "$#" -lt 1 ]; then
	usage
	exit 1
fi

CLUSTER="$1"
shift

RUN_PROFILE=""
RUN_DATASET=""
RUN_CONFIG=""
RUN_FORMAT=""
CLI_SOLVER=""
CLI_SEED=""
CLI_OPTIMIZE=""
CLI_FIXED_SAMPLE=""
CLI_JULIA_CMD=""
CLI_SGE_HOSTS=""
CLI_PERF=""
CLI_PERF_SET=false
CLI_PERF_INTERVAL=""
DRY_RUN=false

while [ "$#" -gt 0 ]; do
	case "$1" in
		--run)
			require_value "$@"
			RUN_PROFILE="${2:-}"
			shift 2
			;;
		--dataset)
			require_value "$@"
			RUN_DATASET="${2:-}"
			shift 2
			;;
		--config)
			require_value "$@"
			RUN_CONFIG="${2:-}"
			shift 2
			;;
		--format)
			require_value "$@"
			RUN_FORMAT="${2:-}"
			shift 2
			;;
		--solver)
			require_value "$@"
			CLI_SOLVER="${2:-}"
			shift 2
			;;
		--seed)
			require_value "$@"
			CLI_SEED="${2:-}"
			shift 2
			;;
		--optimize)
			CLI_OPTIMIZE="true"
			shift
			;;
		--no-optimize)
			CLI_OPTIMIZE="false"
			shift
			;;
		--fixed-sample)
			CLI_FIXED_SAMPLE="true"
			shift
			;;
		--no-fixed-sample)
			CLI_FIXED_SAMPLE="false"
			shift
			;;
		--julia-cmd)
			require_value "$@"
			CLI_JULIA_CMD="${2:-}"
			shift 2
			;;
		--sge-hosts)
			require_value "$@"
			CLI_SGE_HOSTS="${2:-}"
			shift 2
			;;
		--perf)
			CLI_PERF="1"
			CLI_PERF_SET=true
			shift
			;;
		--no-perf)
			CLI_PERF=""
			CLI_PERF_SET=true
			shift
			;;
		--perf-interval)
			require_value "$@"
			CLI_PERF_INTERVAL="${2:-}"
			shift 2
			;;
		--dry-run)
			DRY_RUN=true
			shift
			;;
		-h | --help)
			usage
			exit 0
			;;
		*)
			die "Unsupported argument: $1"
			;;
	esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="$LOCAL_DIR/config/cluster.json"
SAMPLE_CONFIG_FILE="$LOCAL_DIR/config/cluster.sample.json"

PROFILE_DATASET=""
PROFILE_CONFIG=""
PROFILE_FORMAT=""
PROFILE_SOLVER=""
PROFILE_SEED=""
PROFILE_OPTIMIZE=""
PROFILE_FIXED_SAMPLE=""
PROFILE_JULIA_CMD=""
PROFILE_SGE_HOSTS=""
PROFILE_PERF=""
PROFILE_PERF_SET=false
PROFILE_PERF_INTERVAL=""

if [[ -n "$RUN_PROFILE" ]]; then
	RUN_PROFILE_PATH="$(resolve_path "$RUN_PROFILE")"
	[[ -f "$RUN_PROFILE_PATH" ]] || die "Run profile not found: $RUN_PROFILE_PATH"
	load_run_profile "$RUN_PROFILE_PATH"
fi

RUN_DATASET=${RUN_DATASET:-$PROFILE_DATASET}
RUN_CONFIG=${RUN_CONFIG:-$PROFILE_CONFIG}
RUN_FORMAT=${RUN_FORMAT:-$PROFILE_FORMAT}
CLI_SOLVER=${CLI_SOLVER:-$PROFILE_SOLVER}
CLI_SEED=${CLI_SEED:-$PROFILE_SEED}
CLI_OPTIMIZE=${CLI_OPTIMIZE:-$PROFILE_OPTIMIZE}
CLI_FIXED_SAMPLE=${CLI_FIXED_SAMPLE:-$PROFILE_FIXED_SAMPLE}
CLI_JULIA_CMD=${CLI_JULIA_CMD:-$PROFILE_JULIA_CMD}
CLI_SGE_HOSTS=${CLI_SGE_HOSTS:-$PROFILE_SGE_HOSTS}
if [[ "$CLI_PERF_SET" == false && "$PROFILE_PERF_SET" == true ]]; then
	CLI_PERF="$PROFILE_PERF"
	CLI_PERF_SET=true
fi
CLI_PERF_INTERVAL=${CLI_PERF_INTERVAL:-$PROFILE_PERF_INTERVAL}

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
JULIA_SOLVER=${CLI_SOLVER:-${JULIA_SOLVER:-$(jq -r ".$CLUSTER.JULIA_SOLVER // \"HiGHS\"" "$CONFIG_FILE")}}
JULIA_SEED=${CLI_SEED:-${JULIA_SEED:-$(jq -r ".$CLUSTER.JULIA_SEED // \"1\"" "$CONFIG_FILE")}}
JULIA_OPTIMIZE=${CLI_OPTIMIZE:-${JULIA_OPTIMIZE:-$(jq -r ".$CLUSTER.JULIA_OPTIMIZE // \"true\"" "$CONFIG_FILE")}}
JULIA_FIXED_SAMPLE=${CLI_FIXED_SAMPLE:-${JULIA_FIXED_SAMPLE:-$(jq -r ".$CLUSTER.JULIA_FIXED_SAMPLE // \"false\"" "$CONFIG_FILE")}}
JULIA_CMD=${CLI_JULIA_CMD:-${JULIA_CMD:-$(jq -r ".$CLUSTER.JULIA_CMD // \"julia\"" "$CONFIG_FILE")}}
JULIA_SGE_HOSTS=${CLI_SGE_HOSTS:-${JULIA_SGE_HOSTS:-$(jq -r ".$CLUSTER.JULIA_SGE_HOSTS // \"\"" "$CONFIG_FILE")}}
# Performance/RAM instrumentation: local env overrides cluster.json, default off.
if [[ "$CLI_PERF_SET" == true ]]; then
	EMPIRE_PERF="$CLI_PERF"
else
	EMPIRE_PERF=${EMPIRE_PERF:-$(jq -r ".$CLUSTER.EMPIRE_PERF // \"\"" "$CONFIG_FILE")}
fi
EMPIRE_PERF_INTERVAL=${CLI_PERF_INTERVAL:-${EMPIRE_PERF_INTERVAL:-$(jq -r ".$CLUSTER.EMPIRE_PERF_INTERVAL // \"\"" "$CONFIG_FILE")}}

if [[ -z "$REMOTE_USER" || -z "$REMOTE_SERVER" || -z "$REMOTE_DIR" || -z "$SCHEDULER_SCRIPT" ||
	"$REMOTE_USER" == "null" || "$REMOTE_SERVER" == "null" || "$REMOTE_DIR" == "null" || "$SCHEDULER_SCRIPT" == "null" ]]; then
	echo "ERROR: Missing configuration for cluster '$CLUSTER' in $CONFIG_FILE"
	exit 1
fi

STRUCTURED_RUN=false
if [[ -n "$RUN_PROFILE" || -n "$RUN_DATASET" || -n "$RUN_CONFIG" || -n "$RUN_FORMAT" ]]; then
	STRUCTURED_RUN=true
fi

if [[ "$STRUCTURED_RUN" == true ]]; then
	[[ -n "$RUN_DATASET" ]] || die "--dataset is required when passing structured run options."
	RUN_CONFIG=${RUN_CONFIG:-config/testrun.yaml}
	RUN_FORMAT=${RUN_FORMAT:-csv}
	if [[ "$SCHEDULER_SCRIPT" =~ [[:space:]] ]]; then
		die "Structured run options require SCHEDULER_SCRIPT to be only the scheduler entrypoint, e.g. ./scripts/run_empire_julia_basic_sge.sh"
	fi
	SCHEDULER_COMMAND="$SCHEDULER_SCRIPT $(shell_quote "$RUN_DATASET") $(shell_quote "$RUN_CONFIG") $(shell_quote "$RUN_FORMAT")"
	[[ -d "$LOCAL_DIR/data/$RUN_DATASET" ]] || die "Dataset not found: $LOCAL_DIR/data/$RUN_DATASET"
	[[ -f "$LOCAL_DIR/$RUN_CONFIG" ]] || die "Run config not found: $LOCAL_DIR/$RUN_CONFIG"
	FIXED_SAMPLE_KEY_MISSING=false
	if [[ "$JULIA_FIXED_SAMPLE" == "true" || "$JULIA_FIXED_SAMPLE" == "1" || "$JULIA_FIXED_SAMPLE" == "yes" ]]; then
		if [[ ! -f "$LOCAL_DIR/data/$RUN_DATASET/ScenarioData/sampling_key.csv" ]]; then
			if [[ "$DRY_RUN" == true ]]; then
				FIXED_SAMPLE_KEY_MISSING=true
			else
				die "--fixed-sample requires $LOCAL_DIR/data/$RUN_DATASET/ScenarioData/sampling_key.csv"
			fi
		fi
	fi
else
	SCHEDULER_COMMAND="$SCHEDULER_SCRIPT"
fi

if [[ "$DRY_RUN" == true ]]; then
	echo "Dry run; not copying or submitting."
	echo "Cluster:      $CLUSTER"
	echo "Remote:       $REMOTE_USER@$REMOTE_SERVER:$REMOTE_DIR"
	if [[ "$STRUCTURED_RUN" == true ]]; then
		if [[ -n "$RUN_PROFILE" ]]; then
			echo "Run profile:  $RUN_PROFILE"
		fi
		echo "Dataset:      $RUN_DATASET"
		echo "Config:       $RUN_CONFIG"
		echo "Input format: $RUN_FORMAT"
	else
		echo "Run:          legacy SCHEDULER_SCRIPT string from cluster.json"
	fi
	echo "Solver:       $JULIA_SOLVER"
	echo "Seed:         $JULIA_SEED"
	echo "Optimize:     $JULIA_OPTIMIZE"
	echo "Fixed sample: $JULIA_FIXED_SAMPLE"
	echo "Julia cmd:    $JULIA_CMD"
	echo "SGE hosts:    ${JULIA_SGE_HOSTS:-default from SGE script}"
	echo "Perf:         ${EMPIRE_PERF:-off}"
	echo "Perf interval: ${EMPIRE_PERF_INTERVAL:-default}"
	echo "Scheduler:    $SCHEDULER_COMMAND"
	if [[ "${FIXED_SAMPLE_KEY_MISSING:-false}" == true ]]; then
		echo "WARNING: fixed-sample key is missing: $LOCAL_DIR/data/$RUN_DATASET/ScenarioData/sampling_key.csv"
	fi
	exit 0
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
	if [[ "$STRUCTURED_RUN" == true ]]; then
		if [[ -n "$RUN_PROFILE" ]]; then
			echo "Run profile:  $RUN_PROFILE"
		fi
		echo "Dataset:      $RUN_DATASET"
		echo "Config:       $RUN_CONFIG"
		echo "Input format: $RUN_FORMAT"
	fi
	echo "Solver:       $JULIA_SOLVER"
	echo "Seed:         $JULIA_SEED"
	echo "Optimize:     $JULIA_OPTIMIZE"
	echo "Fixed sample: $JULIA_FIXED_SAMPLE"
	echo "Perf:         ${EMPIRE_PERF:-off}"
	echo "Scheduler:    $SCHEDULER_COMMAND"
	ssh "$REMOTE_USER@$REMOTE_SERVER" \
		"cd $REMOTE_DIR && JULIA_SOLVER=$(shell_quote "$JULIA_SOLVER") JULIA_SEED=$(shell_quote "$JULIA_SEED") JULIA_OPTIMIZE=$(shell_quote "$JULIA_OPTIMIZE") JULIA_FIXED_SAMPLE=$(shell_quote "$JULIA_FIXED_SAMPLE") JULIA_CMD=$(shell_quote "$JULIA_CMD") JULIA_SGE_HOSTS=$(shell_quote "$JULIA_SGE_HOSTS") EMPIRE_PERF=$(shell_quote "$EMPIRE_PERF") EMPIRE_PERF_INTERVAL=$(shell_quote "$EMPIRE_PERF_INTERVAL") sh $SCHEDULER_COMMAND"
else
	echo "Files copied. No scheduler command is defined for cluster '$CLUSTER'."
fi
