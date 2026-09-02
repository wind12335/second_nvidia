# 平台快照补充（2026-09-02 会话，阶段 1 执行时点）

## 与核对清单/历史快照的差异
1. 拓扑变化：核对项 2 记载历史为 "GPU0/1 NUMA0、GPU2/3 NUMA1"；实测（nvidia-smi topo -m）为
   GPU0=NUMA2(cores 16-23,80-87), GPU1=NUMA0(0-7,64-71), GPU2=NUMA7(56-63,120-127), GPU3=NUMA6(48-55,112-119)，
   全部 GPU 对为 SYS（跨 NUMA/UPI），无 PIX/PXB/NVLink，NIC0=mlx5_bond_0（单节点实验未使用）。
2. 锁频受限：容器内 root 无 GPU 时钟管理权限（nvidia-smi -lgc 2100 被拒）。
   缓解：协议自带 20 warmup + 50 timed × ≥3 独立 process run + p95 报告。
   GPU 空闲基线 24-25C、P8、210/405MHz；最大 SM 3105MHz、显存 10501MHz（clocks_before.txt）。
3. NCCL：系统库 /usr/lib/x86_64-linux-gnu/libnccl.so.2.28.3（CUDA 13.0 构建）；
   ldd build/ag_gemm_bench → libnccl.so.2 → 2.28.3；运行日志 NCCL INFO 版本行 = 2.28.3+cuda13.0。
   核对项 1 结论：既非 2.30.x 亦非 v3.6.5-dev，为经典 2.x 逐 collective kernel 语义
   （v3.x 常驻 kernel/workFIFO 合并风险不适用；chunk-event 粒度仍以 nsys trace 为准）。
4. 工具链：nvcc 12.6.85（/usr/local/cuda），OpenMPI 4.1.2，cmake 3.22.1（apt 安装），
   Nsight Systems 2026.1.3（apt CUDA 仓库安装），Nsight Compute 2024.3.2（/opt/nvidia 预装）。
5. transport（2 卡 preflight 实测，NCCL INFO）：Channel 0/1 via SHM/direct/direct，
   2 coll channels + 2 p2p channels/peer，P2P Chunksize 131072。4 卡矩阵 rep1 的 NCCL 日志待并入。
6. /root/comm-study 不存在（NVSHMEM/NCCL 源码快照未随迁移包带到本分区）。
   phaseB 改用 NVIDIA 官方 pip wheel nvidia-nvshmem-cu12==3.6.5
   （site-packages/nvidia/nvshmem，libnvshmem_host.so.3 + libnvshmem_device.a + bootstrap_mpi 插件），
   与运行包预期的 v3.6.5-469 源码快照同版本号、二进制发行形态；已在 nvshmem-3.6.5-wheel/ 下做符号链接+CMake shim。
7. torch 不在本环境（协议 §4.1 的 torch 版本行记为不适用）。
