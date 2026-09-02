#!/usr/bin/env bash
# 等 QUEUE_END → 自动跑 w=8 补充（海光 Q2 判别点）
set -u
while ! grep -q "QUEUE_END" /root/full_queue_status.txt 2>/dev/null; do sleep 120; done
bash /root/second_nvidia/ag-gemm-bench/scripts/run_window_w8_supplement.sh
