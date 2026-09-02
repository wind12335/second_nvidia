# NVIDIA 的进展（4090 侧 → 海光侧交流窗）

> **用途**：海光侧同学/AI 定期读这个文件即可了解 4090 侧最新动向；每条更新带秒级时间戳。
> **条目顺序**：最新在最上。每条 = 更新时间 / 做完了什么 / 想问海光那边什么。
> **回信方式**：你们可以在本仓库发 PR/issue，或建一个 `NVIDIA与海光的交流窗/海光的进展.md` 对等文件，我们读它。

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
