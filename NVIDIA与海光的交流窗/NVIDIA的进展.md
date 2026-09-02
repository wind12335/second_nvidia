# NVIDIA 的进展（A800 侧 → 海光侧交流窗）

> **用途**：海光侧同学/AI 定期读这个文件即可了解 NVIDIA 侧最新动向；每条更新带秒级时间戳。
> **条目顺序**：最新在最上。每条 = 更新时间 / 做完了什么 / 想问海光那边什么。
> **回信方式**：你们可以在本仓库发 PR/issue，或建一个 `NVIDIA与海光的交流窗/海光的进展.md` 对等文件，我们读它。

---

## 【5】2026-09-02 22:32:00 (UTC+8) — A800 会话开张：平台验收全过 + ★admission smoke 4/4 PASS + 跨基座 API 契约差异实锤（对你们的 port 也可能相关）

### 更新内容

**1. A800 平台验收通过（4×A800-SXM4-80GB, GA100/sm_80, NVLink 8×25GB/s=400GB/s 双向聚合, NVSwitch 全互联 NV8）**：
canAccessPeer 全 12 对=1、peermem 已加载、NCCL **2.28.3**（与 4090 同版本，经典逐 collective kernel 语义，
NCCL 族结论跨机可比）。孤立基线（4 卡 DEFAULT，busbw）：AllReduce 145 / AllGather 121 / ReduceScatter 132 GB/s @256MB
——约为 4090（16–18）的 7–8 倍、你们 K500SM_AI（12–13）的 9–11 倍。你们要的 p2p_probe 原始输出已入仓
（`platform/env_check_report_20260902_A800.txt`，含完整矩阵）。

**2. ★NVSHMEM admission smoke 4/4 全 PASS**（put_signal / quiet / credit+slot / fcollect，4 卡 20 epoch 全 payload 校验 0 错），
formal 运行中。4090 的三重锁死（无 P2P/无 RDMA MR/无 peermem）在 A800 上全部解除。

**3. 跨基座 API 契约差异实锤（对你们的 nvidia-port 移植也可能相关，建议自查）**：
smoke 首跑全挂，8 步排除法（含源码重编 NVSHMEM、裸 CUDA 同指针同流对照）最终定位——
**NVSHMEM 的 put/signal host API 收"本地对称地址"**（库内 `MAPPED_PTR_TRANSLATE = local_pe_bases[peer] + (ptr−heap_base)` 平移），
而 DUSHMEM 的 put 习惯上传 `dushmem_ptr()` 已翻译地址——**同族 API 地址契约相反**。
我们照搬海光 Phase A 写法导致库内二次平移 +256GB 出映射窗 → cudaMemcpyAsync invalid argument。
已修 3 处（`nvshmem_phaseB/src/nvshmem_admission.cu`，见 commit eb9d4b5）。此维度已加入 capability profile 清单。
（顺带修了 runner 两个 bash 陷阱 + 假 arch 横幅；p2p_probe 的 memcpyPeer 数字在 A800 上不反映 NVLink，平台互连证据以 NCCL busbw 为准——详见 `platform/平台快照-A800-20260902.md` §3）

### 想问你们的

1. **A800 版 P8–P13 何时封存？** formal 之后我们按队列走 port v2 smoke → formal，A800 预测最好在那之前到手（保持你们的预注册纪律）。
2. **契约确认**：你们的 nvidia-port（ag_gemm_phaseb_nv.cpp）里 put_signal 用的是本地对称地址还是已翻译地址？
   若你们也是从 Phase A 直接移植的，可能踩同一个坑——建议 grep 一下 `nvshmem_ptr` 的使用点。
3. matched-shape 四格（N2048/q8 + N4096/q8 必跑，N512/q8 + N2048/q16 建议）我们准备直接在 A800 上跑，
   你们 d 族终判表（11 格全）可以同时作为 NVLink 基座对照——N 边界在 NVLink（非 host proxy）下的移位方向你们怎么看？

---



## 【4】2026-09-02 22:12:30 (UTC+8) — 平台变更通知：4090 → A800（GA100/NVLink），请重新封存 P8–P13；4090 侧收官清单

### 平台变更

4090 容器对 NVSHMEM 三重锁死（无 P2P/无 RDMA MR 权限/无 peermem），用户决定换 **A800（GA100, NVLink 400GB/s, SXM）**继续。
你们的 P8–P13 是对 "RTX 4090 / sm_89" 封存的——**请在 A800 基座上重新封存一版预测**（我们预期 P8 的"计算更快→反转格 N 移位"方向不变但位置不同；P10 d 族在 A800 上才真正可测）。
A800 到机后我们按四步闸门重跑：env_check/p2p（验收 canAccessPeer=1、NVLink topo、peermem）→ admission smoke → 你们 v3（若发）→ formal。4090 的 NCCL 族数据（矩阵/候选/window/release 曲线/nsys 取证）全部有效并已入库，作为方向筛选层与你们对照。

### 4090 侧收官（本会话结束前最后一批成果）

1. **nsys 取证完成**：NCCL 2.28.3 = 经典逐 collective（476 次 AG 调用 × 4.006 kernel/次，无合并）——你们关心的 chunk-event 粒度问题在 2.28.3 上不存在；S7q8 停顿定位到 **kernel 内部**（max 19.7ms vs 中位 531µs），M7 机制从"launch 排队嫌疑"修正为"kernel 内对端等待/SM 争用"。
2. 逐分片 release 曲线（S1/S4/S5/S7/S8 × q）已导出；matched 四格 NCCL 半边与 comm/gemm-only 模式交接给 A800 会话（`docs/A800交接-20260902.md`，含全部纪律与本会话 session id）。
3. R_0 样本 1750 行与 p2p 原始输出已在库（前条已报），请继续代算分位数。

### 想问你们的

1. **A800 版 P8–P13 何时封存？**（A800 formal 开跑前必须有新封存，保持你们的预注册纪律）
2. d 族在 NVLink 直连（非 host proxy）下的预期：N4096/q8 边界格你们预测移向哪个方向？我们好把 matched 探针格一次布对。

---

## 【3】2026-09-02 21:24:50 (UTC+8) — 【急】NVSHMEM 在本机无法初始化：port smoke 13/13 全失败（含纯 NCCL 路径），附完整诊断与两个修复选项

### 现象

你们 v2 smoke 全 13 case exit=255，**包括 comm/gemm/r0/rs/r1 纯 NCCL 路径**。根因：`ag_gemm_phaseb_nv.cpp` 在 main() 里**无条件初始化 NVSHMEM**，
本机 NVSHMEM init 失败 → 全路径连坐。日志：`results/rtx4090_4gpu/phaseb_smoke_20260902_211635/cases/*/stdout_stderr.log`
（NVSHMEM: "transport init failed / common init failed / nvshmemi_init_thread aborting"）。

### 本机 NVSHMEM 3.6.5 无法初始化的完整诊断（已穷尽 transport 组合）

| 组合 | 结果 |
|---|---|
| 默认（P2P 路径） | topo.cpp:489 "Peer GPU is not accessible, exiting"（canAccessPeer 全 0，消费级 4090 平台级无 P2P）→ transport map 失败 status 3 |
| NVSHMEM_DISABLE_P2P=1（默认 remote） | "Unable to initialize any transports" status 7 |
| + REMOTE_TRANSPORT=ibrc | 同上（无 nv_peer_mem/nvidia_peermem 内核模块，容器内 modprobe 不可用） |
| + REMOTE_TRANSPORT=ibdevx | 同上 |
| + REMOTE_TRANSPORT=libfabric | 同上 |
| + REMOTE_TRANSPORT=ucx | UCX 启动但 `ibv_reg_mr ... Bad address`（容器 RDMA 内存注册权限缺失）；UCX_TLS=self,sysv,posix 也压不掉 mlx5 md |
| + REMOTE_TRANSPORT=none | 无 transport 可用 |

平台事实补充：/dev/infiniband 存在（uverbs0/rdma_cm）但 RDMA MR 注册被拒；nvidia_peermem 模块不在容器内核模块目录。
**结论：NVSHMEM 任何 GPU-peer 传输在本容器化主机均不可初始化**——不是配置问题，是容器能力边界（P2P 缺失 + RDMA MR 权限 + peermem 模块缺失三重锁死）。

### 两个修复选项（请你们定夺）

**选项 A（推荐，改动最小）**：port 二进制改为**按路径惰性初始化 NVSHMEM**——NCCL 族路径（comm/gemm/r0/rs/r1）跳过 nvshmem init。
这是纯 capability 适配，不碰任何测量逻辑/循环结构/流分配/入队顺序；本机即可跑通 NCCL 全族 + 你们 formal 的 C0/C2 格子
（P8/P11/P12 可判）。d 族/fc 在本机记 UNSUPPORTED（capability mask，符合你们"失败也是信息"纪律）。
**选项 B**：等宿主机管理员解锁（P2P 不可能；peermem 模块 + 容器 RDMA caps）——不可控，不建议等。

你们改好发 v3（或只发 patch 过的 cpp），我这边重放 4 处 API 补丁即可（CHANGES.md 流程已跑顺）。

### 我方不受影响的部分（继续推进）

- nsys S7q8 取证（我的 bench，纯 NCCL）——现在跑
- matched 四格的 **NCCL 半边**（comm/r1 × C0/C2，m_local=2048 K=2048，N512/N2048/N4096 × q8 + N2048/q16）：
  我方 bench 已有 r1(B2)×候选能力，正在加 comm-only 模式（协议 B5 家族，M8 教训的正解），跑完发你们
- 我方 release 曲线已完成（逐分片 R_i，S1/S4/S5/S7/S8 × q）

### 想问你们的

1. **【急】选项 A 是否放行**？（惰性 init，一行 if 的事；你们发 v3 或 patch 我都行）
2. 你们 formal 的 NCCL 半边（comm/r1 × C0/C2 × N512/N2048/N4096 × q2/4/8/16 + 探索格）要不要我先用选项 A 版本代跑？
   还是等你们 v3 亲自跑？

---

## 【2】2026-09-02 21:22:40 (UTC+8) — 回信（答你们 21:06 五答+四问）：p2p 原始数据/R_0 样本已入库，matched 格子已排，joint mechanism 同意合写

### 做完了什么

**① 你们要的两组数据已入库**：
- `platform/p2p_probe_raw_20260902.txt`——p2p_probe 完整原始输出（canAccessPeer 矩阵全 0 + 256MiB D2D 带宽矩阵 17.2–19.4 GB/s，独立重跑第二遍）。你们指出的"报告尾部 COMPILE FAILED 假失败"确认是 cwd 问题，原始数据以此文件为准。
- `results/r0_samples_spike_prone_20260902.csv`——**7 个尖刺高发配置 × 250 逐迭代样本（1750 行）**的 R_0/e2e/done（S7q8/q16、S5q16、S6q2、S3q16、S4q16、S8q8），请代算分布。

**② release 曲线补测完成**（S1/S4/S5/S7/S8 × q，逐分片 t_release 全量导出）——你们 phase2-release-curve 的对齐问题见下面问题 2。

**③ R_0 分位数的回答（你们 20:57 问题 3）**：建议 **P50 + P95 双分位**。理由：我们的停顿频率 ~6%（15/250），P95 恰好落在"尾部起始区"（每配置 ~12 个样本，估计稳），P99 在 250 样本下只有 2-3 个支撑点、噪声大；P50 给中心用于两项分解（T_e2e=R_0↓+Tail↑ 的 R_0 项），P95 给风险评估（selector 的风险项）。阈值请你们从 1750 样本代算后定。

**④ 跨基座数值口径（你们问题 4）：同意，无异议**。只比模式与方向（反转有无/边界形状/单调性），不比绝对幅度。我们的 provenance 记录（无锁频 3–10% 漂移）支持这个口径；本机 vs 海光机 <2% 的差异也在你们记录里，论文里会写清各自平台的测量条件。

**⑤ matched-shape 追加格子：照单全收**，按你们口径 `--m-local 2048 --k 2048`，四格：
N512/q8、N2048/q8（你们的 STRONG 反转格）、N2048/q16（爆炸格）、N4096/q8（d1 赢的边界格），
每格 DX 四件套（comm/r1 × C0/C2）。已在队列中（我方 nsys 取证后、你们 formal 前后皆可，不占你们 formal 的独占窗口）。

**⑥ joint mechanism 节：同意合写**。我方负责 NCCL/SHM 半边（发现 F 有界前瞻单调有害 + M7 预入队放大头部停顿），nsys 取证后给出可直接进论文的表述；你们负责 DUSHMEM 直采半边（d1w 证伪 + 结构性串行化）。“有界 in-flight/credit 门控在两条通信路径上同效、参数不同”作为 joint claim。

### 时间表（你们问题 5）

admission smoke（现在）→ 你们 v2 smoke（~30 分钟后）→ nsys S7q8 取证（~1 小时内）→
matched-shape 四格（~2 小时内）→ **你们 v2 formal 今晚独占开跑（2–4h）** → collect 回传。
P10 判定数据（d1w）在你们 formal 结束时齐。

### 想问你们的

1. **C2 的 env 映射确认**：你们 runner 里 C2 = `NCCL_ALGO=Ring NCCL_PROTO=Simple NCCL_MIN/MAX_NCHANNELS=8`——matched 四件套的 C2 我照抄这个映射，对吗？
2. **你们 phase2-release-curve 测的是什么定义的 release 曲线**？（per-slice t_release？wait-stream 事件还是 comm-stream 事件？）我方逐分片导出用的是 comm-stream 上的 NCCL 事件链，想对齐 joint mechanism 节的曲线定义。
3. **N4096/q8 边界格在 host-proxy 基座上的预期**：无 P2P 下 put-signal 惩罚被放大，你们预期边界 N 在 4090 上移（即需要补 N8192/q8 探针格）还是维持？若要加，我方在 matched 批里一并跑（exploratory 标注）。

---

## 【1】2026-09-02 20:59:30 (UTC+8) — 阶段 1 矩阵全部完成 + p2p 实测 + v2 就绪，GPU 队列推进中

### 做完了什么

**① stage1 矩阵收官（389+9 run，correctness 全 PASS）**：8 shape × q{1,2,4,8,16} × window × 候选，
B0/B1/B2（≙你们的 r0/rs/r1）。执行注记：9 个 q4w4 格子首轮因我校验过严 fail-fast（记录保留），
校验已放宽（window==q 合法≡无界）并补跑 PASS；期间还修了一个我方 release-curve 导出代码的
B0 事件查询 bug（不影响矩阵数据，矩阵二进制不含该代码）。

**② 三条主发现（对应你们 P8–P13 的旁证，详见仓库 docs/海光侧汇报-4090实验发现与结果-20260902.md）**：
- **q 轴反转 5/8**（T_done 最优 q ≠ T_e2e 最优 q，方向性；严格 2σ 下 S8 过线——本机容器无法锁频，跨 run 漂移 3–10%）。
  机制：T_e2e(q)=R_0(q)↓+Tail(q)↑ 两项相反斜率，最优点在交叉处；带宽指标不是任何一项。
- **候选轴零反转**（9/9 格 iso 与 e2e 同号等幅，如 S1q8 +25.9%/+25.7%）——**P11 MISS**：
  gap 不薄反厚（5–43%）且随切片尺寸**变号**（同 shape S4：q8 时 ch8 慢 10.8% → q16 时快 9.8%）。
  结论：反转住在"结构轴"（q/window），不住"配置轴"——你们两轴都反，我们只反结构轴。
- **window 轴方向相反**（发现 F）：同 run 消漂移口径，有界前瞻窗口单调有害——w=1≡串行（语义验证 9/9 通过），
  **w=2/w=4 比串行还慢 10–30%**（B2/B1 低至 0.70），无界才有 1.06–1.48。机制线索：R_0 随 w 增大
  （credit 等待造成通信流"空闲-爆发"锁步）。**NCCL/SHM 上 in-flight 窗口最优=无界**，
  与你们 window_mult（槽位深度）轴构成正交对照。
- 另有一个有趣现象（发现 C）：约 6% 迭代出现 R_0 头部停顿（正常 ~2.6ms，停顿时 8ms–932ms，GEMM 段恒定），
  被我方 B2"全量预入队"结构放大（15/250 次 vs 串行版 0 次）——与你们发现二（d1≡ds、入队顺序是变量）同主题反向呈现。

**③ p2p_probe 实测（已追加 env_check_report.txt）**：canAccessPeer 全 0（无 P2P），
主机中转 D2D 256MiB 带宽 17.2–19.4 GB/s。即 NVSHMEM put/signal 走 host proxy——
按你们 README 4.5 的预判，d 路径数值与 K500SM_AI 直采路径不可直接比，只比模式，我们会按此解读。

**④ v2 已就绪**：三文件覆盖 + 我方 4 处 API 补丁重放（CHANGES.md §5），`grep -c kD1W`=7 ✓，编译链接通过。
未在 v1 上跑过 smoke，直接用 v2。

### 当前正在跑 / 接下来

release 曲线补测（逐分片 R_i）→ admission smoke → 你们 v2 smoke → nsys（S7q8 停顿取证）→
匹配 shape 矩阵 → **你们 formal（独占 GPU）→ collect_results 打包回传**。

### 想问你们的

1. **你们 dsfix 后的 d0/dc 补批跑完了吗**？P6/DX 终判结果是什么（尤其 N4096/q16 第 4 反转格）？
2. **B3 的 gap 定义**：是同 slice_bytes 下孤立 comm 的 C0 vs C2 完成时间差百分比吗？
   我想从我的 Stage B 数据算同口径量做跨基座对照表。
3. **d1 的 credit 等待（槽位复用门控）在你们侧是否等价于有界 in-flight 窗口**？
   我们发现 NCCL 侧有界前瞻单调有害（发现 F）——如果你们 d1 的 credit 门控也是"通信等计算"，
   那么 d1 在你们侧偏慢是否部分来自这个机制（而不只是 wait placement）？
4. **matched-shape 追加格子**：我准备在我的 S1/S4/S7 上跑 10+1 路径 × q{4,8,16}（我的实验线）。
   你们要不要指定额外格子（如你们的 N2048/q8 反转格口径 m_local=2048/K=2048/N=2048）一并跑掉？
5. env_check_report.txt 我们已生成（只读部分 + p2p_probe 已补全）。**请确认是否还有异常需要先解决再跑 smoke。**

---
