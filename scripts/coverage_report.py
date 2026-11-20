#!/usr/bin/env python3
"""Merge Verilator coverage files and report functional + code coverage.

Functional coverage: SystemVerilog covergroup bins that Verilator 5.054
writes into coverage.dat (page v_covergroup/...). Coverage of a coverpoint or
cross = hit bins / bins (ignore/illegal bins excluded); covergroup = mean of
its coverpoints and crosses; total = mean of the covergroups, the same
formula as get_coverage() / uart_coverage::total() in the testbench.

Code coverage: Verilator line (statement blocks incl. if/else/case arms)
and toggle points whose source file is under rtl/. Waivers, if any, come from
scripts/cov_waivers.txt (regex on the point description, with a reason) and
are reported separately from the raw number.
"""
import glob
import os
import re
import subprocess
import sys
from collections import defaultdict


def parse_key(k):
    d = {}
    for part in k.split("\x01"):
        if "\x02" in part:
            a, b = part.split("\x02", 1)
            d[a] = b
    return d


def load(paths):
    merged = defaultdict(int)
    for p in paths:
        with open(p, errors="replace") as f:
            for line in f:
                if not line.startswith("C '"):
                    continue
                key, cnt = line[3:].rsplit("' ", 1)
                merged[key] += int(cnt)
    return merged


def load_waivers(path):
    w = []
    if os.path.exists(path):
        for line in open(path):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            pat, _, why = line.partition("  #")
            w.append((re.compile(pat.strip()), why.strip()))
    return w


def main():
    d = sys.argv[1] if len(sys.argv) > 1 else "logs/regress"
    files = sorted(glob.glob(os.path.join(d, "*.dat")))
    if not files:
        sys.exit(f"no .dat files in {d}")
    cov = load(files)
    out_dir = os.path.join(d, "coverage")
    os.makedirs(out_dir, exist_ok=True)

    # ---------------- functional
    groups = defaultdict(lambda: defaultdict(dict))   # group -> item -> bin -> count
    for k, c in cov.items():
        f = parse_key(k)
        if f.get("t") != "covergroup":
            continue
        if f.get("Bt") in ("ignore", "illegal"):
            continue
        g = f["page"].split("/", 1)[1]
        rest = f["h"][len(g) + 1:]
        item, _, b = rest.partition(".")
        groups[g][item][b] = c
    lines = ["# Functional coverage (merged over %d runs)" % len(files), ""]
    gsum = 0.0
    holes = []
    for g in sorted(groups):
        items = groups[g]
        pct = [100.0 * sum(1 for v in bins.values() if v) / len(bins) for bins in items.values()]
        gc = sum(pct) / len(pct)
        gsum += gc
        short = g.split("::")[-1]
        lines.append(f"{short:<14} {gc:6.2f}%  ({len(items)} coverpoints/crosses, "
                     f"{sum(len(b) for b in items.values())} bins)")
        for it, bins in items.items():
            for b, v in bins.items():
                if not v:
                    holes.append(f"{short}.{it}.{b}")
    total = gsum / len(groups) if groups else 0.0
    lines.append(f"{'TOTAL':<14} {total:6.2f}%  ({len(groups)} covergroups)")
    lines.append("")
    lines.append(f"Uncovered bins: {len(holes)}")
    lines += ["  " + h for h in holes]

    # ---------------- code (rtl/ only)
    waivers = load_waivers("scripts/cov_waivers.txt")
    lines += ["", "# Code coverage, rtl/ only", ""]
    code = {}
    misses = defaultdict(list)
    for kind in ("line", "toggle"):
        per_file = defaultdict(lambda: [0, 0, 0, 0])   # hit, total, waived, waived_hit
        for k, c in cov.items():
            f = parse_key(k)
            if f.get("t") != kind or not f.get("f", "").startswith("rtl/"):
                continue
            desc = f"{f['f']}:{f['l']} {f.get('o', '')} {f.get('h', '')}"
            pf = per_file[f["f"]]
            waived = next((why for pat, why in waivers if pat.search(desc)), None)
            if waived:
                pf[2] += 1
                pf[3] += 1 if c else 0
                continue
            pf[1] += 1
            pf[0] += 1 if c else 0
            if not c:
                misses[kind].append(desc)
        hit = sum(v[0] for v in per_file.values())
        tot = sum(v[1] for v in per_file.values())
        wv = sum(v[2] for v in per_file.values())
        raw_hit = hit + sum(v[3] for v in per_file.values())
        raw_tot = tot + wv
        code[kind] = (hit, tot, raw_hit, raw_tot, wv)
        lines.append(f"{kind:<7} raw {100.0 * raw_hit / raw_tot:6.2f}% ({raw_hit}/{raw_tot})   "
                     f"after waivers {100.0 * hit / tot:6.2f}% ({hit}/{tot}, {wv} points waived)")
        for fn in sorted(per_file):
            h, t, w, _ = per_file[fn]
            lines.append(f"    {fn:<24} {100.0 * h / t if t else 100.0:6.2f}% ({h}/{t})" + (f"  waived {w}" if w else ""))
    for kind in ("line", "toggle"):
        lines.append(f"\nUnhit {kind} points (not waived): {len(misses[kind])}")
        lines += ["  " + m for m in misses[kind][:200]]
    if waivers:
        lines.append("\nWaivers (scripts/cov_waivers.txt):")
        lines += [f"  {p.pattern}  -- {w}" for p, w in waivers]

    rep = "\n".join(lines) + "\n"
    open(os.path.join(out_dir, "report.txt"), "w").write(rep)
    # machine-readable summary
    with open(os.path.join(out_dir, "summary.txt"), "w") as f:
        f.write(f"runs={len(files)}\nfunctional={total:.2f}\n")
        for kind, (h, t, rh, rt, wv) in code.items():
            f.write(f"{kind}_raw={100.0 * rh / rt:.2f}\n{kind}_waived={100.0 * h / t:.2f}\n")
    # merged file + annotated RTL for humans
    merged = os.path.join(out_dir, "merged.dat")
    subprocess.run(["verilator_coverage", "--write", merged] + files, check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["verilator_coverage", "--annotate", os.path.join(out_dir, "annotated"), merged],
                   check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print(rep[: rep.find("Uncovered bins")] + rep[rep.find("# Code coverage"): rep.find("\nUnhit line")])
    print(f"full report: {os.path.join(out_dir, 'report.txt')}")


if __name__ == "__main__":
    main()
