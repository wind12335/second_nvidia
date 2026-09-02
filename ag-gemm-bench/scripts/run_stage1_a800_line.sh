#!/usr/bin/env bash
# 4090 核心矩阵 A800 复跑编排（2026-09-02 预写，等用户发话后 setsid 发射）
# 阶段: 可选锁频 → 2卡preflight门槛 → Stage A/B/C 全矩阵 → merge 汇总 → 解锁频
# 状态文件: /root/stage1_a800_status.txt
set -uo pipefail
cd /root/second_nvidia/ag-gemm-bench
STATUS=/root/stage1_a800_status.txt
echo "$(date -u +%FT%TZ) STAGE1_LINE_START" > "$STATUS"

# ---- 1) 锁频（裸机可锁则锁，失败则记录并继续——沿用 4090 的"同 run 内比较"红线解释）----
LOCK=${LOCK_CLOCKS:-1}
if [[ $LOCK == 1 ]]; then
  if nvidia-smi -lgc 1410,1410 >/dev/null 2>&1; then
    echo "clocks_locked graphics=1410" >> "$STATUS"
  else
    echo "clocks_lock_FAILED -> 跨run比较仍受限, 主结论同run内比较(4090同款红线)" >> "$STATUS"
  fi
fi

# ---- 2) 2 卡 preflight 门槛（B0/B1/B2 全 PASS 才继续）----
echo "$(date -u +%FT%TZ) PREFLIGHT_START" >> "$STATUS"
PF_DIR=results/preflight2gpu_$(date -u +%Y%m%dT%H%M%SZ)
mkdir -p "$PF_DIR"
mpirun --allow-run-as-root --bind-to none -np 2 ./build/ag_gemm_bench \
  --local-rows 128 --k 128 --n 128 --q 4 --window 2 --warmup 3 --iterations 5 \
  --run-id preflight2 --output-dir "$PF_DIR" > "$PF_DIR.log" 2>&1 < /dev/null
PF_RC=$?
BAD=$(grep -c "FAIL" "$PF_DIR/raw_global_samples.csv" 2>/dev/null || echo 1)
ROWS=$(($(wc -l < "$PF_DIR/raw_global_samples.csv" 2>/dev/null || echo 1) - 1))
if [[ $PF_RC -ne 0 || $BAD -gt 0 || $ROWS -lt 1 ]]; then
  echo "$(date -u +%FT%TZ) PREFLIGHT_FAIL rc=$PF_RC bad=$BAD rows=$ROWS -> ABORT(不进矩阵)" >> "$STATUS"
  nvidia-smi -rgc >/dev/null 2>&1 || true
  exit 1
fi
echo "$(date -u +%FT%TZ) PREFLIGHT_PASS rows=$ROWS" >> "$STATUS"

# ---- 3) Stage A/B/C 全矩阵（与 4090 完全同参数: 20 warmup/50 iters/5 rep）----
echo "$(date -u +%FT%TZ) MATRIX_START stages=A,B,C" >> "$STATUS"
RANKS=4 WARMUP=20 ITERATIONS=50 STAGES="A B C" bash scripts/run_stage1_full.sh > /tmp/stage1_matrix.log 2>&1
MRC=$?
echo "$(date -u +%FT%TZ) MATRIX_DONE rc=$MRC" >> "$STATUS"

# ---- 4) merge 汇总 ----
if [[ $MRC -eq 0 ]]; then
  ROOT=$(ls -dt results/stage1_* | head -1)
  python3 scripts/merge_stage1_results.py "$ROOT" > /tmp/stage1_merge.log 2>&1
  echo "$(date -u +%FT%TZ) MERGE_DONE root=$ROOT rc=$?" >> "$STATUS"
fi

# ---- 5) 解锁频 ----
nvidia-smi -rgc >/dev/null 2>&1 && echo "clocks_reset" >> "$STATUS"
echo "$(date -u +%FT%TZ) STAGE1_LINE_END" >> "$STATUS"
