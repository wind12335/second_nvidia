#!/usr/bin/env python3
# selector v0.3（2026-09-03，A800 会话）——M8 正解：系数只用孤立测量拟合，LOO 留出验证
#
# 预测器输入（全部为孤立测量，formal 的 *_ONLY 路径，C0）：
#   comm = COMM_ONLY p50 (NCCL 整传 AG)
#   fc   = FC_FCOLLECT_ONLY p50 (NVSHMEM fcollect 整传)
#   dc   = DC_PUSHSIG_ONLY p50 (NVSHMEM put+signal 逐传)
#   gemm = GEMM_ONLY p50
#   q    = 分片数
# 模型（两项式：重叠 = 流水主体 + 逐片同步开销）：
#   pred(r0) = comm + gemm
#   pred(d0) = fc + gemm
#   pred(r1) = max(comm, gemm) + a1*q + b1
#   pred(d1) = max(dc,   gemm) + a2*q + b2
# 拟合：LOO——每格留出，用其余格最小二乘拟合 (a1,b1)/(a2,b2)，再对留出格预测 argmin。
# 基线：always-d0 / always-r1 / serial-by-bandwidth（min(comm,fc)+gemm 选串行）
#       / B3 适配版（q>=8 ∧ 0.9<=ratio<=1.35 ∧ iso_gap<=2% → r1，否则 serial-by-bandwidth）。
# 指标：top-1 命中、regret = (实际e2e[选择] - 实际e2e[oracle]) / oracle。
import csv, os, json
from itertools import combinations

ROOT = os.path.join(os.path.dirname(__file__), 'results',
                    'a800_4gpu', 'phaseb_formal_20260902_232036', 'summary', 'phaseb_case_summary.csv')
OUT = os.path.join(os.path.dirname(__file__), 'results', 'selector_v03_20260903')
os.makedirs(OUT, exist_ok=True)

raw = {}
for r in csv.DictReader(open(ROOT)):
    raw.setdefault((r['path'], int(r['N']), int(r['q'])), []).append(float(r['e2e_max_us_p50']))
def p50(path, N, q):
    v = raw.get((path, N, q))
    return sorted(v)[len(v)//2] if v else None

CELLS = [(N, q) for N in (512, 2048, 4096) for q in (2, 4, 8)]
STRATS = ['R0_FULL_SERIAL', 'R1_EVENT_OVERLAP', 'D0_FCOLLECT_SERIAL', 'D1_PUSHSIG_OVERLAP']
SHORT = {'R0_FULL_SERIAL':'r0','R1_EVENT_OVERLAP':'r1','D0_FCOLLECT_SERIAL':'d0','D1_PUSHSIG_OVERLAP':'d1'}

grid = {}
for (N, q) in CELLS:
    comm, fc = p50('COMM_ONLY',N,q), p50('FC_FCOLLECT_ONLY',N,q)
    dc, gemm = p50('DC_PUSHSIG_ONLY',N,q), p50('GEMM_ONLY',N,q)
    e2e = {SHORT[s]: p50(s,N,q) for s in STRATS}
    if None in (comm,fc,dc,gemm) or None in e2e.values(): continue
    grid[(N,q)] = dict(comm=comm, fc=fc, dc=dc, gemm=gemm, e2e=e2e)

def preds(cell, a1,b1,a2,b2):
    c,f,d,g = cell['comm'],cell['fc'],cell['dc'],cell['gemm']
    q = 1  # 占位
    return None
def predict(cell, q, a1,b1,a2,b2):
    c,f,d,g = cell['comm'],cell['fc'],cell['dc'],cell['gemm']
    return {
        'r0': c + g,
        'd0': f + g,
        'r1': max(c,g) + a1*q + b1,
        'd1': max(d,g) + a2*q + b2,
    }

def fit_pair(cells, key):  # 最小二乘拟合 a,b: y = a*x + b（x=q, y=actual - max(...)）
    xs, ys = [], []
    for (N,q),cell in cells.items():
        base = {'r1': max(cell['comm'],cell['gemm']), 'd1': max(cell['dc'],cell['gemm'])}[key]
        xs.append(q); ys.append(cell['e2e'][key] - base)
    n=len(xs); sx=sum(xs); sy=sum(ys); sxx=sum(x*x for x in xs); sxy=sum(x*y for x,y in zip(xs,ys))
    den = n*sxx - sx*sx
    a = (n*sxy - sx*sy)/den if den else 0.0
    b = (sy - a*sx)/n
    return a, b

def serial_by_bw(cell):
    return 'd0' if cell['fc'] < cell['comm'] else 'r0'

def b3_adapt(cell, q):
    ratio = cell['comm']/cell['gemm']
    # iso_gap（本网格无 C2 的 gemm/部分格缺 C2 comm —— 用全网格中位近似为 -20%，条件恒假 → 恒回退
    iso_gap_le2 = False  # A800 实测中位 -20.1%，P12 已证恒回退；此处如实实现
    return 'r1' if (q>=8 and 0.9<=ratio<=1.35 and iso_gap_le2) else serial_by_bw(cell)

def evaluate(name, chooser):
    hits, regs, rows = 0, [], []
    for cellkey, cell in grid.items():
        pick = chooser(cellkey, cell)
        oracle = min(cell['e2e'], key=cell['e2e'].get)
        actual = cell['e2e'][pick]; best = cell['e2e'][oracle]
        reg = 100*(actual-best)/best
        hits += (pick==oracle); regs.append(reg)
        rows.append((cellkey, pick, oracle, round(reg,2)))
    regs.sort()
    med = regs[len(regs)//2]; p95 = regs[min(len(regs)-1,int(0.95*len(regs)))]
    print(f"  {name:22s} top1={hits}/{len(grid)}  regret: med={med:.2f}% p95={p95:.2f}%")
    return dict(name=name, top1=f"{hits}/{len(grid)}", regret_median=round(med,2), regret_p95=round(p95,2), rows=rows)

print(f"selector v0.3  网格: {len(grid)} 格 × 4 策略（LOO 验证）\n")

# ---- LOO 拟合 ----
loo_picks = {}
for hold in grid:
    train = {k:v for k,v in grid.items() if k!=hold}
    a1,b1 = fit_pair(train,'r1'); a2,b2 = fit_pair(train,'d1')
    loo_coeffs = {hold:(a1,b1,a2,b2)}
    q = hold[1]
    loo_picks[hold] = min(predict(grid[hold], q, a1,b1,a2,b2), key=predict(grid[hold], q, a1,b1,a2,b2).get)
    grid[hold].setdefault('_coeffs',(a1,b1,a2,b2))

results = []
results.append(evaluate("selector v0.3 (LOO)", lambda k,c: loo_picks[k]))
results.append(evaluate("always-d0", lambda k,c: 'd0'))
results.append(evaluate("always-r1", lambda k,c: 'r1'))
results.append(evaluate("serial-by-bandwidth", lambda k,c: serial_by_bw(c)))
results.append(evaluate("B3 适配版", lambda k,c: b3_adapt(c,k[1])))

# 输出
with open(os.path.join(OUT,'selector_v03_summary.csv'),'w') as f:
    f.write("method,top1,regret_median_pct,regret_p95_pct\n")
    for r in results: f.write(f"{r['name']},{r['top1']},{r['regret_median']},{r['regret_p95']}\n")
with open(os.path.join(OUT,'selector_v03_choices.csv'),'w') as f:
    f.write("N,q,oracle,")
    f.write(",".join(r['name'] for r in results)+"\n")
    for k in sorted(grid):
        f.write(f"{k[0]},{k[1]},{min(grid[k]['e2e'],key=grid[k]['e2e'].get)},")
        f.write(",".join(('loo_picks' and str(next(r for r in results if r['name']=='selector v0.3 (LOO)')['rows'][i][1]) if True else '') for i in [list(grid).index(k)])+",")
        # 简化: 逐方法行
        f.write("\n")
# 更细的逐格选择表
with open(os.path.join(OUT,'selector_v03_choices.csv'),'w') as f:
    f.write("N,q,oracle_e2e_us,"+",".join(r['name'] for r in results)+"\n")
    idx={k:i for i,k in enumerate(grid)}
    for k in sorted(grid):
        oracle=min(grid[k]['e2e'],key=grid[k]['e2e'].get)
        picks=[r['rows'][idx[k]][1] for r in results]
        f.write(f"{k[0]},{k[1]},{oracle}({grid[k]['e2e'][oracle]:.0f}us),"+",".join(picks)+"\n")
coeffs_all = {f"N{N}q{q}": grid[(N,q)]['_coeffs'] for (N,q) in sorted(grid)}
json.dump(coeffs_all, open(os.path.join(OUT,'loo_coeffs.json'),'w'), indent=1)
print(f"\n产出: {OUT}/selector_v03_summary.csv + choices.csv + loo_coeffs.json")
