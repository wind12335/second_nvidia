#!/usr/bin/env bash
# Matched-shape 矩阵（海光口径, 2026-09-02 A800 会话）:
#   统一 --m-local 2048 --k 2048；格点（海光 21:06 指定 + 22:01 追加裁决格）:
#     N512/q8   N2048/q8 (必跑/STRONG反转格)  N2048/q16 (q16爆炸格)
#     N4096/q8  (d1赢的边界格)                N8192/q16 (边界定律闭式裁决格, P14)
#   DX 四件套口径: {comm, r1} × {C0_DEFAULT, C2_RING_SIMPLE_CH8}
#   d 族对照: {d0, d1} × C0（对表海光 d_family 11 格终判）
# 用法: bash run_matched_shapes_hygon.sh   (REPS 可环境覆盖, 默认 5)
set -euo pipefail
port_dir=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
bin="$port_dir/ag_gemm_phaseb_nv"
outdir="$port_dir/results/matched_hygon_$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$outdir"
export LD_LIBRARY_PATH="/root/miniconda3/lib/python3.10/site-packages/nvidia/nvshmem/lib:${LD_LIBRARY_PATH:-}"
export NVSHMEM_SYMMETRIC_SIZE=1G
export CUDA_VISIBLE_DEVICES=0,1,2,3

REPS=${REPS:-5}
WARMUP=20
ITERS=50
ML=2048; KK=2048
CELLS=("512 8" "2048 8" "2048 16" "4096 8" "8192 16")   # N q

manifest="$outdir/matched_hygon_manifest.csv"
echo "run_id,cell,N,q,path,cand,rep,exit_code,case_dir" > "$manifest"

run_one() {  # path cand N q rep
  local path=$1 cand=$2 nn=$3 q=$4 rep=$5
  local run_id="mh_${path}_${cand}_N${nn}_q${q}_rep${rep}"
  local case_dir="$outdir/$run_id"; mkdir -p "$case_dir"
  # C2 环境映射（交接 §3-3）：Ring/Simple/ch8；C0 走默认
  if [[ "$cand" == C2* ]]; then
    export NCCL_ALGO=Ring NCCL_PROTO=Simple NCCL_MIN_NCHANNELS=8 NCCL_MAX_NCHANNELS=8
  else
    unset NCCL_ALGO NCCL_PROTO NCCL_MIN_NCHANNELS NCCL_MAX_NCHANNELS
  fi
  set +e
  timeout 1200 mpirun --allow-run-as-root -np 4 -mca coll ^hcoll "$bin" \
    --path "$path" --m-local "$ML" --n "$nn" --k "$KK" --q "$q" \
    --warmup "$WARMUP" --iters "$ITERS" --verify-every 1 \
    --output-dir "$case_dir" --run-id "$run_id" --candidate "$cand" \
    < /dev/null > "$case_dir/stdout_stderr.log" 2>&1
  local rc=$?
  set -e
  unset NCCL_ALGO NCCL_PROTO NCCL_MIN_NCHANNELS NCCL_MAX_NCHANNELS
  echo "$run_id,${nn},$q,$path,$cand,$rep,$rc,$case_dir" >> "$manifest"
  local verdict=FAIL; [[ $rc -eq 0 ]] && verdict=PASS
  echo "[$verdict] $run_id rc=$rc"
}

for entry in "${CELLS[@]}"; do
  set -- $entry; nn=$1; q=$2
  for path in comm r1; do
    for cand in C0_DEFAULT C2_RING_SIMPLE_CH8; do
      for rep in $(seq 1 "$REPS"); do run_one "$path" "$cand" "$nn" "$q" "$rep"; done
    done
  done
  for path in d0 d1; do
    for rep in $(seq 1 "$REPS"); do run_one "$path" C0_DEFAULT "$nn" "$q" "$rep"; done
  done
done

pass=$(awk -F, 'NR>1 && $7==0' "$manifest" | wc -l)
total=$(($(wc -l < "$manifest") - 1))
echo "== matched(hygon口径) complete: $total cases, $((total-pass)) failed =="
echo "result_root=$outdir"
