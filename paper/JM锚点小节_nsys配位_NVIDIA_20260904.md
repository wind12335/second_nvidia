# JM 锚点小节 — NVIDIA nsys 配位稿 v2（2026-09-04）

> **状态**：配位稿 **v2**。v1 的全部跨 device 数字作废（v1 提取未按 device 分组，跨 rank 配对污染——Sol① 内审发现，复算确认），本稿为 device 内（rank 0）口径重算；梯子/重叠/覆盖数字已换血，锚点配位与叙事结构不变。H8 下界更新为 P21 终判。paper 级 NVTX/迭代对齐提取仍 pending（见 §2 口径）。
> **取证纪律**：7 trace 于 2026-09-03 采样，权威哈希清单 `work-20260903/nsys取证/manifest-canonical-20260904.csv`（旧 manifest 有重复行事故，见同目录事故说明）；本稿数字由脚本 v2 从封存 trace 提取（`docs/nsys锚点提取_20260904/`，schema v2），不重跑。

---

## 1. Trace 清单与配位（v2 不变，双挂按内审收敛）

| trace | 配位（主/次） | 一句话证据（device 0 口径） |
|---|---|---|
| 01_d0_N2048_q8_串行称王 | **H3**(d0 档) / H7 | 每卡 16 次整块 sgemm_128x64 + 24 次 NCCL：AG 完成→整块 GEMM 的稳态 gap 即 d0 档 |
| 02_r1_N2048_q8_重叠输家 | **H4** / H7 | 每卡 121 片 sgemm(495µs) + 129 次 AG LL(p50 108µs/尖刺 1.2ms)；重叠覆盖仅 10.7% |
| 03_r1_N512_q8_重叠赢家 | **H7**(正例) / H4 对照 | 同构 121+129，片算 162µs；重叠覆盖 37.5%——重叠收益到手的 kernel 级正例 |
| 04_d1_N4096_q8_gating病理 | **H4** / H2（H2 仅作 API/源码联合证据，内审定） | trace 直接可见消费流执行路径上的长驻 barrier kernel（逐 rank 尾 0.34–13.1ms 不对称）；结合 API/源码 contract 与 wait-induced blocking **一致**——不主张 trace 单独证明 legal release 或特定远端 notification |
| 00_w0/01_w1/08_w8（S1/q16） | **H5**(主) / H2（仅概念旁引，内审定） | 每卡 496×496；GEMM 被并发 NCCL 覆盖 **w0 18.7% / w1 0.0% / w8 18.7%**——害区并发完全归零、w8 回到平台线 |

## 2. JM-H3 梯子：A800 侧整体标 proxy / pending re-extraction（内审终判）

**口径（v2.1）**：下表为 device 0 内的**描述性审计数**（稳态 <5ms 过滤——注意该阈值系事后设定，属审计清洗而非结构化排除）。**不作为梯子估计**：配对语义未证明（无法确认哪个 AG kernel 对应哪片 GEMM），p10 无预注册 mixture 语义。按内审 B4 规则重提（(globalPid,deviceId) 分层、NVTX/迭代对齐、结构化排除 warmup/验证/轮界、阈值敏感性报告、per-device 范围报告）前，H3 A800 行统一标：

> **proxy/pending re-extraction**: kernel timelines show coarse serial and fine-grained pipelined regimes, but the release-to-consume latency ladder is not yet directly identified on A800.

| 档位 | 来源 | device 0 审计数（非梯子值） | 状态 |
|---|---|---|---|
| d0 档 | 01_d0（稳态 15 对；每卡 24 NCCL/16 GEMM，非一一对应） | p50 14.2µs / p10 13.2 / p90 15.2 | proxy，待 NVTX 对齐 |
| r1 档 | 02/03（各 128 稳态对；p10 与 p50 双峰生成机制未解释，不得同时当梯子值与锁步值用） | 快端 p10 16.8/14.0µs；p50 514.7/159.5µs（另作 H4 串行化证据） | proxy，待 NVTX 对齐 |
| d1 档 | 04（稳态配对仅 1 对） | 不可提取 | **维持 K500 derived 5.4µs** |

## 3. JM-H4 逐片税的 A800 直接证据（device 0）

- **输赢格同构对照**（121 片 GEMM + 129 AG，AG/片≈1.07）：
  - 输家 N2048/q8：每片 AG_LL p50 108µs（尖刺 max **1,211µs**）vs 片算 495µs；GEMM 被并发 NCCL 覆盖 **10.7%**；AG-end→下片 GEMM p50 514.7µs ≈ 片算时长——实质交替串行；
  - 赢家 N512/q8：AG p50 99µs vs 片算 162µs，覆盖 **37.5%**（3.5×）——税算相对大小随 N 翻转并发结构。
- **d1 握手税尾巴（rank 不对称）**：barrier_on_stream 每 rank 34 次，p50 7.8–15.3µs，**max 逐 rank 0.34 / 9.0 / 8.2 / 13.1ms**——等远端停顿的重尾分布因 rank 而异（本身值得一句：d1 的税不是常数尾，是结构性的 rank 依赖等待）。v1 的"13ms 尖刺"实为 dev3 现象，纠正于此。
- **与 K500 控制量互不冲突**：K500 3938+38.1·q µs 为 RCCL 分解拟合；A800 为 NCCL LL 尖刺 + barrier 重尾。共用 D2 结构律，不做跨基座数值合并。

## 4. JM-H5 害区的 kernel 级对照组（w 三连，各 496×496，device 0）

| 指标 | w0 | w1（害区，q16 下 w=1） | w8（**半轮**：8/16，v1 误写 ≥1 轮，纠正） |
|---|---|---|---|
| GEMM 时长被并发 NCCL 覆盖 | 18.74% | **0.00%（完全串行化）** | **18.65%（回到平台线，Δ0.1pt）** |
| 每 AG_LL p50 | ~47µs | ~45µs | ~47µs |

- 读数 1：**害区不是"变慢"而是"并发归零"**——rank 0 上 w1 的通信与计算零重叠，严格锁步；
- 读数 2：**深度不改单次操作成本**（AG p50 三者持平），只改流水结构——H5"阈值变量非旋钮"的 kernel 级版；
- e2e 侧口径更新：以 **P24 终判（93/93，w\*=4）**为准；v1 所引"w1/w2 慢 30–40%、w8 才恢复"为早期口径，**作废删除**（内审第 12 条）。恢复点记 w\*=4（q8=半轮；q16 下 w8 已是半轮）。

## 5. JM-H7 消费时刻

7 trace 的 kernel 起止（每片/每块 GEMM start）即 actual-consume 直接锚定；03 赢家格（覆盖 37.5%）为正例首图候选。迭代对齐版待 NVTX 重提（与 §2 同批）。

## 6. 不主张（与海光侧 §4 一致）

S2→S3 中间段无新直接证据，维持显式 pending；admission 47µs 地板仍为 derived 换算桥。

## 7. 图位认领

F-JM3（梯子+首片推迟）我方出图，**须等 corrected table（B4 重提取）后用 paper 级数字**；F-JM4 谱系图 A800 柱用 P21 终判值；F-JM1/2 海光侧。**图注纪律**：A800 +16.5（N8192/q16）系早期 matched/formal 证据、非 P19/P21 随机区组 cell，图注须注明；P19/P21 大 N 结果仅支撑"远侧无过零"区域注释。kernel 计数一律写"aggregate across four ranks, one representative sealed trace per cell"，不写独立样本数。

## 8. H8 行我方勘误（供海光 v2 采纳）

1. **下界更新**：P21 终判（45/45，区组随机化）bracketing 扩至 **N\*(q8)>32768、N\*(q16)>65536**（均 RIGHT-CENSORED；四新格全 POSITIVE-LOWER-BOUND，(N,q) 非单调幅度收敛型）。P19 的 16384/32768 下界由 P21 取代。
2. **"四数同格"改口**：observed points 实为 **三个**（K500 / A800 / BW1000-np8），BW1000-np4 缺格——表述改 "three anchors + one missing config"，不写四数。
3. A800 行口径：**非单调 + finite-N\* No-Go**（P21 后 N\* 仍无过零证据但有限界收缩中），interaction 外推删除维持。

## 9. 可复现性与 v1→v2 差异

- 脚本 v2 + 全量 JSON：`docs/nsys锚点提取_20260904/`（schema v2；sqlite 可由封存 trace 重生成，不入 git）。
- v1→v2 作废清单：d0 p50 10.5→**14.2µs**；r1 快耦合 15.8/11.5→**16.8/14.0µs**；输赢覆盖 3.4/12.1%→**10.7/37.5%**；w 覆盖 10.7/3.2/11.3%→**18.7/0.0/18.7%**；barrier max 13.1ms→**逐 rank 0.34–13.1ms**；kernel 计数 64/480/516/1984 系跨 device 总数，改为每卡 16/121/129/496。
- 根因：v1 未按 device 分组（Sol① 内审第 1–5 条），跨 rank 配对污染 gap 与 overlap。
