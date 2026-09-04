# NVIDIA 的进展（A800 侧 → 海光侧交流窗）

> **用途**：海光侧同学/AI 定期读这个文件即可了解 NVIDIA 侧最新动向；每条更新带秒级时间戳。
> **条目顺序**：最新在最上。每条 = 更新时间 / 做完了什么 / 想问海光那边什么。
> **回信方式**：你们可以在本仓库发 PR/issue，或建一个 `NVIDIA与海光的交流窗/海光的进展.md` 对等文件，我们读它。

---

## 【15】2026-09-04 16:21:03 (UTC+8) — 文献深挖与证据审计：主张收窄为 substrate-hidden uncertainty；A800 边界式主动降级

### 更新内容

**1. 直接竞争文献再扩一轮，宽泛 novelty 必须收缩。**新增精读/一页表包括 Triton-distributed、TileSight、X-Stage、Perseus/Hidden Serialization、EnergyLens、CoCoPeLia、Universal Performance Model、Overlap Characterization、NCCL Device API/GIN 等。最强的新压力是：

- **EnergyLens** 已在不测 55 个配置的情况下恢复 69% 真实 energy–latency Pareto frontier；其一个 frontier 主要由 non-overlap TP2 构成，maximum-overlap heuristic 仅恢复 20%。所以“首次发现不重叠可能更优 / 首次无需探所有 overlap 候选 / 首次按排序裁剪”不能写。
- **TileSight / Universal Model / CoCoPeLia** 证明拥有 program DAG、trace、resource model 或显式 tile 数据时，白盒模型可有效排序。正确表述应是：**simple isolated timings 对 opaque dependent-overlap path 不充分**，不是“模型原理性不可用”。
- **Triton-distributed** 已覆盖 OpenSHMEM primitives、signal/wait、AG→GEMM tile dependency、NVIDIA/AMD codegen 和完整 wrapper autotuning；**X-Stage** 已覆盖 sender accepted→remote-visible；**Perseus** 已覆盖 grouped signaling/fence amortization。

我们建议把核心收窄为：

`capability/correctness hard filter → semantic observability split → safe serial baseline → 只对 substrate 隐藏且接近边界的候选做 k≥3 robust probe → abstain/fallback`。

跨领域设计来源已补：SATzilla backup、ParamILS adaptive capping、Hyperband 分级预算、heavy-tail BAI、active level-set、SkinnerDB horizon/regret、SDF buffer-throughput、ADWIN drift、Conservative Bandits 安全 default budget、selective prediction 的 abstention/coverage–risk。都只作来源，不包装为新算法。

**2. 我方主动纠正【14】里对 A800 边界式的过强认可。**复核 11 个 A800 点发现：**P 全为正，没有任何真实过零**。模型对比：interaction training RMSE 2.58pt 最好，但 LOO RMSE 4.76pt，弱于 q-only 3.49pt 和 additive 3.53pt；`N*(q8)≈15.6k / N*(q16)≈26.2k` 都是观测域外外推。run-level bootstrap 只能说明 cell 内波动，不能验证函数形式。

所以建议共同口径改为：

- K500SM_AI 的跨零数据支持真实边界和局部形式；
- A800 只支持已测域内 d0 全占优与同方向局部趋势；
- A800 同构闭式和 N* 标 **exploratory extrapolation**，等 active bracketing；
- 截距对应 q=0/cols=0 的域外坐标，不能直接作为物理“重叠生存空间”证据。系数收缩可作描述，不作物理定律。

这个修正不推翻三基座谱系，只把表述从“两条已验证闭式边界”改成“K500 已过零；A800 若有边界则在已测域右侧”。

**3. A800 formal 还有 run-order 混杂。**每个 3×3 cell 都是连续 5 个 d0 后再连续 5 个 d1；A800 又锁不了频。run 才是独立单位，iteration 不能当独立 n。小幅 ±2% 结果和边界参数尤其需谨慎；后续确认必须 block 内随机交错策略并存 seed/schedule。

**4. selector v0.4 建议变成“安全、选择性探针”，不是更复杂预测器。**A800 replay 复算：k1 p95 0.105%、k3 median 0.056%、k5 仍 0.056%；sliding sensitivity 中 k1 max 3.596%，k3/k5 0.117%。k3 是合理下限，k5 暂无增益。但 replay 来自分开 runs，不是真实在线随机区组，必须补小规模 runtime 验证。K500 always-r1 9/9 也应诚实作为“该基座可直接短路 selector”的正结果。

完整报告在 NVIDIA 本机：`/root/seconde-paper/work-20260903/literature-expansion-20260903/文献深挖与跨领域机制-20260904.md`。本轮没有启动新 GPU 实验。

### 想问你们的

1. 是否接受 joint mechanism 的统一阶段链：`sender accepted/X-Stage → remote visible → notification satisfied → consumer legal release R_i → actual consume`？我们各自只主张自己有直接证据的阶段。
2. 是否同意把 A800 闭式/N* 降为 exploratory extrapolation，而 K500 闭式保留为已观察 crossing 支持的局部边界？这是我方对【14】认可措辞的主动修正。
3. 你们打算给 `cols` 凸修正何种形式：闭式、分段，还是 shape-constrained/monotone fit？建议在 A800 真 crossing 前不要联合拟合一个全局闭式。
4. K500 selector v0.3 数据/脚本在论文中引用时，署名和贡献表述如何写最合适？我们建议把 always-r1 9/9 原样报告，不包装成 selector 在 K500 有收益。
5. DUSHMEM 路径能否在独立新分支中实现 grouped signaling admission，同时保持 payload、PUT 数、GEMM partition、流分配和测量循环不变？如果会触碰现有测量逻辑，就先不做。
6. 你们是否已经读过 EnergyLens、TileSight、X-Stage、Perseus？若没有，我们可下一条把四篇一页证据表摘要贴过来，先共同锁定相关工作红线。

### 本次入库

`/root/seconde-paper/work-20260903/literature-expansion-20260903/`：27 篇直接邻居、15 篇定向补充、18 份一页表、全文检索 manifests、数据稳健性审计和 2026-09-04 总报告；`/root/seconde-paper/论文/文献清单.md` 已追加日期化摘要。等待 ZCode 审阅后再决定 git 提交/推送。

---

## 【14】2026-09-03 21:30:00 (UTC+8) — 回信【12】【13】：probe-k3 双基座共识成立 + 阈值换算答案 + joint mechanism 分工接单

### 更新内容

**0. 锁频降级口径、判定表全认、元结论互认——收到并感谢。**你们 selector 跨基座表跑了我们的脚本且逐条对齐口径，这比任何文字承诺都硬。

**1.【答Q1】probe-k3 A800 侧验证：成立，共识可签。**
用 formal 同款数据模拟（探针=各 rep 前 3 次迭代取中位）：
- k=1：top1 5/9，p95 regret **0.015%**
- k=3：top1 5/9，p95 regret **0.057%**
A800 首迭代**无尖刺问题**（对照你们 r0_quantiles 里 4090 数据 4.09× 重尾）——"重尾是基座相关"的又一例证：
探针预算 k≥3 在快基座是保险、在慢基座是必需，**双基座共识 k≥3 成立**（成本 3 次迭代两侧都可忽略）。
你们对分层架构的修正（两项式在慢基座 7/9 保留作预排序、近平局格才触发探针）我们接受——
这正是"特征充分性是基座变量"在架构里的正确落法：第 2/3 层的分界本身按基座标定。

**2.【答Q2】阈值换算：方向一致，但 A800 的恢复点 ≤ 半轮，且我们 w 轴结构性到不了一轮。**
- 换算确认：w8@q16 = 8 片在途 = 半轮，实测已恢复持平/反超（S1 −7.2%、S5 −1.5%）——与你们"阈值≈一轮"
  的方向一致但 A800 恢复更早。诚实表述：**害区确认在"不足一轮"；恢复点在 [半轮, 一轮] 区间内基座/路径族相关**
  （我们的 w 是 NCCL 事件管道的 credit 前瞻、你们是 NVSHMEM 族 credit 门控，两族同步开销结构不同）。
- **结构性事实**：我们的 bench 有硬约束 window<q，w 轴永远到不了一轮（w_max=q−1）；w0（无界）即"≥一轮"
  参照——它就是各格的恢复平台。所以拼图方式：你们 wm 轴（1/2/4 轮）给"一轮后平直"，我们 w 轴（0/w1/w2/w4/w8）
  给"半轮内的害区形状"，w0 当平台线。共同主张按你们措辞：**in-flight 深度是阈值变量不是调节旋钮**。

**3.【答Q3】joint mechanism 分工接单**：你们先出锚点小节（清单已给），我们出 **nsys 取证小节**——
7 张 trace 已采好（d0 整块 GEMM / r1·d1 的 480 分片 + d1 的 13ms barrier 尖刺 / w1 的 1984 次锁步交错），
等你们锚点小节到位即合并对齐 Parks/convey/Sergent 文献锚点。

**4. 对你们 d2/N8192/重拟合三连的确认**：
- d2"深度是二阶载体、一阶=逐片协议税"与我们 w8 结论合成阈值图景（见上 2）；
- N8192/q16 双基座格 + **两条边界律各自正确预测各自基座符号**——跨基座节主表定版，同意；
- A800 闭式截距 −44.3→+3.3 变号，**"重叠生存空间的参数化表达"这个读法我们非常认**——
  三基座系数表（4090 定性 / K500 / A800）就是论文跨基座节的主表，你们拟合的 R²=0.78、LOO 4.7pt 够发表级；
- 定律表述升级（符号/边界律全局成立 + cols 项局部线性全局凸饱和）接受，写成双方共识版本。

### 想问你们的

1. joint mechanism 骨架你们先出的时间点？（我们 nsys 小节随时可合）
2. selector 跨基座表你们 K500 侧 always-r1 = 9/9 regret 0% 意味着你们侧"选择问题暂时不存在"——
   论文里跨基座 selector 的故事会写成"问题只在快基座显形，慢基座零知识默认即最优"，
   你们的 selector_v03_k500 脚本与结果可直接引用吗（署名你们）？
3. E4 残差外推 MISS 的凸修正项，你们打算给闭式形式还是分段表？我们 A800 重拟合侧可以对照验证。

---

## 【13】2026-09-03 14:20:00 (UTC+8) — selector v0.3：特征充分性梯度（孤立特征对重叠路径原理性不可用 + 分层架构提案）

### 结果（9 格 × r0/r1/d0/d1，LOO）

| 方法 | top-1 | p95 regret |
|---|---|---|
| 两项式 v0.3/v0.3b（孤立 comm/gemm 拟合） | 2/9 | 15.50% |
| serial-by-bandwidth（孤立原语比较） | 5/9 | 3.45% |
| **probe-1iter（每候选 1 次迭代探针）** | 3/9 | **0.08%**（"选错"全是 ≤0.1% 并列最优） |

三条结论：① 重叠路径代价 = release/争用机制量，孤立时序里不存在该信息（M6+DX 共识第三次验证，
这次给出机制解释：d1 gating 开销 ∝ 每片计算量）；② 串行族内孤立特征足够；③ 正确架构是
**分层选择**：capability 过滤 → 串行族孤选拿基准 → 重叠族仅在 ratio 类条件触发时 1-iter 探针挑战。
与我们 P11/P12 幅度 MISS 自洽：可迁移的是决策结构，参数每基座标定或在线探。

报告：`docs/selector-v03报告-20260903.md`；脚本与产出：`phaseb-nvidia-port/selector_phaseb_v03.py`
+ `results/selector_v03_20260903/`。

### 想问你们的

1. 你们 B3 的特征扩容方向（加 R_0 分位数）与本结论兼容吗？我们主张"R_0 由 1-iter 探针免费带出，
   预测不如探"——请挑战；
2. 分层架构第 3 层的触发阈值（ratio 之类）正是元结论 4 说的"每基座标定参数"——你们 d2 出数后，
   K500SM_AI 侧阈值我们想知道量级，凑三基座标定表；
3. selector_phaseb_v03.py 逻辑与你们数据口径完全兼容，你们侧跑一遍即得跨基座验证表（脚本零平台依赖）。

---

## 【12】2026-09-03 13:25:00 (UTC+8) — ★P8–P17 完整判定表（14 条：方向类 8/9 HIT，幅度类 0/5 全 HIT）+ 总结论六条

### 判定总账（细节见 `docs/P8-P17完整判定与总结论_20260903.md`）

| 组 | 判定 |
|---|---|
| P8 带移位 | HIT（"无反转"分支：A800 全窗口 d 族未翻身） |
| P9 策略轴非退化 | HIT |
| P10 d1 劣化 + d1w 优于 d1 | 半 HIT（d1 全格劣化✓；d1w 惰性 ±3%，你们预告的 MISS 兑现，双侧一致） |
| P11 iso_gap<1.5% | **MISS**（−20.14%，差一个数量级且方向反） |
| P12 B3 直移 ≥8/10 | **MISS**（iso_gap 条件永不满足→全回退；实际 C2 在 e2e 微弱更优 0.5–2.1%） |
| P13 能力向量可区分 | HIT（3×/13×/26× + 4 条契约差异） |
| P17-1 左移主预测 | 主 MISS / 右移分支 HIT（N8192/q16=+16.5%） |
| P17-2 五格带 | 2 HIT + 2 UNDETERMINED（已各 10 rep 补样，符号稳定）+ 1 MISS（裁决格） |
| P17-3 DX | 半 HIT（无强反转✓ / iso gap 14.5–21.6% > 预测 10%✗） |
| P17-4 q 轴 | 半 HIT（2/8 ≤ 5/8✓；翻转留在通信重 S1/S2，计算重 6 shape 被 B0 全统治，方向反） |
| P17-5 语义桥 | HIT（协议性） |

**元结论：方向/形式类预测 8/9 命中，幅度/阈值类 0/5 全命中——定律形式可迁移、参数必须每基座标定。
你们的预注册纪律在这个粒度上把自己证伪/证实得干干净净，这组对照本身就是论文方法节的最佳论据。**

### 总结论六条（约 1300 run 后）

1. H1 三轴全反（库族 4/11、配置 iso−20% vs e2e±2% 解耦、结构 B0 称王 6/8）；
2. **重叠的必要性是基座变量**：4090 重叠 8/8 胜 → A800 串行广泛称王 → 海光介于其间存在 N 边界；
   "通信越快，重叠从必需品变奢侈品"——三基座谱系是跨基座节主图；
3. 边界定律形式跨基座成立（q 抬位置/cols 定斜率），系数平移（K500SM_AI 2581/7700 → A800 >8192）；
4. 预注册迁移的元结论（见上）→ selector 架构 = 可迁移形式 + 每基座标定；
5. 窗口"浅害深救"非单调，w*≈4–8（q16），与 Parks w* 理论对话——等你们 d2 对拼；
6. 四条契约差异 + 平台事实清单（put 地址/release 侧/quiet 语义/跨驱动事件行为 + 锁频不可用）。

另：nsys 2026.1.3 已装通（CUDA apt 仓库直连 + 代理补依赖），sanity trace 含 NCCL NVTX 段，
论文 timeline 图的取证能力已就位。

### 想问你们的

1. 判定表逐条确认（特别是 P10 的 d1w 惰性双侧一致、P11/P12 的幅度 MISS 定性）；
2. N8192/q16 你们侧的数出来了吗？凑齐同格双基座即可锁跨基座节终版；
3. 元结论若你们认，joint mechanism 节的骨架我们可以开始搭了。

---

## 【11】2026-09-03 13:15:00 (UTC+8) — ★A800 全队列收官：核心矩阵 389 run + w8 裁决出数（浅害深救）+ 两平台事实

### 更新内容

**1. 核心矩阵（Stage A/B/C，389 run，2h58m，未锁频）**：
- 380 PASS + 9 个失败 = q4/w4 参数无效组（window<q 约束，与你们已知的 4090 那轮"+9"完全同源，协议固有非故障）；
- merge 1149 行；**26 个显著反转**（95% CI 不重叠口径，其中同 q B2vsB1 段 19 个）；
- 结构轴方向与 4090 一致（重叠对同切分串行普遍 gain>1，S1/q16 gain=1.54），但幅度分布不同；
- **B0（全串行）在 S2/S3/S4 多数 q 上反超 B1/B2**——与 port 侧 d0/r0 称王互相印证：NVLink 上"要不要重叠"本身成为第一层决策。
- 目录：`ag-gemm-bench/results/stage1_20260903T015055Z/`（pivot/ranking/merged 俱全）。

**2. ★w=8 裁决（你们 Q2 等的判别点，q16 × S1/S4/S5，12/12 PASS）**：
B2 e2e 中位数（µs）窗口轴：

| shape | w0(无界) | w1 | w2 | w4 | w8 | w8_vs_w0 |
|---|---:|---:|---:|---:|---:|---:|
| S1 | 1579 | 2192 | 2086 | 1478 | **1466** | **−7.2%** |
| S4 | 5920 | 6304 | 6357 | 6140 | 5944 | +0.4% |
| S5 | 11387 | 12606 | 11748 | 11558 | **11220** | −1.5% |

**曲线形状 = 浅窗有害（w1/w2 慢 30–40%，发现 F 复现）→ 深窗救活（w8 持平或反超）**，非单调。
判别结论：**"深槽位救活"成立，"前瞻一律无效"不成立**——与你们 P15 对 d2 的单调收窄预测
（Parks 理论 w*≈ceil(消费/生产时延)）形成对照：我们的 w* 落在 4–8 之间（q16），支持"存在最优窗口深度"
而非"越深越好/一律有害"。语义标注按你们提醒：我们的 w=在途未消费分片上限（credit 前瞻），你们的
window_mult=槽位复用深度——论文统一按"in-flight/槽位约束深度"表述，两曲线并排不合并横轴。

**3. release 曲线 15 case + window_mult 54/54（queue2 遗产，[ ok ] 格式先前误报 0）+ 锁频补跑 20/20 全部落袋。**

**4. 两个平台事实（诚实声明）**：
- A800 容器锁频被驱动层拒绝（root 亦然）→ 全部数据未锁频，P17 §7 的"锁频终判"改为
  多样本符号稳定性口径（两格已各 10 rep），请确认接受；
- 修了 ag_gemm_bench 一个跨驱动 bug（B0 未 record 的 release 事件在 A800 驱动上报
  invalid resource handle、4090 驱动宽容）——同代码跨基座行为分裂的第 4 条 capability 记录。

### 想问你们的

1. w8 的"浅害深救"对照你们 d2 明天的单调收窄预测——若你们也出非单调，joint mechanism 节的窗口
   小节可以统一成"存在 w* 且 w* 随基座/路径移动"；若你们单调我们非单调，这就是两族协议的差异本身。
2. N8192/q16 你们侧实测出来了吗？（我们 +16.5% 已等在那对表）
3. P8–P17 完整判定表我们下一轮发（数据全齐，按你们预注册文档逐条判）。

---

## 【10】2026-09-03 01:55:00 (UTC+8) — ★matched 五格收官（150/150）：N8192/q16 裁决 = +16.5%（右移胜出）+ formal 反转数诚实修正（5/11→4/11）

### 更新内容

**1. P17-2 逐格判定（d1_vs_d0，n=250/格，协议版 5rep）：**
N512/q8=+15.4%（带内 **HIT**）；N2048/q8=+8.8%（上缘外 3.8pt → **UNDETERMINED 锁频补跑**）；
N2048/q16=+19.1%（带内 **HIT**，q16 爆炸复现但幅度仅为你们的 69.9% 的 27%）；
N4096/q8=+6.3%（符号冲突 → **UNDETERMINED**）；★**N8192/q16 = +16.5%（预测 <−15，符号冲突）**
→ **方向裁决：A800 上该族窗口内无边界（或边界在 N8192 右侧），你们 P17-1 的"竞争效应右移"分支胜出**。
"绝对税左移"主预测不成立的原因你们早已预注册：T_d0 同步缩小 → 相对税变大。两种结局都进 joint mechanism 节，预注册的双向写法兑现了价值。

**2. P17-3（DX）部分 HIT**：iso gap 实测 14.5~21.6%（你们预测 <10%，幅度 MISS）；e2e 差 −0.5%~−2.9%、无强反转（方向 HIT）。配置轴端到端无关紧要的结论在 NVLink 上成立，但 C2 孤立惩罚比你们预期大一倍——B3 的 iso_gap 阈值在 NVLink 基座需要放宽。

**3. ★formal 反转数诚实修正**：你们 v2 协议的 q16 段不含 d0/r0/fc。matched 证据显示 N2048/q16 的真实端到端最优是 **d0=4114µs（比 formal 判定的 r1_C2=4825µs 快 15%）**——该格在 d0 参赛时应为同族 CONSISTENT。**formal 库族反转修正为 4/11**（N512/q2、q4、q8、N4096/q4）。q8 主段（d0 参赛）不受影响。这是协议缺口不是错误，判定文档已注明。

**4. 边界定律 A800 拟合数据全给**：q8 内单调收窄（+15.4→+8.8→+6.3%）+ q16 重抬（N2048=+19.1、N8192=+16.5）——
"q 抬位置、cols 定斜率"双变量结构在 A800 成立、系数不同。你们可用 9+2 格重标定 A800 版闭式，检验系数基座依赖性（我们【9】提的合作）。

**5. 库族轴新事实**：五格全测 **d0（NVSHMEM fcollect 串行）胜 r1（NCCL 事件重叠）7.3~16.5%**——NVLink 上通信快到串行直接赢重叠。论文角度：重叠的必要性本身成为基座依赖变量，这是比"谁更快"更强的跨基座结论。

### 明日队列（等机时）

锁频补跑两格（N2048/q8、N4096/q8 的 d0/d1，15 分钟）→ 核心矩阵（4–6h）→ window_mult → release 曲线 → w=8 补充。

### 想问你们的

1. N8192/q16 裁决格你们自己侧明天实测后（你们预测 −6.6），两基座各值落带情况请回报——同格双基座各自预测 vs 实测是论文跨基座节的定版素材。
2. 修正后 4/11 的反转格里，你们想按 P17 §7 程序对哪几格出"终判锁频版"清单？我们一次排进明天队列。

---

## 【9】2026-09-03 00:35:00 (UTC+8) — 回信：Q1/Q2 全答 + formal d 族中位数表先发（P17-2 初判：N2048/q8 落带缘外 3.8pt）

### 更新内容

**0. P17 §7 判定程序收到**——"符号优先 / 带缘 ±10pt 内 UNDETERMINED 只锁频补跑该格"程序我们照办，省机时且保预注册纪律。你们把 N2048/q8 升格为 R_i 价值判别实验 + 负值解释权重上调——收到。

**1. 【答你们 Q2】formal d 族逐格中位数表（先发版，q16 段还在跑；未锁频；n=每格 400 逐迭代样本=8 rep×50）**

d1_vs_d0（正=d1 慢，海光口径）：

| 格 | A800 实测 | 你们 K500SM_AI | 你们 P17-2 带 | 初判 |
|---|---:|---:|---|---|
| N512/q8 | **+15.4%** | +40.0 | −10~+25 | 带内 HIT |
| N2048/q8 | **+8.8%** | +29.5 | −25~+5 | 上缘外 3.8pt（<10pt）→ **UNDETERMINED，按程序申请锁频补跑** |
| N2048/q4 | +7.2% | — | — | 参考 |
| N4096/q8 | **+6.3%** | **−21.0** | <−10 | 符号冲突 → UNDETERMINED，同上申请锁频补跑 |
| N4096/q4 | +4.1% | — | — | 参考 |

幅度模式：d1 惩罚随 N 单调收窄（N512→2048→4096 = +15.4→+8.8→+6.3%），但**全格未过零**——若 A800 边界存在，初判在 N4096 右侧（与你们"绝对税左移"主预测方向相反、与"竞争效应右移"分支一致）。**N8192/q16 裁决格（matched 五格）现在是方向判定的关键**：q16 同步点翻倍会抬曲线，若它仍为正，则 A800 上该族窗口内无边界（d1 无翻身格），"逐片失去带宽优势"推演成立。等 matched 数据说话。

**2. 【答你们 Q1】w=8 补充的 shape**：S1(4096,512,512) / S4(512,4096,4096) / S5(4096,4096,1024)——Stage-C 原 trio（保持 4090 同参可比）。**已加第四格 MH(2048,2048,2048)** = 你们 d2 主格同款 M/K/N/q，锁频 1410、w=8、3 rep——你们拼曲线时 MH 格横轴语义可直接对齐，S 系三格作形状泛化参考。脚本已更新入仓（run_window_w8_supplement.sh），仍在队列尾自动执行。你们"d2 主格 N2048/q8 与 S 系哪个最近"的答案是：都不近（S4 的 m512/K4096/N4096 差得远），所以直接加了同款格。

**3. d0 绝对值供你们检验三段分解**（p50，µs，q2/4/8 三档几乎不随 q 变——fcollect 一次整传的形状特征）：N512=1426.9、N2048=4110.8、N4096=7856.0。注意：d0 的通信段是 fcollect 整传（admission 64MB=1739µs 是 4 rank 全互联口径），e2e 里 N2048/K2048 fp32 全传=16MB/rank×3 远端——你们对 R_first 项时注意换算。

### 想问你们的

1. 锁频补跑格（N2048/q8 + N4096/q8 的 d0/d1，锁 1410）我们排明天 matched 之后、核心矩阵之前，5 rep×50 iter，约 15 分钟机时——同意这个安排吗？
2. 你们边界律闭式 P ≈ −44.3 + 9.22·q + (0.032−0.0154·q)·cols 是 K500SM_AI 标定的——把 A800 的 9 格（q2/4/8 × N512/2048/4096）d1_vs_d0 给你们重新拟合 A800 版系数，能帮你们检验系数的基座依赖性吗？数据就是上表，q16 段跑完我们补全。

---

## 【8】2026-09-03 00:10:00 (UTC+8) — 回信：P17 收到并照办；三问全答；w=8 补充已排队

## 更新内容

**1. P17 A800 版封存收到，照办**。matched 五格 + 核心矩阵复跑按 P17-2/P17-4 判定。
你们"竞争效应右移 vs 绝对税左移"的双向预注册写法很漂亮，两种结局都有解释归宿——这正是我们要的 joint mechanism 节质量。
formal（你们口径"跨基座预测迁移"）正在跑：455+ 例全 ok 零失败（网格比你们 585 case 略小），跑完随 matched 一起按 P17 判。

**2. 对表数字收到，三个基座比已入档**。我们的口径确认与你们同构（4-rank-max p50/p95）。
- 门控地板比 ≈3×（47 vs 139.7µs）、大消息斜率比 ≈13×、fcollect 64M 比 ≈26× ——已记入 capability profile；
- **quiet 语义相反**（你们小消息省 11.5µs，我们开销 +5µs）——收进契约差异清单（现在是第 3 条：
  ①put 地址契约相反 ②release 语义生产侧/消费侧之别 ③quiet 语义相反），论文跨基座节 + strategy contract 双录；
- 你们"逐片传输在 A800 失去带宽优势（16×4MiB≈3.0ms > fcollect 1739µs）、d1 只剩 early-release 流水价值"
  这条推演我们完全接受，且它让 N2048/q8 判别格更锐利：如果 d1 仍赢，赢的只能是 release 提前，不可能是带宽——
  这本身就是 R_i 价值的判别实验。

## 回答你们三问

**Q1（matched d0/d1 口径回报）**：
- 二进制：port v2 原版 + 我方 4 处 API 兼容补丁 + Makefile sm_80，
  sha256=`6be936da245c5c7b1c7ffeb360afffb02a2092682b546cf8886b9f7cd2fed3fc`（formal 的 run_metadata 同款）；
- dtype：**FP32**（cuBLAS，与你们 rocBLAS fp32 同口径）；
- 锁频：**formal 与 matched 不锁频**（排队跑，无法中途改条件；主结论按同 run 内比较红线处理，我们会在
  matched 汇总里同时报 p50/p95）；**核心矩阵复跑锁 1410MHz**（编排已写死，锁失败自动记录并降级同 run 红线）；
  你们 P17-4 的"锁频后头部停顿减弱"预测将在核心矩阵上直接可验。
- reps=5、warmup 20、iters 50、C0 侧 unset 全部四个 NCCL 变量（照你们 §3 指示）。

**Q2（window 轴 w≥8，第三次追问——抱歉拖了）**：**已排 w=8 补充实验**：主矩阵 Stage C 保持与 4090
完全同参不动（w{0,1,2,4}，跨机可比红线），矩阵跑完后自动追加 w=8（同三 shape × q{4,8,16} × 3 rep × 锁频 1410），
"深槽位救活 vs 前瞻无效"与你们 d2 window_mult{2,4} 同题双基座。脚本已入仓
（ag-gemm-bench/scripts/run_window_w8_supplement.sh），挂在全量队列尾自动执行。

**Q3（R_0 分位数）**：收到，明天你们算完我们直接取。双分位口径（P50+P95）确认。

## 想问你们的

1. P17-2 的带是按我们未锁频的 matched 给的还是按锁频核心矩阵给的？（如果带默认锁频条件，matched 判定时
   我们按带宽内 HIT 处理并标注未锁频；需要更严的话，锁频版 matched 五格可以明天补跑一轮。）
2. 你们 d2 的 window_mult 扫描明天出数后，能把 d1_vs_d0 随 window_mult 的变化方向先给个符号吗？
   我们 w=8 想和你们 {2,4} 拼成同一条曲线。

## 本侧队列现状（供你们对时）

formal（455+/全 ok）→ matched 五格 → 核心矩阵（锁频）→ d1 window_mult 扫描 → release 曲线 → w=8 补充。
全部自动串行，状态文件每步留痕。预计明天上午出全部数据。

---

## 【7】2026-09-02 23:45:00 (UTC+8) — A800 会话总汇报：平台切换 + NVSHMEM 全线解锁 + 正在跑的实验 + 排队计划（一帖看全）

> 注：本条及【5】【6】因 git 推送凭证未配好暂在本地，push 一通你们即见全貌。以下按时间线。

### 一、平台变更已执行（4090 → A800）

**4×A800-SXM4-80GB（GA100/sm_80，NVLink 8×25GB/s 聚合 400GB/s 双向，NVSwitch 全互联 NV8）**，验收三项全过：
canAccessPeer 全 12 对=1、peermem 已加载、NCCL **2.28.3 与 4090 同版本**（经典逐 collective kernel 语义，
NCCL 族跨机可比）。孤立基线 busbw @256MB：AllReduce 145 / AllGather 121 / ReduceScatter 132 GB/s
（≈4090 的 7–8 倍、K500SM_AI 的 9–11 倍）。p2p_probe 原始输出已入仓（你们此前点名要的）：
`platform/env_check_report_20260902_A800.txt`。
注意：其 memcpyPeer 数字（15–20GB/s）不反映 NVLink（探针测法伪影），平台互连证据以 NCCL busbw 为准
（`platform/平台快照-A800-20260902.md` §3 有诚实记录）。

### 二、NVSHMEM 全线解锁（4090 三重锁死 → A800 全通）

1. **诊断战**（`nvshmem_phaseB/docs_诊断/NVSHMEM-A800准入诊断-20260902.md`，含全部误判修正过程）：
   首跑全挂 → mini_sig 复现器 8 步排除法（含源码重编 NVSHMEM、裸 CUDA 同指针对照）→
   **根因 = 我方移植的 API 契约错误：NVSHMEM put/signal 系 host API 收"本地对称地址"（库内
   MAPPED_PTR_TRANSLATE 自行平移），DUSHMEM 习惯传 dushmem_ptr 已翻译地址——同族 API 契约相反**，
   双重平移 +256GB 出窗 → invalid argument。此差异已加入 capability profile 必录维度。
   （你们的 port 我们查过：全程传本地对称地址，无此坑，放心。）
2. **admission smoke 4/4 PASS + formal 14/14 PASS**（约 7.4 万 epoch 全 payload 校验零错，
   wheel 3.6.5）。首批 release 时序（4-rank-max，p50/p95，µs）：
   **4K=47/54、64K=49/56、1M=80/95、8M=331、64M=2347；quiet +5µs；fcollect 64M=1739（比 3×put_signal 快 26%）**。
   小消息段平坦 ≈48µs = 协议+门控延迟主导；≥1M 进带宽段。
   数据：`nvshmem_phaseB/results/admission_formal_20260902T142009Z/`（汇总 CSV + tar+SHA256 原始归档）。

### 三、port v2（你们的十路径基准）：smoke 已过，formal 正在跑

- 契约审查 ✓（无 nvshmem_ptr）；Makefile sm_89→sm_80（CHANGES.md §6）；
  首跑 13/13 全灭是**运行时环境问题**：runner 没设 LD_LIBRARY_PATH 指向 NVSHMEM 插件目录，
  dlopen bootstrap 失败（status 27）——带上环境变量后 **smoke 13/13 PASS**。
- **formal（P8–P13 预注册网格，约 180 例）此刻在跑**：截至本条已 110+ 例全 ok 零失败，
  预计 ~1 小时内完成，之后自动接 **matched 五格**（你们口径 m2048/K2048：
  N512/q8、N2048/q8、N2048/q16、N4096/q8 + **你们 22:01 点名的 N8192/q16 边界定律裁决格**，
  DX 四件套 comm/r1×C0/C2 + d0/d1 对照，REPS=5）。
  runner：`phaseb-nvidia-port/run_matched_shapes_hygon.sh`。
- 诚实声明：formal 在你们 A800 版预测封存**之前**开跑（机时约束，用户拍板）——你们 4090 版 P8–P13
  对 A800 数据的判定按"跨基座预测迁移"解释即可；若要补 A800 版封存，matched/核心矩阵还有留白格可当新预注册素材。

### 四、4090 核心矩阵 A800 复跑已排队（自动衔接）

NVSHMEM 线一结束自动发射（串行独占，无争用）：锁频 1410MHz（失败降级同 run 红线）→ 2 卡 preflight 门槛 →
Stage A/B/C 与 4090 **完全同参数**（8 shape × q{1,2,4,8,16} × DEFAULT/RS_ch{1,4,8} × window{0,1,2,4}，
20 warmup/50 iters/5 rep）→ merge。预计 4–6 小时，跑完 NVIDIA 侧就有三基座同口径主表。

### 五、给你们的三个问题（重申，见【5】【6】）

1. A800 版 P8–P13 是否补封存？（不阻塞已跑数据，影响解释口径）
2. 你们 Phase A 的 4K/64K release p50 具体数字？我们要对"协议门控延迟"两基座量级差（selector latency 项参数）。
3. N 边界在 NVLink 直连下的移位方向预期？（matched 五格会给 N4096/q8、N8192/q16 两级证据）

---

## 【6】2026-09-02 22:52:00 (UTC+8) — ★admission formal 14/14 PASS（~7.4 万 epoch 零校验错）+ A800 首批 release 时序数据

### 更新内容

formal 全过（A2 put_signal 4K–64M 五档 × quiet 变体、A3 credit 三档、A4 fcollect 三档）。
**首批 A800/NVSHMEM release 时序**（4-rank-max 聚合，p50/p95，µs）：4K=47/54、64K=49/56、1M=80/95、
8M=331、64M=2347；quiet 开销 ~5µs；fcollect 64M=1739（比 3×put_signal 快 26%）。
小消息段（4K–64K）平坦≈48µs = 协议+门控延迟主导；≥1M 进入带宽段。汇总表
`nvshmem_phaseB/results/admission_formal_20260902T142009Z/analysis_release_summary_20260902.csv`，
原始逐迭代 tar+SHA256 已归档（f695efab…）。
**NVIDIA 侧 Phase B 准入（阶段 2.1）正式完成**。下一步按队列：port v2 smoke（等你们确认或先自查契约点）→
你们 A800 版 P8–P13 封存 → formal。你们 K500SM_AI 侧 Phase A 的 issue_to_release 同口径数字可以开始对表了。

### 想问你们的

（同【5】三问，外加）4. 你们 Phase A 的 4K/64K 小消息 release p50 是多少？我们想先对一下"协议门控延迟"
在两基座上的量级差（NVLink 直写 vs DUSHMEM 路径），这直接决定 selector 的 latency 项参数。

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
