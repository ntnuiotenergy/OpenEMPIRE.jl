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
  --allow-config-mismatch     Warn instead of failing when model-relevant config
                              keys differ between the Julia and Python configs

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

Config comparison is by model-relevant keys (horizon, scenarios, season length,
discount_rate, wacc, emission cap, leap years, north_sea, time_format), not a raw
checksum: the two ports' config files are never byte-identical. Solver settings
are reported as a warning, since Gurobi parameters may live outside the Python
YAML.

cluster.json is the source of truth for what runs remotely. The existing repo
launchers read their own config/cluster.json, and dataset/config/solver on the
remote side come from each SCHEDULER_SCRIPT, not this script's flags. Before
submitting, this script checks that each SCHEDULER_SCRIPT references the requested
dataset (as a distinct argument) and config path, so mismatched cluster configs
fail early. The Python SCHEDULER_SCRIPT must also include USE_FIXED_SAMPLE=true
and must not be a test run, because the Python copy launcher forwards only
EMPIRE_PERF* and otherwise owns the remote scheduler command.
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

function yaml_scalar() {
	# Print the scalar value of a top-level "key: value" line, ignoring comment
	# lines and inline comments. Empty output means the key is absent. Only used
	# for the flat, top-level EMPIRE config keys we compare for parity.
	local file="$1"
	local key="$2"
	[[ -f "$file" ]] || return 0
	awk -v key="$key" '
		/^[[:space:]]*#/ { next }
		{
			line = $0
			sub(/#.*/, "", line)
		}
		match(line, "^[[:space:]]*" key "[[:space:]]*:[[:space:]]*") {
			val = substr(line, RLENGTH + 1)
			gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
			gsub(/^"|"$/, "", val)
			print val
			exit
		}
	' "$file"
}

function repo_commit() {
	# "sha (branch)" with a -dirty suffix, or "unknown" for non-git folders
	# (e.g. copied HPC directories).
	local repo="$1"
	if git -C "$repo" rev-parse HEAD >/dev/null 2>&1; then
		local commit branch dirty=""
		commit="$(git -C "$repo" rev-parse HEAD 2>/dev/null)"
		branch="$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null)"
		[[ -n "$(git -C "$repo" status --porcelain 2>/dev/null)" ]] && dirty="-dirty"
		printf '%s (%s)%s\n' "$commit" "$branch" "$dirty"
	else
		printf 'unknown\n'
	fi
}

function read_scheduler_script_soft() {
	# Best-effort SCHEDULER_SCRIPT read for the manifest; empty on any failure so
	# it works in --prepare-only without requiring jq/cluster.json.
	local repo="$1"
	local cluster="$2"
	local config_file="$repo/config/cluster.json"
	[[ -f "$config_file" ]] || return 0
	command -v jq >/dev/null 2>&1 || return 0
	jq -r ".$cluster.SCHEDULER_SCRIPT // \"\"" "$config_file" 2>/dev/null
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
	[[ "$script_value" =~ (^|[^[:alnum:]_])"$DATASET"([^[:alnum:]_]|$) ]] ||
		die "$label SCHEDULER_SCRIPT does not reference dataset '$DATASET' as a distinct argument (pass it explicitly, do not rely on the SGE default): $script_value"
	[[ "$script_value" == *"$expected_config"* ]] ||
		die "$label SCHEDULER_SCRIPT does not mention config '$expected_config' (pass it explicitly, do not rely on the SGE default): $script_value"
}

function validate_python_fixed_sample() {
	local script_value="$1"
	[[ "$script_value" == *"USE_FIXED_SAMPLE=true"* ||
		"$script_value" == *"USE_FIXED_SAMPLE=1"* ||
		"$script_value" == *"USE_FIXED_SAMPLE=yes"* ]] ||
		die "Python SCHEDULER_SCRIPT must include USE_FIXED_SAMPLE=true for comparable fixed-sample runs: $script_value"
}

function validate_python_not_test_run() {
	# The Python copy launcher only forwards EMPIRE_PERF*, so fixed-sample/test-run
	# selection lives entirely in the SCHEDULER_SCRIPT. Refuse an obvious test run.
	local script_value="$1"
	[[ "$script_value" != *"--test-run"* &&
		"$script_value" != *"TEST_RUN=true"* &&
		"$script_value" != *"TEST_RUN=1"* &&
		"$script_value" != *"TEST_RUN=yes"* ]] ||
		die "Python SCHEDULER_SCRIPT enables a test run; refusing to launch a non-comparable Python job: $script_value"
}

# Config keys that must agree for a fair comparison. Runtime-specific keys such
# as use_fixed_sample and the Gurobi solver_* block are handled separately: they
# differ by design between the two ports.
PARITY_CONFIG_KEYS=(
	forecast_horizon_year
	number_of_scenarios
	length_of_regular_season
	discount_rate
	wacc
	use_emission_cap
	use_scenario_generation
	leap_years_investment
	north_sea
	time_format
)

# Solver keys: recorded and warned on, never fatal, because the Python reference
# may source Gurobi parameters outside its YAML config.
SOLVER_CONFIG_KEYS=(
	optimization_solver
	solver_method
	solver_crossover
	solver_presolve
	solver_threads
)

function compare_config_parity() {
	# Populate CONFIG_MISMATCHES (fatal unless --allow-config-mismatch) and
	# SOLVER_NOTES (warn-only) by comparing individual keys, not raw checksums:
	# the two ports' config files are never byte-identical.
	CONFIG_MISMATCHES=()
	SOLVER_NOTES=()
	local key jv pv
	for key in "${PARITY_CONFIG_KEYS[@]}"; do
		jv="$(yaml_scalar "$JULIA_CONFIG_PATH" "$key")"
		pv="$(yaml_scalar "$PYTHON_CONFIG_PATH" "$key")"
		if [[ -z "$jv" || -z "$pv" ]]; then
			CONFIG_MISMATCHES+=("$key: julia='${jv:-<absent>}' python='${pv:-<absent>}'")
		elif [[ "$jv" != "$pv" ]]; then
			CONFIG_MISMATCHES+=("$key: julia='$jv' python='$pv'")
		fi
	done
	for key in "${SOLVER_CONFIG_KEYS[@]}"; do
		jv="$(yaml_scalar "$JULIA_CONFIG_PATH" "$key")"
		pv="$(yaml_scalar "$PYTHON_CONFIG_PATH" "$key")"
		if [[ "$jv" != "$pv" ]]; then
			SOLVER_NOTES+=("$key: julia='${jv:-<absent>}' python='${pv:-<absent>}'")
		fi
	done
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
	# SGE prints "Your job N (...) has been submitted" (or "Your job-array N ...").
	# The trailing `|| true` keeps a no-match from tripping set -e/pipefail.
	local logfile="$1"
	[[ -f "$logfile" ]] || return 0
	grep -Eo 'Your job(-array)?[[:space:]]+[0-9]+' "$logfile" 2>/dev/null | awk '{print $NF}' | paste -sd ',' - || true
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
MANIFEST=""

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
# The two ports' config files are never byte-identical (different headers, the
# Julia solver_* block, use_fixed_sample), so compare model-relevant keys instead
# of raw checksums.
compare_config_parity
if [[ ${#CONFIG_MISMATCHES[@]} -gt 0 ]]; then
	info "Config parity differences on model-relevant keys:"
	for entry in "${CONFIG_MISMATCHES[@]}"; do
		info "  - $entry"
	done
	if [[ "$ALLOW_CONFIG_MISMATCH" == true ]]; then
		info "WARNING: continuing despite config parity differences (--allow-config-mismatch)."
	else
		die "Julia/Python configs differ on model-relevant keys (see above). Align the configs or pass --allow-config-mismatch."
	fi
else
	info "Config parity check passed on model-relevant keys."
fi
if [[ ${#SOLVER_NOTES[@]} -gt 0 ]]; then
	info "NOTE: solver settings differ between configs; verify Gurobi parameters (method/crossover/presolve/threads) match on both sides:"
	for entry in "${SOLVER_NOTES[@]}"; do
		info "  - $entry"
	done
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
		validate_python_not_test_run "$PYTHON_SCHEDULER"
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

# Empty means "defer to each launcher's cluster.json default" — the launchers
# treat EMPIRE_PERF="" as unset. --perf forces it on for both runtimes.
PERF_VALUE=""
if [[ "$PERF" == true ]]; then
	PERF_VALUE="1"
fi

# Record what actually determines each HPC run: the SCHEDULER_SCRIPT in each
# repo's cluster.json owns dataset/config/solver on the remote side.
JULIA_SCHEDULER_MANIFEST="$(read_scheduler_script_soft "$JULIA_REPO" "$CLUSTER")"
PYTHON_SCHEDULER_MANIFEST="$(read_scheduler_script_soft "$PYTHON_REPO" "$CLUSTER")"
CONFIG_PARITY="ok"
[[ ${#CONFIG_MISMATCHES[@]} -eq 0 ]] || CONFIG_PARITY="mismatch"
SOLVER_DIFFERENCES="none"
if [[ ${#SOLVER_NOTES[@]} -gt 0 ]]; then
	SOLVER_DIFFERENCES="$(
		IFS='|'
		echo "${SOLVER_NOTES[*]}"
	)"
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
		echo "julia_commit=$(repo_commit "$JULIA_REPO")"
		echo "python_commit=$(repo_commit "$PYTHON_REPO")"
		echo "julia_config=$JULIA_CONFIG_PATH"
		echo "python_config=$PYTHON_CONFIG_PATH"
		echo "julia_config_sha256=$JULIA_CONFIG_SHA"
		echo "python_config_sha256=$PYTHON_CONFIG_SHA"
		echo "config_parity=$CONFIG_PARITY"
		echo "solver_config_differences=$SOLVER_DIFFERENCES"
		echo "julia_scheduler_script=${JULIA_SCHEDULER_MANIFEST:-unknown}"
		echo "python_scheduler_script=${PYTHON_SCHEDULER_MANIFEST:-unknown}"
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
	echo "julia_submit_log=$JULIA_LOG" >> "$MANIFEST"
	# `if run_and_log ...` disables set -e for the launcher call so a failed
	# submit is recorded in the manifest rather than aborting silently.
	if run_and_log "Julia" "$JULIA_LOG" env \
		JULIA_SOLVER="$SOLVER" \
		JULIA_SEED="$SEED" \
		JULIA_OPTIMIZE="true" \
		JULIA_FIXED_SAMPLE="true" \
		EMPIRE_PERF="$PERF_VALUE" \
		EMPIRE_PERF_INTERVAL="$PERF_INTERVAL" \
		"$JULIA_REPO/scripts/copy_and_run_julia_on_hpc.sh" "$CLUSTER"; then
		JULIA_JOB_IDS="$(extract_job_ids "$JULIA_LOG")"
		echo "julia_job_ids=${JULIA_JOB_IDS:-unknown}" >> "$MANIFEST"
	else
		echo "julia_job_ids=failed" >> "$MANIFEST"
		echo "status=failed" >> "$MANIFEST"
		die "Julia submission failed; see $JULIA_LOG"
	fi
fi

if contains_runtime python; then
	PYTHON_LOG="$COMPARE_DIR/python_submit.log"
	echo "python_submit_log=$PYTHON_LOG" >> "$MANIFEST"
	# copy_and_run_empire_on_hpc.sh only forwards EMPIRE_PERF*; fixed-sample and
	# non-test-run selection are enforced above via the SCHEDULER_SCRIPT checks,
	# not passed as env, so we do not set USE_FIXED_SAMPLE/TEST_RUN here.
	if run_and_log "Python" "$PYTHON_LOG" env \
		EMPIRE_PERF="$PERF_VALUE" \
		EMPIRE_PERF_INTERVAL="$PERF_INTERVAL" \
		"$PYTHON_REPO/scripts/copy_and_run_empire_on_hpc.sh" "$CLUSTER"; then
		PYTHON_JOB_IDS="$(extract_job_ids "$PYTHON_LOG")"
		echo "python_job_ids=${PYTHON_JOB_IDS:-unknown}" >> "$MANIFEST"
	else
		echo "python_job_ids=failed" >> "$MANIFEST"
		echo "status=failed" >> "$MANIFEST"
		die "Python submission failed; see $PYTHON_LOG"
	fi
fi

echo "status=submitted" >> "$MANIFEST"
info "Submitted requested runtimes. Manifest: $MANIFEST"
