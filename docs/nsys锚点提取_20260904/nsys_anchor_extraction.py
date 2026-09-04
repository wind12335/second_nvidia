#!/usr/bin/env python3
"""JM-H anchor extraction from nsys forensics traces (2026-09-04).

For each of the 7 sealed traces: export to sqlite, pull kernel events
(device 0, excluding symmetric-heap init), and compute anchor-relevant
microsecond statistics keyed to JM-H3/H4/H5/H7.
"""

from __future__ import annotations

import json
import re
import subprocess
import sqlite3
import statistics
from pathlib import Path

SRC = Path("/root/seconde-paper/work-20260903/nssys_placeholder")
SRC = Path("/root/seconde-paper/work-20260903/nsys取证")
OUT = Path("/root/second_nvidia/docs/nsys锚点提取_20260904")
OUT.mkdir(parents=True, exist_ok=True)

TRACES = {
    "01_d0_N2048_q8": {"kind": "d0"},
    "02_r1_N2048_q8": {"kind": "r1_loser"},
    "03_r1_N512_q8": {"kind": "r1_winner"},
    "04_d1_N4096_q8": {"kind": "d1"},
    "00_w0_S1_q16": {"kind": "w0"},
    "01_w1_S1_q16": {"kind": "w1"},
    "08_w8_S1_q16": {"kind": "w8"},
}

INIT_PAT = re.compile(r"nvshmemi_init_array|memset", re.I)
GEMM_PAT = re.compile(r"sgemm|gemm", re.I)
NCCL_PAT = re.compile(r"nccl", re.I)
BARRIER_PAT = re.compile(r"barrier", re.I)
SIGNAL_PAT = re.compile(r"signal|wait|fcollect|putmem|stream_wait|event", re.I)


def export_sqlite(rep: Path, dst: Path) -> None:
    if dst.exists():
        return
    subprocess.run(
        ["nsys", "export", "--type", "sqlite", "--force-overwrite", "true",
         "--output", str(dst), str(rep)],
        check=True, capture_output=True, timeout=600,
    )


def kernel_events(db: Path):
    con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    rows = con.execute(
        "SELECT k.start, k.end, s.value FROM CUPTI_ACTIVITY_KIND_KERNEL k "
        "JOIN StringIds s ON k.demangledName = s.id ORDER BY k.start"
    ).fetchall()
    con.close()
    evts = []
    for start, end, name in rows:
        if INIT_PAT.search(name or ""):
            continue
        evts.append({"start": start, "end": end, "name": name or "?"})
    return evts


def gap_stats(pairs):
    if not pairs:
        return None
    us = sorted((e - s) / 1000.0 for s, e in pairs)
    return {
        "n": len(us), "p50_us": round(statistics.median(us), 2),
        "p10_us": round(us[max(0, int(0.1 * len(us)) - 1)], 2),
        "p90_us": round(us[min(len(us) - 1, int(0.9 * len(us)))], 2),
        "min_us": round(us[0], 2), "max_us": round(us[-1], 2),
    }


def next_gap(a_evts, b_evts):
    """for each a-end, gap to first b-start after it"""
    pairs, bstarts = [], sorted(e["start"] for e in b_evts)
    import bisect
    for a in a_evts:
        i = bisect.bisect_right(bstarts, a["end"])
        if i < len(bstarts):
            pairs.append((a["end"], bstarts[i]))
    return gap_stats(pairs)


def overlap_fraction(evts_a, evts_b):
    if not evts_a or not evts_b:
        return None
    spans = [(max(a["start"], b["start"]), min(a["end"], b["end"]))
             for a in evts_a for b in evts_b
             if a["start"] < b["end"] and b["start"] < a["end"]]
    if not spans:
        return 0.0
    spans.sort()
    total, cs, ce = 0, None, None
    for s, e in spans:
        if cs is None:
            cs, ce = s, e
        elif s <= ce:
            ce = max(ce, e)
        else:
            total += ce - cs
            cs, ce = s, e
    total += ce - cs
    cover_a = sum(a["end"] - a["start"] for a in evts_a)
    return round(total / cover_a, 4) if cover_a else None


def summarize(kind, evts):
    gemm = [e for e in evts if GEMM_PAT.search(e["name"]) and not NCCL_PAT.search(e["name"])]
    nccl = [e for e in evts if NCCL_PAT.search(e["name"])]
    barrier = [e for e in evts if BARRIER_PAT.search(e["name"])]
    out = {
        "counts": {"gemm": len(gemm), "nccl": len(nccl),
                   "barrier_like": len(barrier),
                   "total_kernels": len(evts)},
        "gemm_names": sorted({e["name"].split("(")[0][:48] for e in gemm})[:4],
    }
    if kind == "d0":
        out["H3_d0_gap_ncclend_to_gemmstart"] = next_gap(nccl, gemm)
        out["H7_gemm_durations_us"] = gap_stats(
            [(e["start"], e["end"]) for e in gemm])
    elif kind.startswith("r1"):
        out["H3_r1_gap_ncclend_to_gemmstart"] = next_gap(nccl, gemm)
        out["H3_r1_gap_gemmend_to_ncclstart"] = next_gap(gemm, nccl)
        out["H4_nccl_durations_us"] = gap_stats(
            [(e["start"], e["end"]) for e in nccl])
        out["H4_gemm_durations_us"] = gap_stats(
            [(e["start"], e["end"]) for e in gemm])
        out["H7_overlap_fraction_gemmdur_covered_by_nccl"] = overlap_fraction(gemm, nccl)
    elif kind == "d1":
        out["H3_d1_gap_barrierend_to_gemmstart"] = next_gap(barrier, gemm)
        out["H4_barrier_durations_us"] = gap_stats(
            [(e["start"], e["end"]) for e in barrier])
        out["H4_gemm_durations_us"] = gap_stats(
            [(e["start"], e["end"]) for e in gemm])
    elif kind in ("w0", "w1", "w8"):
        out["H5_nccl_durations_us"] = gap_stats(
            [(e["start"], e["end"]) for e in nccl])
        out["H5_gemm_durations_us"] = gap_stats(
            [(e["start"], e["end"]) for e in gemm])
        out["H5_overlap_fraction_gemmdur_covered_by_nccl"] = overlap_fraction(gemm, nccl)
        out["H5_gap_gemmend_to_ncclstart"] = next_gap(gemm, nccl)
    return out


def main() -> int:
    report = {}
    for stem, meta in TRACES.items():
        rep = next(SRC.glob(f"{stem}*.nsys-rep"), None)
        if rep is None:
            report[stem] = {"error": "nsys-rep not found"}
            continue
        db = OUT / f"{stem}.sqlite"
        try:
            export_sqlite(rep, db)
            evts = kernel_events(db)
            report[stem] = {"kind": meta["kind"], **summarize(meta["kind"], evts)}
            print(f"OK {stem}")
        except Exception as exc:  # noqa: BLE001
            report[stem] = {"kind": meta["kind"], "error": repr(exc)[:200]}
            print(f"ERR {stem}: {exc}")
    (OUT / "anchor_extraction_summary.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print("summary ->", OUT / "anchor_extraction_summary.json")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
