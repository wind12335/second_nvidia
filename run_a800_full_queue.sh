#!/usr/bin/env bash
# A800 全量实验队列（2026-09-02 夜）：等 NVSHMEM 线 LINE_END 后一链到底
#   ① 4090核心矩阵复跑(run_stage1_a800_line: 锁频→preflight→Stage A/B/C→merge→解锁)
#   ② d1 × window_mult 扫描（海光协议的槽位深度轴）
#   ③ 代表性 case 逐分片 release 曲线导出（R_i 数据）
# 已知缺口：nsys 未装（Ubuntu 源无 NVIDIA nsight），trace 取证顺延，不阻塞以上三项
# 主状态文件: /root/full_queue_status.txt
set -u
STATUS=/root/full_queue_status.txt
echo "$(date -u +%FT%TZ) QUEUE_START (waiting NVSHMEM LINE_END)" > "$STATUS"

while ! grep -q "LINE_END" /root/port_line_status.txt 2>/dev/null; do sleep 60; done
echo "$(date -u +%FT%TZ) NVSHMEM_LINE_FINISHED: $(grep -E 'FORMAL_DONE|MATCHED' /root/port_line_status.txt | tr '\n' ' ')" >> "$STATUS"

# ① 核心矩阵
echo "$(date -u +%FT%TZ) STAGE1_LINE launching" >> "$STATUS"
bash /root/second_nvidia/ag-gemm-bench/scripts/run_stage1_a800_line.sh > /root/stage1_a800.log 2>&1
echo "$(date -u +%FT%TZ) STAGE1_LINE done rc=$? ($(grep -E 'MATRIX_DONE|MERGE_DONE|ABORT|PREFLIGHT' /root/stage1_a800_status.txt | tr '\n' ' '))" >> "$STATUS"

# ② window_mult 扫描（独立于①的成败，各自记录）
echo "$(date -u +%FT%TZ) WINDOW_MULT launching" >> "$STATUS"
export LD_LIBRARY_PATH="/root/miniconda3/lib/python3.10/site-packages/nvidia/nvshmem/lib:${LD_LIBRARY_PATH:-}"
cd /root/second_nvidia/phaseb-nvidia-port && bash run_window_mult.sh > /root/window_mult.log 2>&1
echo "$(date -u +%FT%TZ) WINDOW_MULT done rc=$? pass=$(grep -c '\[PASS\]' /root/window_mult.log) fail=$(grep -c '\[FAIL\]' /root/window_mult.log)" >> "$STATUS"

# ③ release 曲线
echo "$(date -u +%FT%TZ) RELEASE_CURVES launching" >> "$STATUS"
cd /root/second_nvidia/ag-gemm-bench && bash scripts/run_release_curves.sh > /root/release_curves.log 2>&1
echo "$(date -u +%FT%TZ) RELEASE_CURVES done rc=$? root=$(ls -dt results/release_curves_* | head -1)" >> "$STATUS"

echo "$(date -u +%FT%TZ) QUEUE_END 全部跑完" >> "$STATUS"
