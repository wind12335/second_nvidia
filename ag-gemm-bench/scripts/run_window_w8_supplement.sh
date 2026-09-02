#!/usr/bin/env bash
# Stage-C w=8 补充实验（2026-09-03，海光三问之 Q2）：
# "深槽位救活 vs 前瞻无效" 判别点。主矩阵保持与 4090 完全同参不动（w{0,1,2,4}），
# 本脚本只在主矩阵之后补 w=8：同 Stage-C 三 shape × q{4,8,16} × 3 rep × DEFAULT × B2。
# 与海光 d2 window_mult∈{2,4} 构成同题双基座。
set -uo pipefail
cd /root/second_nvidia/ag-gemm-bench
STATUS=/root/full_queue_status.txt
echo "$(date -u +%FT%TZ) W8_SUPPLEMENT launching" >> "$STATUS"

nvidia-smi -lgc 1410,1410 >/dev/null 2>&1 && echo "w8: clocks locked 1410" >> "$STATUS"

outdir=results/window_w8_supplement_$(date -u +%Y%m%dT%H%M%SZ)
mkdir -p "$outdir"
export CUDA_VISIBLE_DEVICES=0,1,2,3
rc_total=0; n=0
for entry in "S1|4096|512|512" "S4|512|4096|4096" "S5|4096|4096|1024"; do
  IFS='|' read -r sid ml kk nn <<< "$entry"
  for q in 4 8 16; do
    for rep in 1 2 3; do
      run_id="w8_${sid}_q${q}_rep${rep}"
      mkdir -p "$outdir/$run_id"
      timeout 900 mpirun --allow-run-as-root --bind-to none -np 4 ./build/ag_gemm_bench \
        --local-rows "$ml" --k "$kk" --n "$nn" --q "$q" --window 8 \
        --warmup 20 --iterations 50 --run-id "$run_id" --output-dir "$outdir/$run_id" \
        < /dev/null > "$outdir/$run_id/console.log" 2>&1
      rc=$?; n=$((n+1)); [[ $rc -ne 0 ]] && rc_total=$((rc_total+1))
      echo "w8 $run_id rc=$rc" >> "$STATUS"
    done
  done
done
nvidia-smi -rgc >/dev/null 2>&1 && echo "w8: clocks reset" >> "$STATUS"
echo "$(date -u +%FT%TZ) W8_SUPPLEMENT done runs=$n fail=$rc_total" >> "$STATUS"
