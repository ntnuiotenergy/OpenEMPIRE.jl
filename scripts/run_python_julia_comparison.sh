#!/usr/bin/env bash
set -euo pipefail

function usage() {
	cat <<'USAGE'
Usage:
  scripts/run_python_julia_comparison.sh --dataset DATASET --config CONFIG [options]

Prepare and optionally launch matched Julia/Python EMPIRE comparison runs.

Required:
  --dataset NAME              Dataset name present in Julia data/ and Python input_data/
  --config PATH               Config path, relative to each repo unless --python-config is set

Common options:
  --python-config PATH        Python config path when it differs from --config
  --julia-repo PATH           Julia repo root, default: this script's parent repo
  --python-repo PATH          Python CSV repo root, default: sibling ../OpenEMPIRE-csv
  --seed N                    Scenario seed for generated sampling keys, default: 1
  --solver NAME               Julia solver env value, default: Gurobi
  --cluster NAME              Cluster passed to copy scripts, default: Solstorm
  --perf                      Set EMPIRE_PERF=1 for both runtimes
  --perf-interval SECONDS     EMPIRE_PERF_INTERVAL, default: 1.0

Sampling key:
  --sampling-key PATH         Use an existing sampling_key.csv
  --generate-key              Generate a fresh key with the Julia runner first
  --allow-config-mismatch     Warn instead of failing when config checksums differ

Execution mode:
  --prepare-only              Install/validate key and write manifest; do not submit jobs
  --dry-run                   Print actions/commands without writing or submitting
  --runtime julia,python      Runtime subset to submit, default: julia,python

What it does:
  1. Ensures Julia/Python dataset and config paths exist.
  2. Uses or generates one sampling_key.csv.
  3. Installs that key into both source dataset folders for fixed-sample runs.
  4. Writes results/comparison_runs/<timestamp>_<dataset>/comparison_manifest.txt.
  5. Optionally calls each repo's existing copy_and_run_*_on_hpc.sh launcher.

The existing repo launchers still read their own config/cluster.json. Before
submitting, this script checks that each SCHEDULER_SCRIPT mentions the requested
dataset and config path, so mismatched cluster configs fail early. The Python
SCHEDULER_SCRIPT must also include USE_FIXED_SAMPLE=true, because the Python
copy launcher owns the remote scheduler command.
USAGE
}

function die() {
	echo "ERROR: $*" >&2
	exit 1
}

function info() {
	echo "[compare] $*"
}

function abs_path() {
	local path="$1"
	if [[ "$path" = /* ]]; then
		printf '%s\n' "$path"
	else
		printf '%s/%s\n' "$(pwd)" "$path"
	fi
}

function resolve_in_repo() {
	local repo="$1"
	local path="$2"
	if [[ "$path" = /* ]]; then
		printf '%s\n' "$path"
	else
		printf '%s/%s\n' "$repo" "$path"
	fi
}

function sha256_file() {
	local path="$1"
	if command -v shasum >/dev/null 2>&1; then
		shasum -a 256 "$path" | awk '{print $1}'
	elif command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$path" | awk '{print $1}'
	else
		die "Neither shasum nor sha256sum is available."
	fi
}

function contains_runtime() {
	local runtime="$1"
	[[ ",$RUNTIMES," == *",$runtime,"* ]]
}

function validate_runtimes() {
	local value="$1"
	[[ -n "$value" ]] || die "--runtime must not be empty"
	IFS=',' read -ra runtime_parts <<< "$value"
	for runtime in "${runtime_parts[@]}"; do
		case "$runtime" in
			julia | python)
				;;
			*)
				die "--runtime only supports julia, python, or julia,python: $value"
				;;
		esac
	done
}

function copy_key_if_needed() {
	local source="$1"
	local target="$2"
	if [[ "$DRY_RUN" == true ]]; then
		info "Would install sampling key: $source -> $target"
		return 0
	fi
	mkdir -p "$(dirname "$target")"
	if [[ -f "$target" ]] && cmp -s "$source" "$target"; then
		info "Sampling key already matches: $target"
	else
		cp "$source" "$target"
		info "Installed sampling key: $target"
	fi
}

function read_scheduler_script() {
	local repo="$1"
	local cluster="$2"
	local config_file="$repo/config/cluster.json"
	[[ -f "$config_file" ]] || die "Missing cluster config: $config_file"
	command -v jq >/dev/null 2>&1 || die "jq is required to read $config_file"
	jq -r ".$cluster.SCHEDULER_SCRIPT // \"\"" "$config_file"
}

function validate_scheduler_script() {
	local label="$1"
	local script_value="$2"
	local expected_config="$3"
	[[ -n "$script_value" && "$script_value" != "null" ]] ||
		die "$label cluster config has no SCHEDULER_SCRIPT for $CLUSTER"
	[[ "$script_value" == *"$DATASET"* ]] ||
		die "$label SCHEDULER_SCRIPT does not mention dataset '$DATASET': $script_value"
	[[ "$script_value" == *"$expected_config"* ]] ||
		die "$label SCHEDULER_SCRIPT does not mention config '$expected_config': $script_value"
}

function validate_python_fixed_sample() {
	local script_value="$1"
	[[ "$script_value" == *"USE_FIXED_SAMPLE=true"* ||
		"$script_value" == *"USE_FIXED_SAMPLE=1"* ||
		"$script_value" == *"USE_FIXED_SAMPLE=yes"* ]] ||
		die "Python SCHEDULER_SCRIPT must include USE_FIXED_SAMPLE=true for comparable fixed-sample runs: $script_value"
}

function run_and_log() {
	local label="$1"
	local logfile="$2"
	shift 2
	if [[ "$DRY_RUN" == true ]]; then
		info "Would run ($label): $*"
		return 0
	fi
	info "Launching $label; log: $logfile"
	"$@" 2>&1 | tee "$logfile"
}

function extract_job_ids() {
	local logfile="$1"
	[[ -f "$logfile" ]] || return 0
	grep -Eo 'Your job[[:space:]]+[0-9]+' "$logfile" | awk '{print $3}' | paste -sd ',' -
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_JULIA_REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
DEFAULT_PYTHON_REPO="$(cd "$DEFAULT_JULIA_REPO/.." && pwd)/OpenEMPIRE-csv"

DATASET=""
CONFIG=""
PYTHON_CONFIG=""
JULIA_REPO="$DEFAULT_JULIA_REPO"
PYTHON_REPO="$DEFAULT_PYTHON_REPO"
SEED="1"
SOLVER="Gurobi"
CLUSTER="Solstorm"
PERF=false
PERF_INTERVAL="1.0"
SAMPLING_KEY=""
GENERATE_KEY=false
ALLOW_CONFIG_MISMATCH=false
PREPARE_ONLY=false
DRY_RUN=false
RUNTIMES="julia,python"

while [[ $# -gt 0 ]]; do
	case "$1" in
		--dataset)
			DATASET="$2"
			shift 2
			;;
		--config)
			CONFIG="$2"
			shift 2
			;;
		--python-config)
			PYTHON_CONFIG="$2"
			shift 2
			;;
		--julia-repo)
			JULIA_REPO="$(abs_path "$2")"
			shift 2
			;;
		--python-repo)
			PYTHON_REPO="$(abs_path "$2")"
			shift 2
			;;
		--seed)
			SEED="$2"
			shift 2
			;;
		--solver)
			SOLVER="$2"
			shift 2
			;;
		--cluster)
			CLUSTER="$2"
			shift 2
			;;
		--perf)
			PERF=true
			shift
			;;
		--perf-interval)
			PERF_INTERVAL="$2"
			shift 2
			;;
		--sampling-key)
			SAMPLING_KEY="$(abs_path "$2")"
			shift 2
			;;
		--generate-key)
			GENERATE_KEY=true
			shift
			;;
		--allow-config-mismatch)
			ALLOW_CONFIG_MISMATCH=true
			shift
			;;
		--prepare-only)
			PREPARE_ONLY=true
			shift
			;;
		--dry-run)
			DRY_RUN=true
			shift
			;;
		--runtime)
			RUNTIMES="$2"
			shift 2
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

[[ -n "$DATASET" ]] || die "--dataset is required"
[[ -n "$CONFIG" ]] || die "--config is required"
[[ "$DATASET" != */* ]] || die "--dataset must be a dataset name, not a path: $DATASET"
[[ -d "$JULIA_REPO" ]] || die "Julia repo not found: $JULIA_REPO"
[[ -d "$PYTHON_REPO" ]] || die "Python repo not found: $PYTHON_REPO"
validate_runtimes "$RUNTIMES"
contains_runtime julia || contains_runtime python || die "--runtime must include julia and/or python"

if [[ -z "$PYTHON_CONFIG" ]]; then
	if [[ -f "$(resolve_in_repo "$PYTHON_REPO" "$CONFIG")" ]]; then
		PYTHON_CONFIG="$CONFIG"
	else
		PYTHON_CONFIG="config/$(basename "$CONFIG")"
	fi
fi

JULIA_CONFIG_PATH="$(resolve_in_repo "$JULIA_REPO" "$CONFIG")"
PYTHON_CONFIG_PATH="$(resolve_in_repo "$PYTHON_REPO" "$PYTHON_CONFIG")"
JULIA_DATA_DIR="$JULIA_REPO/data/$DATASET"
PYTHON_DATA_DIR="$PYTHON_REPO/input_data/$DATASET"
JULIA_KEY_TARGET="$JULIA_DATA_DIR/ScenarioData/sampling_key.csv"
PYTHON_KEY_TARGET="$PYTHON_DATA_DIR/ScenarioData/sampling_key.csv"

[[ -d "$JULIA_DATA_DIR" ]] || die "Julia dataset not found: $JULIA_DATA_DIR"
[[ -d "$PYTHON_DATA_DIR" ]] || die "Python dataset not found: $PYTHON_DATA_DIR"
[[ -f "$JULIA_CONFIG_PATH" ]] || die "Julia config not found: $JULIA_CONFIG_PATH"
[[ -f "$PYTHON_CONFIG_PATH" ]] || die "Python config not found: $PYTHON_CONFIG_PATH"

JULIA_CONFIG_SHA="$(sha256_file "$JULIA_CONFIG_PATH")"
PYTHON_CONFIG_SHA="$(sha256_file "$PYTHON_CONFIG_PATH")"
if [[ "$JULIA_CONFIG_SHA" != "$PYTHON_CONFIG_SHA" ]]; then
	if [[ "$ALLOW_CONFIG_MISMATCH" == true ]]; then
		info "WARNING: config checksums differ."
	else
		die "Config checksums differ. Use --allow-config-mismatch if this is intentional."
	fi
fi

JULIA_SCHEDULER=""
PYTHON_SCHEDULER=""
if [[ "$PREPARE_ONLY" == false && "$DRY_RUN" == false ]]; then
	if contains_runtime julia; then
		JULIA_SCHEDULER="$(read_scheduler_script "$JULIA_REPO" "$CLUSTER")"
		validate_scheduler_script "Julia" "$JULIA_SCHEDULER" "$CONFIG"
		[[ -x "$JULIA_REPO/scripts/copy_and_run_julia_on_hpc.sh" ]] ||
			die "Julia copy launcher is not executable: $JULIA_REPO/scripts/copy_and_run_julia_on_hpc.sh"
	fi

	if contains_runtime python; then
		PYTHON_SCHEDULER="$(read_scheduler_script "$PYTHON_REPO" "$CLUSTER")"
		validate_scheduler_script "Python" "$PYTHON_SCHEDULER" "$PYTHON_CONFIG"
		validate_python_fixed_sample "$PYTHON_SCHEDULER"
		[[ -x "$PYTHON_REPO/scripts/copy_and_run_empire_on_hpc.sh" ]] ||
			die "Python copy launcher is not executable: $PYTHON_REPO/scripts/copy_and_run_empire_on_hpc.sh"
	fi
fi

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
COMPARE_DIR="$JULIA_REPO/results/comparison_runs/${TIMESTAMP}_${DATASET}"
KEYGEN_ROOT="$COMPARE_DIR/keygen"

if [[ "$GENERATE_KEY" == true ]]; then
	[[ -z "$SAMPLING_KEY" ]] || die "Use either --generate-key or --sampling-key, not both."
	if [[ "$DRY_RUN" == true ]]; then
		info "Would generate sampling key with Julia seed=$SEED into $KEYGEN_ROOT"
		SAMPLING_KEY="$JULIA_KEY_TARGET"
	else
		mkdir -p "$KEYGEN_ROOT"
		info "Generating shared sampling key with Julia runner..."
		(
			cd "$JULIA_REPO"
			julia --project=. scripts/run_julia_empire.jl \
				--dataset="$DATASET" \
				--config="$CONFIG" \
				--format=csv \
				--solver="$SOLVER" \
				--seed="$SEED" \
				--generate-only \
				--results="$KEYGEN_ROOT"
		)
		SAMPLING_KEY="$(find "$KEYGEN_ROOT" -path '*/Input/csv/ScenarioData/sampling_key.csv' -type f | sort | tail -n 1)"
		[[ -n "$SAMPLING_KEY" && -f "$SAMPLING_KEY" ]] || die "Generated sampling key not found under $KEYGEN_ROOT"
	fi
fi

if [[ -z "$SAMPLING_KEY" ]]; then
	SAMPLING_KEY="$JULIA_KEY_TARGET"
fi

[[ "$DRY_RUN" == true || -f "$SAMPLING_KEY" ]] || die "Sampling key not found: $SAMPLING_KEY"

if [[ "$DRY_RUN" == true ]]; then
	KEY_SHA="dry-run"
else
	KEY_SHA="$(sha256_file "$SAMPLING_KEY")"
	copy_key_if_needed "$SAMPLING_KEY" "$JULIA_KEY_TARGET"
	copy_key_if_needed "$SAMPLING_KEY" "$PYTHON_KEY_TARGET"
	JULIA_KEY_SHA="$(sha256_file "$JULIA_KEY_TARGET")"
	PYTHON_KEY_SHA="$(sha256_file "$PYTHON_KEY_TARGET")"
	[[ "$JULIA_KEY_SHA" == "$PYTHON_KEY_SHA" && "$JULIA_KEY_SHA" == "$KEY_SHA" ]] ||
		die "Installed sampling keys do not match."
fi

PERF_VALUE=""
if [[ "$PERF" == true ]]; then
	PERF_VALUE="1"
fi

if [[ "$DRY_RUN" == false ]]; then
	mkdir -p "$COMPARE_DIR"
	MANIFEST="$COMPARE_DIR/comparison_manifest.txt"
	{
		echo "created_at=$TIMESTAMP"
		echo "dataset=$DATASET"
		echo "seed=$SEED"
		echo "cluster=$CLUSTER"
		echo "runtimes=$RUNTIMES"
		echo "julia_repo=$JULIA_REPO"
		echo "python_repo=$PYTHON_REPO"
		echo "julia_config=$JULIA_CONFIG_PATH"
		echo "python_config=$PYTHON_CONFIG_PATH"
		echo "julia_config_sha256=$JULIA_CONFIG_SHA"
		echo "python_config_sha256=$PYTHON_CONFIG_SHA"
		echo "sampling_key_source=$SAMPLING_KEY"
		echo "sampling_key_sha256=$KEY_SHA"
		echo "julia_sampling_key=$JULIA_KEY_TARGET"
		echo "python_sampling_key=$PYTHON_KEY_TARGET"
		echo "solver=$SOLVER"
		echo "perf=$PERF"
		echo "perf_interval=$PERF_INTERVAL"
		echo "status=prepared"
	} > "$MANIFEST"
	info "Comparison manifest written to: $MANIFEST"
else
	MANIFEST=""
fi

if [[ "$PREPARE_ONLY" == true || "$DRY_RUN" == true ]]; then
	info "Preparation complete; not submitting jobs."
	exit 0
fi

if contains_runtime julia; then
	JULIA_LOG="$COMPARE_DIR/julia_submit.log"
	run_and_log "Julia" "$JULIA_LOG" env \
		JULIA_SOLVER="$SOLVER" \
		JULIA_SEED="$SEED" \
		JULIA_OPTIMIZE="true" \
		JULIA_FIXED_SAMPLE="true" \
		EMPIRE_PERF="$PERF_VALUE" \
		EMPIRE_PERF_INTERVAL="$PERF_INTERVAL" \
		"$JULIA_REPO/scripts/copy_and_run_julia_on_hpc.sh" "$CLUSTER"
	JULIA_JOB_IDS="$(extract_job_ids "$JULIA_LOG")"
	echo "julia_submit_log=$JULIA_LOG" >> "$MANIFEST"
	echo "julia_job_ids=${JULIA_JOB_IDS:-unknown}" >> "$MANIFEST"
fi

if contains_runtime python; then
	PYTHON_LOG="$COMPARE_DIR/python_submit.log"
	run_and_log "Python" "$PYTHON_LOG" env \
		USE_FIXED_SAMPLE="true" \
		TEST_RUN="false" \
		EMPIRE_PERF="$PERF_VALUE" \
		EMPIRE_PERF_INTERVAL="$PERF_INTERVAL" \
		"$PYTHON_REPO/scripts/copy_and_run_empire_on_hpc.sh" "$CLUSTER"
	PYTHON_JOB_IDS="$(extract_job_ids "$PYTHON_LOG")"
	echo "python_submit_log=$PYTHON_LOG" >> "$MANIFEST"
	echo "python_job_ids=${PYTHON_JOB_IDS:-unknown}" >> "$MANIFEST"
fi

echo "status=submitted" >> "$MANIFEST"
info "Submitted requested runtimes. Manifest: $MANIFEST"
