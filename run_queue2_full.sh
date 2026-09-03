#!/usr/bin/env bash
# 剩余任务主队列 v2（2026-09-03）：单脚本顺序执行，无监视器无文件触发（防竞态）
#   ① 锁频补跑两格  ② 核心矩阵  ③ window_mult  ④ release 曲线  ⑤ w8 补充
# 状态: /root/queue2_status.txt
set -u
STATUS=/root/queue2_status.txt
echo "$(date -u +%FT%TZ) QUEUE2_START" > "$STATUS"

echo "$(date -u +%FT%TZ) STEP1 locked_rerun" >> "$STATUS"
bash /root/second_nvidia/phaseb-nvidia-port/run_locked_rerun.sh > /root/locked_rerun.log 2>&1
echo "$(date -u +%FT%TZ) STEP1 done rc=$?" >> "$STATUS"

echo "$(date -u +%FT%TZ) STEP2 stage1_core_matrix" >> "$STATUS"
bash /root/second_nvidia/ag-gemm-bench/scripts/run_stage1_a800_line.sh > /root/stage1_a800.log 2>&1
echo "$(date -u +%FT%TZ) STEP2 done rc=$? ($(grep -E 'MATRIX_DONE|MERGE_DONE|ABORT' /root/stage1_a800_status.txt | tr '\n' ' '))" >> "$STATUS"

echo "$(date -u +%FT%TZ) STEP3 window_mult" >> "$STATUS"
export LD_LIBRARY_PATH="/root/miniconda3/lib/python3.10/site-packages/nvidia/nvshmem/lib:${LD_LIBRARY_PATH:-}"
cd /root/second_nvidia/phaseb-nvidia-port && bash run_window_mult.sh > /root/window_mult.log 2>&1
echo "$(date -u +%FT%TZ) STEP3 done rc=$? pass=$(grep -c '\[PASS\]' /root/window_mult.log) fail=$(grep -c '\[FAIL\]' /root/window_mult.log)" >> "$STATUS"

echo "$(date -u +%FT%TZ) STEP4 release_curves" >> "$STATUS"
cd /root/second_nvidia/ag-gemm-bench && bash scripts/run_release_curves.sh > /root/release_curves.log 2>&1
echo "$(date -u +%FT%TZ) STEP4 done rc=$? root=$(ls -dt results/release_curves_* 2>/dev/null | head -1)" >> "$STATUS"

echo "$(date -u +%FT%TZ) STEP5 w8_supplement" >> "$STATUS"
bash /root/second_nvidia/ag-gemm-bench/scripts/run_window_w8_supplement.sh > /root/w8.log 2>&1
echo "$(date -u +%FT%TZ) STEP5 done rc=$?" >> "$STATUS"

echo "$(date -u +%FT%TZ) QUEUE2_END 全部完成" >> "$STATUS"
