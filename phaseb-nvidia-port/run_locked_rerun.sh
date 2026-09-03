#!/usr/bin/env bash
# 锁频补跑两格（2026-09-03，P17 §7 程序的 UNDETERMINED 终判）：
#   N2048/q8 + N4096/q8 的 d0/d1 × C0 × 5rep，锁 1410MHz，口径同 matched
set -uo pipefail
cd /root/second_nvidia/phaseb-nvidia-port
export LD_LIBRARY_PATH="/root/miniconda3/lib/python3.10/site-packages/nvidia/nvshmem/lib:${LD_LIBRARY_PATH:-}"
export NVSHMEM_SYMMETRIC_SIZE=1G CUDA_VISIBLE_DEVICES=0,1,2,3
STATUS=/root/queue2_status.txt
REPS=5; WARMUP=20; ITERS=50; ML=2048; KK=2048
outdir="results/locked_rerun_$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$outdir"

if nvidia-smi -lgc 1410,1410 >/dev/null 2>&1; then
  echo "$(date -u +%FT%TZ) LOCKED_RERUN clocks locked 1410" >> "$STATUS"
  LOCKED=1
else
  echo "$(date -u +%FT%TZ) LOCKED_RERUN clocks_lock_FAILED 继续未锁频(标注)" >> "$STATUS"
  LOCKED=0
fi
echo "locked=$LOCKED" > "$outdir/clock_state.txt"

manifest="$outdir/locked_manifest.csv"
echo "run_id,cell,path,rep,exit_code,case_dir" > "$manifest"
for CELL in "2048 8" "4096 8"; do
  set -- $CELL; nn=$1; q=$2
  for path in d0 d1; do
    for rep in $(seq 1 $REPS); do
      rid="lr_${path}_N${nn}_q${q}_rep${rep}"
      mkdir -p "$outdir/$rid"
      set +e
      timeout 1200 mpirun --allow-run-as-root -np 4 -mca coll ^hcoll ./ag_gemm_phaseb_nv \
        --path "$path" --m-local "$ML" --n "$nn" --k "$KK" --q "$q" \
        --warmup $WARMUP --iters $ITERS --verify-every 1 \
        --output-dir "$outdir/$rid" --run-id "$rid" --candidate C0_DEFAULT \
        < /dev/null > "$outdir/$rid/stdout_stderr.log" 2>&1
      rc=$?
      set -e
      echo "$rid,N${nn}/q${q},$path,$rep,$rc,$outdir/$rid" >> "$manifest"
      echo "$(date -u +%FT%TZ) LOCKED_RERUN $rid rc=$rc" >> "$STATUS"
    done
  done
done
[[ $LOCKED == 1 ]] && nvidia-smi -rgc >/dev/null 2>&1 && echo "clocks reset" >> "$outdir/clock_state.txt"
echo "$(date -u +%FT%TZ) LOCKED_RERUN_DONE outdir=$outdir fail=$(awk -F, 'NR>1 && $5!=0' "$manifest" | wc -l)" >> "$STATUS"
