#!/usr/bin/env bash
# nsys 论文取证采样（2026-09-03）：六张关键 timeline，正反例配对
# 产出: /root/seconde-paper/work-20260903/nsys取证/*.nsys-rep + manifest + sha256
set -uo pipefail
OUT=/root/seconde-paper/work-20260903/nsys取证
cd "$(dirname "$0")"
export LD_LIBRARY_PATH="/root/miniconda3/lib/python3.10/site-packages/nvidia/nvshmem/lib:${LD_LIBRARY_PATH:-}"
MANIFEST="$OUT/manifest-20260903.csv"
echo "case_id,bench,shape,rep_file,sha256" > "$MANIFEST"

nsys_run() {  # id cmd...
  local id="$1"; shift
  nsys profile -t cuda,nvtx,osrt --sample=none -f true -o "$OUT/$id" "$@" < /dev/null > "$OUT/$id.console.log" 2>&1
  if [[ -f "$OUT/$id.nsys-rep" ]]; then
    S=$(sha256sum "$OUT/$id.nsys-rep" | cut -d' ' -f1)
    echo "$id trace ok sha256=$S"
  else
    echo "$id FAILED"; fi
}

# --- port 基准 4 张（每张单路径，4 rank 同 rep）---
P=/root/second_nvidia/phaseb-nvidia-port/ag_gemm_phaseb_nv
nsys_run "01_d0_N2048_q8_串行称王" timeout 180 mpirun --allow-run-as-root --bind-to none -np 4 -mca coll ^hcoll $P --path d0 --m-local 2048 --n 2048 --k 2048 --q 8 --warmup 5 --iters 10 --verify-every 1 --output-dir /tmp/nsysf/01 --run-id f01
nsys_run "02_r1_N2048_q8_重叠输家" timeout 180 mpirun --allow-run-as-root --bind-to none -np 4 -mca coll ^hcoll $P --path r1 --m-local 2048 --n 2048 --k 2048 --q 8 --warmup 5 --iters 10 --verify-every 1 --output-dir /tmp/nsysf/02 --run-id f02
nsys_run "03_r1_N512_q8_重叠赢家" timeout 180 mpirun --allow-run-as-root --bind-to none -np 4 -mca coll ^hcoll $P --path r1 --m-local 2048 --n 512 --k 2048 --q 8 --warmup 5 --iters 10 --verify-every 1 --output-dir /tmp/nsysf/03 --run-id f03
nsys_run "04_d1_N4096_q8_gating病理" timeout 180 mpirun --allow-run-as-root --bind-to none -np 4 -mca coll ^hcoll $P --path d1 --m-local 2048 --n 4096 --k 2048 --q 8 --warmup 5 --iters 10 --verify-every 1 --output-dir /tmp/nsysf/04 --run-id f04

# --- 核心矩阵 w 轴 3 张（B0/B1/B2 三策略同 rep，q16 S1）---
B=/root/second_nvidia/ag-gemm-bench/build/ag_gemm_bench
for W in 0 1 8; do
  nsys_run "0${W}_w${W}_S1_q16_窗口轴" timeout 180 mpirun --allow-run-as-root --bind-to none -np 4 $B --local-rows 4096 --k 512 --n 512 --q 16 --window $W --warmup 5 --iterations 10 --run-id fw$W --output-dir /tmp/nsysf/w$W
done
# 修 manifest 名
ls "$OUT"/*.nsys-rep | while read f; do echo "rep,$(basename $f),$(sha256sum $f | cut -d' ' -f1)" >> "$MANIFEST"; done
echo "done: $MANIFEST"
