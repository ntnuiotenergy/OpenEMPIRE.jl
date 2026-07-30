#!/bin/bash
# Capture SGE accounting for a finished EMPIRE job into logs/perf_<JOB_ID>.txt.
#
# qacct is the authoritative source for peak memory on Solstorm (maxvmem) and a
# second independent peak-RSS figure (ru_maxrss), alongside cpu/wallclock. It can
# lag a few minutes after the job ends, so this is a standalone post-hoc step
# rather than something the job runs on itself.
#
# Usage:
#   sh scripts/perf/collect_qacct.sh <JOB_ID> [out_file]
#   # retries until accounting is available (qacct returns the record)

set -u

JOB_ID=${1:?"usage: collect_qacct.sh <JOB_ID> [out_file]"}
OUT=${2:-logs/perf_${JOB_ID}.txt}
RETRIES=${QACCT_RETRIES:-30}
SLEEP=${QACCT_SLEEP:-20}

mkdir -p "$(dirname "$OUT")"

if ! command -v qacct >/dev/null 2>&1; then
	echo "ERROR: qacct not found. Run this on Solstorm (SGE submit/exec host)." >&2
	exit 1
fi

echo "Collecting SGE accounting for job ${JOB_ID} (up to ${RETRIES} tries)..."
for i in $(seq 1 "$RETRIES"); do
	if qacct -j "$JOB_ID" >"$OUT" 2>/dev/null && grep -q "jobnumber" "$OUT"; then
		echo "Wrote accounting to ${OUT}"
		echo "--- key memory/runtime fields ---"
		grep -E "hostname|qsub_time|start_time|end_time|ru_wallclock|cpu|ru_maxrss|maxvmem|mem |slots" "$OUT" || true
		exit 0
	fi
	echo "  attempt ${i}/${RETRIES}: accounting not ready yet, sleeping ${SLEEP}s..."
	sleep "$SLEEP"
done

echo "ERROR: accounting for job ${JOB_ID} not available after $((RETRIES * SLEEP))s." >&2
exit 1
