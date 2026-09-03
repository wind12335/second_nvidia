#!/usr/bin/env bash
# 队列 v3（2026-09-03）：重跑 queue2 中失败的三步（bug 已修：事件 record + w8 q16-only）
set -u
STATUS=/root/queue3_status.txt
echo "$(date -u +%FT%TZ) QUEUE3_START" > "$STATUS"

echo "$(date -u +%FT%TZ) STEP2 stage1_core_matrix(修复版)" >> "$STATUS"
bash /root/second_nvidia/ag-gemm-bench/scripts/run_stage1_a800_line.sh > /root/stage1_a800.log 2>&1
echo "$(date -u +%FT%TZ) STEP2 done rc=$? ($(grep -E 'MATRIX_DONE|MERGE_DONE|ABORT|PREFLIGHT' /root/stage1_a800_status.txt | tr '\n' ' '))" >> "$STATUS"

echo "$(date -u +%FT%TZ) STEP4 release_curves(修复版)" >> "$STATUS"
cd /root/second_nvidia/ag-gemm-bench && bash scripts/run_release_curves.sh > /root/release_curves.log 2>&1
echo "$(date -u +%FT%TZ) STEP4 done rc=$? root=$(ls -dt results/release_curves_* | head -1) cases=$(ls $(ls -dt results/release_curves_* | head -1) | grep -c relcurve)" >> "$STATUS"

echo "$(date -u +%FT%TZ) STEP5 w8_supplement(q16-only修复版)" >> "$STATUS"
bash /root/second_nvidia/ag-gemm-bench/scripts/run_window_w8_supplement.sh > /root/w8.log 2>&1
echo "$(date -u +%FT%TZ) STEP5 done rc=$? ($(grep W8_SUPPLEMENT /root/full_queue_status.txt | tail -1))" >> "$STATUS"

echo "$(date -u +%FT%TZ) QUEUE3_END" >> "$STATUS"
