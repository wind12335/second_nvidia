#!/usr/bin/env bash
# nvshmem_phaseB admission runner: smoke gate first, then formal (README-RUN-ORDER §2).
# Protocol alignment with Phase A: epoch signal + credit slot reuse + full payload checksum.
set -euo pipefail
phase_dir=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
bin="$phase_dir/build/nvshmem_admission"
wheel_lib=/root/miniconda3/lib/python3.10/site-packages/nvidia/nvshmem/lib
config=${1:-$phase_dir/configs/admission_smoke.csv}
ranks=${RANKS:-4}
outdir=${2:-$phase_dir/results/$(basename "$config" .csv)_$(date -u +%Y%m%dT%H%M%SZ)}
mkdir -p "$outdir"
cp "$config" "$outdir/config_used.csv"
export LD_LIBRARY_PATH="$wheel_lib:${LD_LIBRARY_PATH:-}"

run_case() {
  local line=$1
  [[ "$line" == \#* || -z "$line" ]] && return 0
  IFS=, read -r case_id mode payload epochs slots credit quiet credit_quiet timeout <<< "$line"
  local case_dir="$outdir/$case_id"
  mkdir -p "$case_dir"
  set +e
  timeout "$timeout" mpirun --allow-run-as-root --bind-to none -np "$ranks" "$bin" < /dev/null \
    --case-id "$case_id" --mode "$mode" --payload-bytes "$payload" \
    --epochs "$epochs" --slots "$slots" --credit "$credit" --quiet "$quiet" \
    --credit-quiet "$credit_quiet" --expected-pes "$ranks" \
    --outdir "$case_dir" > "$case_dir/stdout.log" 2> "$case_dir/stderr.log"
  local rc=$?
  set -e
  # PASS rule: exit 0 AND every rank csv has zero checksum mismatches on every epoch
  local mism=0
  for f in "$case_dir"/raw/rank_*.csv; do
    [[ -e "$f" ]] || continue
    m=$(awk -F, 'NR>1 && $11 != 0' "$f" | wc -l)
    mism=$((mism + m))
  done
  local verdict=FAIL
  if [[ $rc -eq 0 && $mism -eq 0 ]]; then verdict=PASS; fi
  echo "$case_id,$rc,$mism,$verdict" >> "$outdir/admission_manifest.csv"
  echo "[$verdict] $case_id rc=$rc checksum_mismatch_rows=$mism"
}

echo "case_id,exit_code,checksum_mismatch_rows,verdict" > "$outdir/admission_manifest.csv"
while IFS= read -r line; do run_case "$line"; done < "$config"
echo "admission done: $outdir/admission_manifest.csv"
