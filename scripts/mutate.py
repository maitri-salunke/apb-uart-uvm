#!/usr/bin/env python3
"""Bug-injection (mutation) campaign.

Each mutation is a deliberate RTL bug behind `ifdef MUT_<NAME>` in rtl/.
For every mutation the testbench is rebuilt with +define+MUT_<NAME> (no code
coverage, for speed) and the same fixed regression is run: every test with
seeds 1..SEEDS. A mutation is "caught" if at least one run fails (scoreboard
mismatch, SVA failure, UVM_ERROR/FATAL or timeout). Results go to
logs/mutate/results.md.
"""
import argparse
import os
import re
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(__file__))
from regress import TESTS, run_one  # noqa: E402

MUTATIONS = [
    ("FIFO_LEVEL",        "uart_fifo.sv",     "simultaneous push+pop decrements the level"),
    ("BAUD_OFF_BY_ONE",   "uart_baud_gen.sv", "baud divider terminal count one short"),
    ("PARITY_INV",        "uart_tx.sv",       "TX parity sense inverted"),
    ("TX_MSB_FIRST",      "uart_tx.sv",       "TX shifts MSB first"),
    ("TX_STOP_SHORT",     "uart_tx.sv",       "TX stop bit half length"),
    ("RX_NO_FRAME_CHECK", "uart_rx.sv",       "RX ignores the stop bit (no framing error)"),
    ("PREADY_HANG",       "apb_uart.sv",      "PREADY never asserted for writes to RX_THR"),
    ("NO_PSLVERR",        "apb_uart.sv",      "unmapped addresses accepted without PSLVERR"),
    ("RX_OVF_NOSET",      "apb_uart.sv",      "RX overflow sticky bit never set"),
    ("CTRL_RESET",        "apb_uart.sv",      "CTRL resets with RX disabled"),
    ("W1C_AS_RW",         "apb_uart.sv",      "INT_STAT is plain RW, writing 0 clears"),
    ("RX_THR_GT",         "apb_uart.sv",      "RX threshold compares > instead of >="),
    ("STATUS_SWAP",       "apb_uart.sv",      "STATUS TX_FULL/TX_EMPTY bits swapped"),
    ("LOOPBACK_BROKEN",   "apb_uart.sv",      "loopback mux ignores CTRL.LOOPBACK"),
]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--jobs", type=int, default=4)
    ap.add_argument("--seeds", type=int, default=2)
    ap.add_argument("--only", default="")
    ap.add_argument("--timeout", type=int, default=300)
    a = ap.parse_args()
    jobs = min(a.jobs, 4)
    muts = [m for m in MUTATIONS if not a.only or m[0] in a.only.split(",")]
    root = "logs/mutate"
    os.makedirs(root, exist_ok=True)
    rows = []
    for name, f, desc in muts:
        bdir = f"build/mut_{name}"
        t0 = time.time()
        r = subprocess.run(["make", "-s", "build", f"BUILD={bdir}", f"DEFINES=MUT_{name}", "COV=0",
                            f"JOBS={jobs}"], capture_output=True, text=True)
        if r.returncode:
            print(r.stdout[-2000:], r.stderr[-2000:])
            sys.exit(f"build failed for {name}")
        out = os.path.join(root, name)
        os.makedirs(out, exist_ok=True)
        from concurrent.futures import ThreadPoolExecutor
        runs = [(t, s) for t in TESTS for s in range(1, a.seeds + 1)]
        with ThreadPoolExecutor(max_workers=jobs) as ex:
            res = list(ex.map(lambda ts: run_one(f"{bdir}/Vtb_top", ts[0], ts[1], out, a.timeout, False), runs))
        fails = [x for x in res if x["status"] != "PASS"]
        killers = sorted({x["test"] for x in fails})
        first = fails[0]["reason"] if fails else ""
        m = re.search(r"\[([A-Z0-9_]+)\]", first)
        sig = m.group(1) if m else first[:60]
        if "Assertion failed" in first:
            m2 = re.search(r"(A\d\d_\w+)|APB A\d\d|DUT A\d\d", first)
            sig = "SVA " + (m2.group(0) if m2 else "")
        rows.append((name, f, desc, bool(fails), len(fails), len(res), killers, sig, first))
        print(f"{name:<18} {'CAUGHT' if fails else 'missed'} {len(fails)}/{len(res)} failing  "
              f"({time.time() - t0:.0f}s)  {sig}", flush=True)
    caught = sum(r[3] for r in rows)
    with open(os.path.join(root, "results.md"), "w") as fh:
        fh.write(f"# Mutation campaign: {caught}/{len(rows)} caught\n\n")
        fh.write(f"Each mutant: {len(TESTS)} tests x seeds 1..{a.seeds}.\n\n")
        fh.write("| Mutation | File | Bug | Result | Failing runs | First detector |\n|---|---|---|---|---|---|\n")
        for name, f, desc, c, nf, nt, k, sig, first in rows:
            fh.write(f"| MUT_{name} | {f} | {desc} | {'caught' if c else '**missed**'} | {nf}/{nt} | {sig} |\n")
        fh.write("\nFirst failure message per mutant:\n\n")
        for name, *_rest in rows:
            fh.write(f"- MUT_{name}: `{_rest[-1]}`\n")
    print(f"caught {caught}/{len(rows)} -> {root}/results.md")


if __name__ == "__main__":
    main()
