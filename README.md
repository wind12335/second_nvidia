# second_nvidia — 第二篇论文 NVIDIA(RTX 4090) 侧实验套件

异构 GPU 通信基座上的**依赖释放感知 Collective-GEMM 重叠**（H1：孤立带宽最优 ≠ 端到端最优）。
本仓库是 4090 分区（4× RTX 4090, sm_89, driver 580.65.06, CUDA 12.6）上跑的完整实验线，
海光侧（K500SM_AI/gfx928）对照仓库由对方维护，CSV/CLI 口径与海光版一致，可合并分析。

## 目录

| 目录 | 内容 | 状态 |
|---|---|---|
| `ag-gemm-bench/` | 阶段 1 主基准：B0/B1/B2 三策略 AG-GEMM（NCCL 事件管道），含 `--window`（credit 前瞻窗口）与 `--dump-release-curve`（逐分片 R_i 导出）扩展 | 389-run 矩阵已跑，代码+脚本可复现 |
| `nvshmem_phaseB/` | NVSHMEM 消费语义准入微基准（epoch signal + credit 槽位 + 全 payload 校验） | 已构建待跑 |
| `phaseb-nvidia-port/` | 海光侧 10+1 路径统一基准的 NVIDIA 移植（v2 含 d1w）；`CHANGES.md` 记录本机 4 处 API 兼容补丁 | v2 已编译通过 |
| `platform/` | 平台事实快照（拓扑/时钟/NCCL 2.28.3 ldd 核对/provenance 补充） | 完整 |
| `results/` | 矩阵 run 清单、合并分析表（pivot/ranking/merged CSV）、S7q8 取证样本、preflight 汇总 | 持续更新 |
| `docs/` | 阶段 1 报告（机制分析 M1–M8）、数据地图、与海光侧的往来汇报 | 持续更新 |
| `setup/` | 工具链安装记录 + NVSHMEM wheel CMake shim 构造脚本 | 可复现 |

## 快速复现

```bash
bash setup/toolchain.sh                  # cmake/nsys/nvshmem wheel（已装可跳过）
bash setup/make_nvshmem_prefix.sh        # NVSHMEM wheel → CMake 前缀

# 阶段 1 主基准（2 卡门槛 → 4 卡矩阵）
cd ag-gemm-bench
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release && cmake --build build -j
mpirun --allow-run-as-root --bind-to none -np 2 ./build/ag_gemm_bench \
  --local-rows 128 --k 128 --n 128 --q 4 --window 2 --warmup 3 --iterations 5 \
  --run-id smoke --output-dir results/smoke      # 三策略须全 PASS
RANKS=4 WARMUP=20 ITERATIONS=50 REPETITIONS=5 bash scripts/run_stage1_full.sh
python3 scripts/merge_stage1_results.py results/stage1_<时间戳>

# 海光 10+1 路径基准（四步闸门：env_check → make → smoke → formal）
cd ../phaseb-nvidia-port
bash env_check.sh
make NVSHMEM_HOME=<prefix> NCCL_HOME=/usr MPI_HOME=/usr/lib/x86_64-linux-gnu/openmpi
bash run_phaseb_nv.sh smoke
```

## 平台事实速览（2026-09-02）

- 4× RTX 4090（无 P2P，全对 SYS 拓扑，4 卡分属 4 NUMA）；NCCL 系统库 **2.28.3**（经典 2.x 逐 collective kernel 语义）；transport = SHM/direct/direct。
- NVSHMEM = pip wheel 3.6.5（无源码快照）；容器内**无法锁频**→ 跨 run 均值漂移 3–10%，主结论一律用**同 run 内**比较（红线）。
- 详见 `platform/`。

## 数据纪律

- 每个 run 落独立时间戳目录，绝不覆盖；失败 case 原样保留。
- 逐迭代原始 CSV 与 NCCL 日志体积大，不入 git——完整原始数据在时间戳 tar 包
  （如 `rtx4090_results_partial_20260902T112630Z.tar.gz` + SHA256）；git 内保留清单、
  合并分析表与取证样本（`results/.../forensics_S7q8/`）。
- 红线：重叠收益只与同 q、同 GEMM partition 的 B1 串行基线比较；设备标签以实测快照为准；
  4090 数据不能替代 A100 最终验证。

## 关联

- 海光侧汇报与预注册预测（P8–P13）：`docs/NVIDIA侧汇报_海光发现与执行说明_20260902.md`
- 本侧发现汇报（回传海光）：`docs/海光侧汇报-4090实验发现与结果-20260902.md`
