# EnergyLens 一页证据表（2026-09-04）

> 论文：Song et al., *EnergyLens: Predictive Energy-Aware Exploration for Multi-GPU LLM Inference Optimization*，arXiv:2605.14249v1。依据为本地 10 页全文及带页码文本。

## 问题与方法

- EnergyLens 用高层 einsum/模型规格描述 fusion、parallelism、MoE 与 Megatron-style compute–communication overlap，在没有实现、trace 或 GPU access 的早期阶段预测 energy/latency（p.1–2, p.10）。
- overlap 验证覆盖 Llama3-70B 的 no-overlap 与四阶段 overlap，并改变通信占用的 1/4/16 个 SM（p.8）。
- 它明确把优化目标定为保持候选排序、识别有利区域，而非追求精确 point prediction（p.8）。

## 关键结果

- overlap sweep 上 energy MAPE 12.97%，latency MAPE 11.18%；模型能反映通信 SM 太多会损失计算资源、太少又会使通信成为瓶颈（p.8）。
- 一个 Llama3-70B energy–latency Pareto frontier 主要由 non-overlap TP2 配置构成，只有最追求 latency 的点受益于 overlap（p.9）。
- maximum-overlap heuristic 仅恢复真实 Pareto frontier 的 20%；EnergyLens 不测候选，预测全部 55 个配置后恢复 69%（p.9）。

## 对本项目的直接压力

- 不能写“首次发现不重叠可能更优”“首次证明不是所有 overlap 候选都需要探”“首次用模型裁剪 overlap 配置”或“首次以排序而非点预测做优化”。
- 工作标题 *Not Everything Needs Probing* 仍可用，但正文必须把 `what need not be probed` 的依据收窄为：可解析/白盒部分无需探，只有 substrate 隐藏的 release/争用信息在边界附近需要探。

## 可保留差异

- EnergyLens 是高层白盒 LLM 执行/能耗模型，候选以 parallelism、batch 和通信 SM 分配为主；本项目面对 opaque NCCL/RCCL/NVSHMEM/DUSHMEM library path 和不一致的合法完成语义。
- 本项目的中心问题不是预测所有结构化候选，而是判断“基座隐藏了什么信息”、何时必须在 dependent context 中测、何时应拒绝预测并回退安全串行路径。

## 证据等级

全文级、当前最重要的新竞争压力之一。论文为 2026 年预印本，终稿前需复核版本与正式发表状态。
