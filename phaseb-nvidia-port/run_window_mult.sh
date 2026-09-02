#!/usr/bin/env bash
# Slot-depth sweep on the NVSHMEM overlap path (d1): --window-mult in {1,2,4}
# (symmetric slots = q * window_mult). Complements stage-1 Stage C (lookahead
# credit window on the NCCL path): together they cover both window axes the
# protocol distinguishes (in-flight bound vs slot-reuse depth).
set -euo pipefail
port_dir=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
bin="$port_dir/ag_gemm_phaseb_nv"
outdir="$port_dir/results/window_mult_$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$outdir"
export LD_LIBRARY_PATH="/root/miniconda3/lib/python3.10/site-packages/nvidia/nvshmem/lib:${LD_LIBRARY_PATH:-}"
export NVSHMEM_SYMMETRIC_SIZE=2G
export CUDA_VISIBLE_DEVICES=0,1,2,3

REPS=${REPS:-3}
SHAPES=("S4 512 4096 4096" "S5 4096 4096 1024")
QS=(4 8 16)
MULTS=(1 2 4)

manifest="$outdir/window_manifest.csv"
echo "run_id,shape,m_local,K,N,q,window_mult,rep,exit_code,case_dir" > "$manifest"
for entry in "${SHAPES[@]}"; do
  set -- $entry; sid=$1; ml=$2; kk=$3; nn=$4
  for q in "${QS[@]}"; do
    for wm in "${MULTS[@]}"; do
      for rep in $(seq 1 "$REPS"); do
        run_id="wm_${sid}_d1_q${q}m${wm}_rep${rep}"
        case_dir="$outdir/$run_id"; mkdir -p "$case_dir"
        set +e
        timeout 900 mpirun --allow-run-as-root -np 4 -mca coll ^hcoll "$bin" \
          --path d1 --m-local "$ml" --n "$nn" --k "$kk" --q "$q" \
          --window-mult "$wm" \
          --warmup 20 --iters 50 --verify-every 1 \
          --output-dir "$case_dir" --run-id "$run_id" --candidate C0_DEFAULT \
          < /dev/null > "$case_dir/stdout_stderr.log" 2>&1
        rc=$?
        set -e
        echo "$run_id,$sid,$ml,$kk,$nn,$q,$wm,$rep,$rc,$case_dir" >> "$manifest"
        (( rc != 0 )) && echo "[FAIL] $run_id exit=$rc" || echo "[ ok ] $run_id"
      done
    done
  done
done
echo "window_mult sweep done: $manifest"
