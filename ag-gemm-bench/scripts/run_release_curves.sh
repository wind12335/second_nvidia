#!/usr/bin/env bash
# Re-run representative cases with --dump-release-curve to export per-slice R_i
# (protocol §7.2 release CSV). Must run AFTER the main matrix with the rebuilt
# binary; keeps 20 warmup + 50 timed so timings remain protocol-comparable.
set -euo pipefail
script_dir=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
benchmark="$script_dir/build/ag_gemm_bench"
outdir="$script_dir/results/release_curves_$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$outdir"
"$script_dir/scripts/collect_platform_facts.sh" "$outdir"

# shape local_rows K N | q list — representative coverage incl. Stage-C window points
CASES=(
  "S1 4096 512 512|4 8 16"
  "S4 512 4096 4096|2 4 8 16"
  "S5 4096 4096 1024|4 8 16"
  "S7 1024 4096 16384|4 8 16"
  "S8 2048 4096 8192|4 8"
)

for entry in "${CASES[@]}"; do
  spec=${entry%%|*}; qlist=${entry##*|}
  set -- $spec; sid=$1; lr=$2; k=$3; n=$4
  for q in $qlist; do
    for w in 0; do
      run_id="relcurve_${sid}_q${q}w${w}"
      case_dir="$outdir/$run_id"
      mkdir -p "$case_dir"
      mpirun --allow-run-as-root --bind-to none -np 4 "$benchmark" \
        --local-rows "$lr" --k "$k" --n "$n" --q "$q" --window "$w" \
        --warmup 20 --iterations 50 --run-id "$run_id" --transport-hint DEFAULT \
        --output-dir "$case_dir" --dump-release-curve "$case_dir/release_curve" \
        > "$case_dir/stdout.log" 2> "$case_dir/stderr.log"
      echo "$run_id exit=$?"
    done
  done
done
echo "release curves in $outdir"
