#!/usr/bin/env python3
"""Seeded regression runner for the apb_uart UVM testbench.

Runs N simulations (round-robin over the test list, seed = 1..N unless
--seeds is given), at most --jobs in parallel, each with its own coverage
file. A run passes only if the log has "TEST PASSED", zero UVM_ERROR /
UVM_FATAL, and no Verilator %Error (SVA failure, $fatal, timeout).
Writes <out>/results.csv and <out>/summary.txt.
"""
import argparse
import csv
import os
import re
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor

TESTS = [
    "uart_reg_test", "uart_tx_test", "uart_rx_test", "uart_fifo_test",
    "uart_loopback_test", "uart_irq_test", "uart_duplex_test",
    "uart_apb_rand_test", "uart_rand_test", "uart_slow_baud_test",
]


def run_one(sim, test, seed, out, timeout, cov):
    log = os.path.join(out, f"{test}_s{seed}.log")
    cmd = [sim, f"+UVM_TESTNAME={test}", f"+verilator+seed+{seed}",
           "+UVM_NO_RELNOTES", "+UVM_VERBOSITY=UVM_LOW"]
    if cov:
        cmd.append(f"+verilator+coverage+file+{os.path.join(out, f'{test}_s{seed}.dat')}")
    t0 = time.time()
    status = "PASS"
    reason = ""
    try:
        with open(log, "w") as f:
            subprocess.run(cmd, stdout=f, stderr=subprocess.STDOUT, timeout=timeout, check=False)
    except subprocess.TimeoutExpired:
        status, reason = "FAIL", "wallclock timeout"
    dt = time.time() - t0
    text = open(log, errors="replace").read()
    m_err = re.search(r"UVM_ERROR :\s+(\d+)", text)
    m_fat = re.search(r"UVM_FATAL :\s+(\d+)", text)
    if status == "PASS":
        if "%Error" in text:
            status = "FAIL"
            reason = next(l for l in text.splitlines() if "%Error" in l).strip()
        elif not m_err or int(m_err.group(1)) or int(m_fat.group(1)) or "TEST PASSED" not in text:
            status = "FAIL"
            first = re.search(r"^(UVM_(ERROR|FATAL) .*)$", text, re.M)
            reason = first.group(1) if first else "no TEST PASSED"
    fc = re.search(r"FUNCTIONAL_COVERAGE_THIS_RUN=([\d.]+)", text)
    sb = re.search(r"\[SB\] checks=(\d+) errors=(\d+)", text)
    return {
        "test": test, "seed": seed, "status": status, "secs": f"{dt:.1f}",
        "fcov_run": fc.group(1) if fc else "",
        "sb_checks": sb.group(1) if sb else "",
        "reason": reason[:200],
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sim", default="build/sim/Vtb_top")
    ap.add_argument("--n", type=int, default=50)
    ap.add_argument("--seed0", type=int, default=1)
    ap.add_argument("--jobs", type=int, default=4)
    ap.add_argument("--tests", default=",".join(TESTS))
    ap.add_argument("--out", default="logs/regress")
    ap.add_argument("--timeout", type=int, default=600)
    ap.add_argument("--no-cov", action="store_true")
    ap.add_argument("--quiet", action="store_true")
    a = ap.parse_args()
    tests = [t for t in a.tests.split(",") if t]
    os.makedirs(a.out, exist_ok=True)
    for f in os.listdir(a.out):
        if f.endswith((".dat", ".log")):
            os.remove(os.path.join(a.out, f))
    jobs = [(tests[i % len(tests)], a.seed0 + i) for i in range(a.n)]
    jobs_n = min(a.jobs, 4)
    t0 = time.time()
    results = []
    with ThreadPoolExecutor(max_workers=jobs_n) as ex:
        futs = [ex.submit(run_one, a.sim, t, s, a.out, a.timeout, not a.no_cov) for t, s in jobs]
        for fu in futs:
            r = fu.result()
            results.append(r)
            if not a.quiet:
                print(f"{r['status']}  {r['test']:<20} seed={r['seed']:<5} {r['secs']:>6}s  {r['reason']}", flush=True)
    with open(os.path.join(a.out, "results.csv"), "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(results[0].keys()))
        w.writeheader()
        w.writerows(results)
    npass = sum(r["status"] == "PASS" for r in results)
    lines = [f"runs={len(results)} pass={npass} fail={len(results) - npass} "
             f"wall={time.time() - t0:.0f}s jobs={jobs_n}"]
    for t in tests:
        rs = [r for r in results if r["test"] == t]
        if rs:
            lines.append(f"  {t:<20} {sum(r['status'] == 'PASS' for r in rs)}/{len(rs)}")
    open(os.path.join(a.out, "summary.txt"), "w").write("\n".join(lines) + "\n")
    print("\n".join(lines))
    sys.exit(0 if npass == len(results) else 1)


if __name__ == "__main__":
    main()
