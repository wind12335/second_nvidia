#!/usr/bin/env bash
# Matched-shape mini-matrix: run the 10-path port binary on MY stage-1 shapes
# so NCCL/NVSHMEM cross-substrate data lands on the same (m_local,K,N,q) grid
# as the stage-1 matrix (bridge between the two datasets).
#   S1 comm-heavy  m=4096 K=512  N=512
#   S4 balanced    m=512  K=4096 N=4096
#   S7 compute     m=1024 K=4096 N=16384
# paths: r0 rs r1 (NCCL) + d0 ds d1 (NVSHMEM) + comm gemm fc dc (isolated refs)
set -euo pipefail
port_dir=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
bin="$port_dir/ag_gemm_phaseb_nv"
outdir="$port_dir/results/matched_shapes_$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$outdir"
export LD_LIBRARY_PATH="/root/miniconda3/lib/python3.10/site-packages/nvidia/nvshmem/lib:${LD_LIBRARY_PATH:-}"
export NVSHMEM_SYMMETRIC_SIZE=1G
export CUDA_VISIBLE_DEVICES=0,1,2,3

REPS=${REPS:-3}
WARMUP=20
ITERS=50
SHAPES=("S1 4096 512 512" "S4 512 4096 4096" "S7 1024 4096 16384")
PATHS=(comm gemm r0 rs r1 fc dc d0 ds d1)
QS=(4 8 16)

manifest="$outdir/matched_manifest.csv"
echo "run_id,shape,m_local,K,N,q,path,rep,exit_code,case_dir" > "$manifest"
for entry in "${SHAPES[@]}"; do
  set -- $entry; sid=$1; ml=$2; kk=$3; nn=$4
  for q in "${QS[@]}"; do
    for path in "${PATHS[@]}"; do
      for rep in $(seq 1 "$REPS"); do
        run_id="matched_${sid}_${path}_q${q}_rep${rep}"
        case_dir="$outdir/$run_id"; mkdir -p "$case_dir"
        set +e
        timeout 900 mpirun --allow-run-as-root -np 4 -mca coll ^hcoll "$bin" \
          --path "$path" --m-local "$ml" --n "$nn" --k "$kk" --q "$q" \
          --warmup "$WARMUP" --iters "$ITERS" --verify-every 1 \
          --output-dir "$case_dir" --run-id "$run_id" --candidate C0_DEFAULT \
          < /dev/null > "$case_dir/stdout_stderr.log" 2>&1
        rc=$?
        set -e
        echo "$run_id,$sid,$ml,$kk,$nn,$q,$path,$rep,$rc,$case_dir" >> "$manifest"
        (( rc != 0 )) && echo "[FAIL] $run_id exit=$rc" || echo "[ ok ] $run_id"
      done
    done
  done
done
echo "matched-shape mini-matrix done: $manifest"
