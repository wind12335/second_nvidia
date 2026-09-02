#!/usr/bin/env bash
# Nsight Systems traces for representative stage-1 cases (post-matrix, GPUs exclusive).
# Purpose (checklist item 5 + B5 decomposition):
#  - verify NCCL 2.28.3 chunk-event granularity: q AllGather calls -> q comm-kernel groups
#  - separate true overlap vs launch queuing on comm/compute streams
#  - extract whole-GEMM (B0) vs slice-GEMM (B2) kernel durations for partition-loss
set -euo pipefail
script_dir=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
benchmark="$script_dir/build/ag_gemm_bench"
outdir="$script_dir/results/nsight_$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$outdir"
"$script_dir/scripts/collect_platform_facts.sh" "$outdir"

trace() { # name local_rows K N q warmup iters
  local name=$1 lr=$2 k=$3 n=$4 q=$5 wu=${6:-3} it=${7:-8}
  nsys profile -t cuda -s none --cpuctxsw=none --force-overwrite=true \
    -o "$outdir/$name" \
    mpirun --allow-run-as-root --bind-to none -np 4 "$benchmark" \
      --local-rows "$lr" --k "$k" --n "$n" --q "$q" --window 0 \
      --warmup "$wu" --iterations "$it" --run-id "nsys_$name" --transport-hint UNSPECIFIED \
      --output-dir "$outdir/case_$name" \
    > "$outdir/$name.stdout" 2> "$outdir/$name.stderr"
  echo "traced $name"
}

# S7 q8 first: spike-prone config (15/250 R0 stalls in matrix), 25 iters to catch one
trace S7_comp_q8    1024 4096 16384 8  3 25
trace S4_balanced_q4 512 4096 4096 4
trace S1_comm_q8    4096 512 512 8

for name in S4_balanced_q4 S1_comm_q8 S7_comp_q8; do
  nsys stats -r cuda_gpu_trace --format csv -o "$outdir/$name.kern" "$outdir/$name.nsys-rep" >/dev/null 2>&1 || true
  nsys stats -r cuda_gpu_kern_sum --format csv -o "$outdir/$name.ksum" "$outdir/$name.nsys-rep" >/dev/null 2>&1 || true
done
echo "traces + stats in $outdir"
