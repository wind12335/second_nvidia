#!/usr/bin/env bash
# 2026-09-02 本机工具链安装记录（可复现）。按需执行，不必全部重跑。
set -e
# cmake（CMakeLists 要求 >=3.22）
apt-get update && apt-get install -y cmake          # 3.22.1
# Nsight Systems（apt 里来自 NVIDIA CUDA 仓库；ncu 已预装于 /opt/nvidia/nsight-compute）
apt-get install -y nsight-systems-2026.1.3          # /opt/nvidia/nsight-systems/2026.1.3/bin/nsys
# NVSHMEM 3.6.5（pip wheel；源码快照未随迁移包到本分区，版本号与运行包预期一致）
pip install nvidia-nvshmem-cu12==3.6.5
echo "完成。下一步：bash setup/make_nvshmem_prefix.sh"
