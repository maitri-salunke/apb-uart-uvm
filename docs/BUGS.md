# Bugs found

## RTL bugs found by the environment

**None so far.** The RTL in `rtl/` passed every regression run once the
testbench bugs below were fixed: 500 seeds with the default 1-wait-state
configuration and 100 more with `WAIT_STATES = 0`. No assertion fired and
the scoreboard reported no mismatch. I am not going to invent RTL bugs to
fill this file. Two caveats:

- I wrote the RTL and the testbench in the same session, so the same
  misreading of the spec could be in both. The mutation campaign
  (`make mutate`, 14 deliberate RTL bugs) is the evidence that the checkers
  work. It does not prove the RTL is free of bugs.
- One RTL change happened at design time, before any testbench existed, so
  it is not counted as a find: `uart_fifo` originally dropped a push to a
  full FIFO even when a pop happened in the same cycle, which did not match
  the "no overflow when a slot frees up" rule in REGISTERS.md. I fixed it
  while writing the overflow logic (`do_push = push && (!full || pop)`).

## Testbench bugs found while bringing up the environment

Each of these was a real failure (or a coverage hole) in a regression,
debugged to its root cause and fixed in `tb/`:

| # | Symptom | Root cause | Fix |
|---|---|---|---|
| T1 | `cg_flush` RX bins never hit; the "RX flush" step in `fifo_vseq` flushed the TX FIFO instead | The CTRL write concatenation `{22'h0, 2'b10, 3'h0, par_odd, par_en, 2'b11}` was 31 bits wide (the LOOPBACK bit was missing), so the flush bits moved down one position | Added the missing `1'b0` for LOOPBACK |
| T2 | `uart_reg_test` seeds 41 and 51: RAL `mirror()` mismatch on INT_EN (read 0x38, mirror 0x00) | `apb_random_seq` now issues unaligned addresses (the DUT ignores PADDR[1:0], as specified), but the adapter passed the raw address to the predictor, which found no register at 0x011 and skipped the prediction | `bus2reg` masks `addr[1:0]` |
| T3 | `uart_slow_baud_test`: 5 of 20 seeds, "received 0 frames"; DUT and RX monitor both flagged a parity error on a frame the driver meant to be good | Race in the driver: it read `cfg.par_odd` at task entry, before the scoreboard had applied the CTRL write to `uart_cfg` (the update lands one cycle after the APB transfer), so it computed even parity for an 8O1 frame | Driver reads the config at the start bit; `configure()` waits 2 cycles after the CTRL write |
| T4 | DIV = 0, RX_THR = 0 and RX_THR = 16 bins unhit after 45 seeds | `dist { [1:3] := 6, ... }` gives every value in a range the full weight, so the single values (0, 16) got about 1/74 of the draws | Changed range weights to `:/` |
| T5 | `uart_slow_baud_test` failed randomization on every seed | The new `div inside {[1024:2100]}` constraint conflicted with the base class `dist` constraint on `div` (0..40) | Override the base constraint by name (`c_div`) in the derived sequence |
| T6 | `cg_w1c.<rx_ovf,keep>` unhit | The W1C loop cleared bit 2 first, so RX_OVF was never set while other bits were being cleared | Clear from bit 5 down to bit 2 |

## Tool issues worked around (not bugs in this project)

- The UVM DPI C code includes `<malloc.h>`, which macOS does not have:
  `tb/compat/malloc.h` forwards to `<stdlib.h>`.
- The UVM DPI uses VPI for `uvm_hdl_*`; Verilator needs `--vpi` to link it.
- Verilator 5.054 does not support `get_coverage()` on a single coverpoint or
  cross (it does support it on the whole covergroup). Per-bin numbers come
  from `coverage.dat` instead (`scripts/coverage_report.py`).
