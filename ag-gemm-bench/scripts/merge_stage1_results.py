#!/usr/bin/env python3
"""Merge stage1 matrix case dirs into one consolidated CSV + ranking analysis.

Reads <output_root>/run_manifest.csv (written by run_stage1_full.sh) and each
case's summary.csv (written by ag_gemm_bench). Produces:
  - stage1_runs_merged.csv   one row per (run_id, strategy)
  - stage1_pivot.md          per (shape,q,candidate,window) strategy pivots
  - stage1_ranking.md        H1 ranking-reversal audit (same-q B1 vs B2, and
                             candidate ranking by isolated-comm vs by e2e)
"""
import csv
import sys
from pathlib import Path
from statistics import mean, stdev

def fmt(x, nd=3):
    return f"{x:.{nd}f}" if isinstance(x, (int, float)) else str(x)

def main(output_root: str) -> None:
    root = Path(output_root)
    manifest = root / "run_manifest.csv"
    rows = []
    with manifest.open() as f:
        for m in csv.DictReader(f):
            case_dir = Path(m["case_dir"])
            summary = case_dir / "summary.csv"
            if not summary.exists():
                rows.append({**m, "strategy": "MISSING_SUMMARY", "note": summary})
                continue
            with summary.open() as sf:
                for s in csv.DictReader(sf):
                    r = dict(m)
                    r["strategy"] = s["strategy"]
                    r["status"] = s["status"]
                    r["correctness"] = s["correctness"]
                    r["max_abs_error"] = s["max_abs_error"]
                    r["M_global"] = s["M"]
                    r["slice_bytes"] = s["slice_bytes"]
                    for k in ("release_first_mean_us", "release_first_p50_us",
                              "release_first_p95_us", "release_last_mean_us",
                              "done_mean_us", "done_p50_us", "done_p95_us",
                              "gemm_first_mean_us", "gemm_last_mean_us",
                              "e2e_mean_us", "e2e_p50_us", "e2e_p95_us"):
                        r[k] = float(s[k])
                    rows.append(r)

    out_csv = root / "stage1_runs_merged.csv"
    fields = ["stage", "candidate", "shape_id", "category", "local_rows", "K", "N",
              "q", "window", "repetition", "strategy", "status", "correctness",
              "M_global", "slice_bytes",
              "release_first_mean_us", "release_last_mean_us", "done_mean_us",
              "gemm_first_mean_us", "gemm_last_mean_us", "e2e_mean_us",
              "e2e_p50_us", "e2e_p95_us", "run_id"]
    with out_csv.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields, extrasaction="ignore")
        w.writeheader()
        w.writerows(rows)
    print(f"wrote {out_csv} ({len(rows)} rows)")

    # group: (stage,candidate,shape,q,window) -> strategy -> list of rep rows
    groups = {}
    for r in rows:
        if "e2e_mean_us" not in r:
            continue
        key = (r["stage"], r["candidate"], r["shape_id"], int(r["q"]), int(r["window"]))
        groups.setdefault(key, {}).setdefault(r["strategy"], []).append(r)

    pivot_lines = [
        "# Stage1 pivot (mean over reps; e2e/done/release in us)",
        "",
        "| stage | cand | shape | q | w | B0_e2e | B1_e2e | B2_e2e | B2/B1 | B2_release_last | B2_done | slice_B |",
        "|---|---|---|---|---|---|---|---|---|---|---|---|",
    ]
    rank_lines = [
        "# H1 ranking audit",
        "",
        "## A. Same-q B2 vs B1 (red-line compliant comparison)",
        "",
        "gain = B1_e2e / B2_e2e (>1 means overlap wins at this q)",
        "",
        "| shape | q | w | cand | B1_e2e | B2_e2e | gain | sig |",
        "|---|---|---|---|---|---|---|---|",
    ]
    for key in sorted(groups):
        stage, cand, shape, q, w = key
        g = groups[key]
        def agg(st, field):
            vals = [r[field] for r in g.get(st, [])]
            return (mean(vals), stdev(vals) if len(vals) > 1 else 0.0, len(vals)) if vals else (None, None, 0)
        b0, b0s, n0 = agg("B0_FULL_SERIAL", "e2e_mean_us")
        b1, b1s, n1 = agg("B1_SLICE_SERIAL", "e2e_mean_us")
        b2, b2s, n2 = agg("B2_SLICE_EVENT_OVERLAP", "e2e_mean_us")
        rlast, _, _ = agg("B2_SLICE_EVENT_OVERLAP", "release_last_mean_us")
        done, _, _ = agg("B2_SLICE_EVENT_OVERLAP", "done_mean_us")
        sb = next((r["slice_bytes"] for st in g.values() for r in st), "?")
        if None not in (b0, b1, b2):
            pivot_lines.append(f"| {stage} | {cand} | {shape} | {q} | {w} | {fmt(b0,1)} | {fmt(b1,1)} | {fmt(b2,1)} | {fmt(b1/b2,3)} | {fmt(rlast,1)} | {fmt(done,1)} | {sb} |")
            # significance: gain with stdev of both
            sig = ""
            if b2 > 0 and b2s is not None:
                delta = b1 - b2
                noise = (b1s + b2s) if (b1s or b2s) else 1e-9
                sig = "YES" if abs(delta) > 2 * max(noise, 1e-9) and n1 >= 2 and n2 >= 2 else "no"
            rank_lines.append(f"| {shape} | {q} | {w} | {cand} | {fmt(b1,1)}±{fmt(b1s,1)} | {fmt(b2,1)}±{fmt(b2s,1)} | {fmt(b1/b2,3)} | {sig} |")

    # B. candidate ranking reversal (stage B): rank by done (isolated-ish comm) vs by e2e (B2)
    rank_lines += ["", "## B. Candidate ranking: by B2 T_done vs by B2 T_e2e (stage B only)", "",
                   "| shape | q | rank_by_done | rank_by_e2e | REVERSED |", "|---|---|---|---|---|"]
    cand_groups = {}
    for r in rows:
        if r.get("stage") != "B" or r.get("strategy") != "B2_SLICE_EVENT_OVERLAP":
            continue
        ck = (r["shape_id"], int(r["q"]))
        cand_groups.setdefault(ck, {}).setdefault(r["candidate"], []).append(r)
    for ck in sorted(cand_groups):
        shape, q = ck
        by_done, by_e2e = [], []
        for cand, rs in cand_groups[ck].items():
            by_done.append((mean(x["done_mean_us"] for x in rs), cand))
            by_e2e.append((mean(x["e2e_mean_us"] for x in rs), cand))
        rd = [c for _, c in sorted(by_done)]
        re_ = [c for _, c in sorted(by_e2e)]
        rank_lines.append(f"| {shape} | {q} | {'>'.join(rd)} | {'>'.join(re_)} | {'YES' if rd != re_ else 'no'} |")

    # C. q ranking reversal under DEFAULT: best q by T_done vs by T_e2e (stage A)
    rank_lines += ["", "## C. q ranking: best-q by B2 T_done vs by B2 T_e2e (stage A, DEFAULT)", "",
                   "| shape | rank_by_done | rank_by_e2e | best differs |", "|---|---|---|---|"]
    q_groups = {}
    for r in rows:
        if r.get("stage") != "A" or r.get("strategy") != "B2_SLICE_EVENT_OVERLAP":
            continue
        q_groups.setdefault(r["shape_id"], {}).setdefault(int(r["q"]), []).append(r)
    for shape in sorted(q_groups):
        by_done = sorted((mean(x["done_mean_us"] for x in rs), q) for q, rs in q_groups[shape].items())
        by_e2e = sorted((mean(x["e2e_mean_us"] for x in rs), q) for q, rs in q_groups[shape].items())
        rd = ">".join(f"q{q}" for _, q in by_done)
        re_ = ">".join(f"q{q}" for _, q in by_e2e)
        rank_lines.append(f"| {shape} | {rd} | {re_} | {'YES' if by_done[0][1] != by_e2e[0][1] else 'no'} |")

    (root / "stage1_pivot.md").write_text("\n".join(pivot_lines) + "\n")
    (root / "stage1_ranking.md").write_text("\n".join(rank_lines) + "\n")
    print(f"wrote {root/'stage1_pivot.md'} and {root/'stage1_ranking.md'}")

if __name__ == "__main__":
    main(sys.argv[1])
