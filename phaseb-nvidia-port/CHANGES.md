# CHANGES（NVIDIA 侧 4090 机执行 AI 记录，2026-09-02）

按【对话词 2】的规则：只动 API/构建兼容性，未改任何测量逻辑、事件打点、CSV 输出、CLI。

## 1. Makefile：RPATHS 链接标志
- 原：`RPATHS = -Wl,-rpath,$(dir) ...`
- 改：`-Xlinker -rpath -Xlinker $(dir)`（foreach 生成）
- 原因：nvcc 前端不透传 `-Wl,` 形式，直接 fatal "Unknown option"。

## 2. Makefile：CXX_FLAGS 增加 `-x cu`
- 原因：源文件后缀 .cpp 但含 `<<<>>>` kernel 启动语法；hipcc 接受、nvcc 默认按主机 C++ 解析报错。`-x cu` 强制按 CUDA 编译，零源码改动。

## 3. ag_gemm_phaseb_nv.cpp:178  device signal API
- 原：`nvshmem_uint64_signal(dest, value, pe);`
- 改：`nvshmemx_signal_op(dest, value, NVSHMEM_SIGNAL_SET, pe);`
- 原因：NVSHMEM 3.x 移除了 2.x 的 typed device signal；3.6.5 头文件（pip wheel nvidia-nvshmem-cu12==3.6.5，include/device/nvshmemx_defines.h:35）提供 `nvshmemx_signal_op`。语义等价（SET 操作），流序保持不变（仍由 kernel launch 在 compute_stream 上保序）。正是 README 风险 4.2 的复核点。

## 4. ag_gemm_phaseb_nv.cpp:337-345  init_attr 布局
- 原：`nvshmemx_init_attr_options_t init_options; init_options.mpi_comm=...; init_attr.options=&init_options;`
- 改：`init_attr.mpi_comm = &mpi_world;`（直接成员）
- 原因：3.6.5 的 `nvshmemx_init_attr_t`（=v2，device_host/nvshmem_types.h:280-290）`mpi_comm` 为直接成员，无 options 间接层（该布局是 DUSHMEM 侧习惯）。NVSHMEMX_INIT_WITH_MPI_COMM 语义不变。

## 环境事实（供 DCU 侧判断）
- NVSHMEM：pip wheel 3.6.5（源码快照未随迁移到本分区）；`nvshmemx_fcollectmem_on_stream` 在 3.6.5 存在并已通过编译——README 风险 4.3 的头号嫌疑在本版本不成立，无需备选 A/B。
- NCCL：系统库 2.28.3（libnccl.so.2.28.3，CUDA 13.0 构建），nvcc 12.6.85 编译链接通过。
- 机器：4× RTX 4090 sm_89，driver 580.65.06，全 GPU 对 SYS 拓扑（无 PIX/PXB/NVLink），p2p_probe 结果见 env_check_report.txt（矩阵跑完后补跑）。
- 构建命令：`make NVSHMEM_HOME=<wheel-shim-prefix> NCCL_HOME=/usr MPI_HOME=/usr/lib/x86_64-linux-gnu/openmpi`
- 二进制 ldd：libnvshmem_host.so.3（wheel）、libnccl.so.2（系统 2.28.3）、libmpi.so.40 均解析正常。

## 5. v2 升级记录（2026-09-02 晚）
- 收到 phaseb_nvidia_port_20260902_v2.tar.gz，按海光侧说明覆盖解压三个文件
  （ag_gemm_phaseb_nv.cpp 新增 d1w/D1W_WAITSTREAM_OVERLAP、run_phaseb_nv.sh 加入 d1w 与探索格、analyze_phaseb.py 认 d1w）。
- 验证：`grep -c kD1W ag_gemm_phaseb_nv.cpp` = 7 ✓（与海光侧截图要求一致）。
- 上面 §3/§4 两处 API 补丁在 v2 源码上原样重放（v2 仍用 2.x 的 nvshmem_uint64_signal 与 options 间接层；
  本机 Makefile 保留 -x cu 与 -Xlinker rpath 修复，v2 的 Makefile 与 v1 相同未含此修复）。
- v1 已打补丁版本备份为 ag_gemm_phaseb_nv.cpp.v1patched.bak；make clean && make 重编通过，ldd 正常。
- 未在 v1 上跑过 smoke，按说明直接用 v2 跑，无需重跑。
