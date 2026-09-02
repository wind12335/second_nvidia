#!/usr/bin/env bash
# 自动衔接守护器（2026-09-02）：等 NVSHMEM 流水线 LINE_END → 发射 4090核心矩阵A800复跑
# 轮询 /root/port_line_status.txt，每 60s 一次；取消方式：kill 本进程 pid
set -u
while true; do
  if grep -q "LINE_END" /root/port_line_status.txt 2>/dev/null; then
    echo "$(date -u +%FT%TZ) NVSHMEM_LINE_FINISHED, launching stage1_a800_line" > /root/auto_chain.log
    MATCHED_STATE=$(grep -E "MATCHED_DONE|MATCHED_SKIPPED" /root/port_line_status.txt | tail -1)
    echo "context: $MATCHED_STATE" >> /root/auto_chain.log
    exec bash /root/second_nvidia/ag-gemm-bench/scripts/run_stage1_a800_line.sh
  fi
  sleep 60
done
