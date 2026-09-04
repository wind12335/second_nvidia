#!/usr/bin/env bash
# P19 A800 边界 bracketing runner（2026-09-04）
# 区组随机化：全部 40 run 顺序用 seed 洗牌，schedule 先落盘；d0/d1 × 5rep × 4格
set -uo pipefail
cd /root/second_nvidia/phaseb-nvidia-port
export LD_LIBRARY_PATH="/root/miniconda3/lib/python3.10/site-packages/nvidia/nvshmem/lib:${LD_LIBRARY_PATH:-}"
export NVSHMEM_SYMMETRIC_SIZE=2G CUDA_VISIBLE_DEVICES=0,1,2,3
OUT="results/p19_bracketing_$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$OUT"
STATUS=/root/agent-mailbox/20260904_ZCode-P19运行状态.md
echo "# P19 运行状态" > "$STATUS"

# 1) 生成洗牌 schedule（seed 固定，先落盘封存）
python3 - "$OUT" <<'EOF'
import random, sys, csv
out=sys.argv[1]
runs=[]
for N,q in [(12288,8),(16384,8),(16384,16),(32768,16)]:
    for path in ('d0','d1'):
        for rep in range(1,6):
            runs.append((N,q,path,rep))
random.seed(20260904)
random.shuffle(runs)
with open(f'{out}/schedule.csv','w',newline='') as f:
    w=csv.writer(f); w.writerow(['order','N','q','path','rep','run_id'])
    for i,(N,q,p,r) in enumerate(runs,1):
        w.writerow([i,N,q,p,r,f'p19_{p}_N{N}_q{q}_rep{r}'])
print(f"schedule: {len(runs)} runs, seed=20260904")
EOF

# 2) 按 schedule 顺序执行
PASS=0; FAIL=0
while IFS=, read -r order N q path rep run_id; do
  [[ "$order" == "order" ]] && continue
  mkdir -p "$OUT/$run_id"
  timeout 1200 mpirun --allow-run-as-root --bind-to none -np 4 -mca coll ^hcoll \
    ./ag_gemm_phaseb_nv --path "$path" --m-local 2048 --n "$N" --k 2048 --q "$q" \
    --warmup 20 --iters 50 --verify-every 1 \
    --output-dir "$OUT/$run_id" --run-id "$run_id" --candidate C0_DEFAULT \
    < /dev/null > "$OUT/$run_id/stdout_stderr.log" 2>&1
  rc=$?
  [[ $rc -eq 0 ]] && PASS=$((PASS+1)) || FAIL=$((FAIL+1))
  echo "$(date -u +%FT%TZ) [$order/40] $run_id rc=$rc (pass=$PASS fail=$FAIL)" >> "$STATUS"
done < "$OUT/schedule.csv"

# 3) 立即判定
python3 - "$OUT" <<'EOF'
import csv, glob, os, sys
out=sys.argv[1]
cells={}
for f in glob.glob(f'{out}/p19_*/raw_global_samples.csv'):
    base=os.path.basename(os.path.dirname(f))
    parts=base.split('_')  # p19 d0 N12288 q8 rep1
    path,N,q=parts[1],int(parts[2][1:]),int(parts[3][1:])
    med=None
    rows=[r for r in csv.DictReader(open(f)) if r['correctness_all_ranks']=='PASS']
    if rows:
        e=sorted(float(r['e2e_max_us']) for r in rows)
        med=e[len(e)//2]
    cells.setdefault((N,q,path),[]).append(med)
print("=== P19 判定（run 级 p50 的中位）===")
results={}
for N,q in [(12288,8),(16384,8),(16384,16),(32768,16)]:
    d0=sorted(v for v in cells.get((N,q,'d0'),[]) if v)
    d1=sorted(v for v in cells.get((N,q,'d1'),[]) if v)
    if d0 and d1:
        pct=100*(d1[len(d1)//2]-d0[len(d0)//2])/d0[len(d0)//2]
        results[(N,q)]=pct
        print(f"  N{N}/q{q}: d1_vs_d0 = {pct:+.1f}%  (d0={d0[len(d0)//2]:.0f}us d1={d1[len(d1)//2]:.0f}us, n={len(d0)}/{len(d1)} runs)")
with open(f'{out}/verdict.csv','w') as f:
    f.write("N,q,d1_vs_d0_pct\n")
    for (N,q),p in results.items(): f.write(f"{N},{q},{p:.2f}\n")
EOF
echo "$(date -u +%FT%TZ) P19_DONE outdir=$OUT" >> "$STATUS"
echo "DONE $OUT"
