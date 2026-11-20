# Design notes

Every part of the project, in order: the design, then the testbench from the pins
up, then the flow (regression, coverage, mutations).

## 1. The design (rtl/)

```
             +---------------------------- apb_uart ----------------------------+
 PSEL  ----->|  APB slave: 1 wait state, decode, PSLVERR                         |
 PENABLE --->|     |                                                             |
 PADDR ----->|     +--> CTRL / BAUD / INT_EN / RX_THR registers                  |
 PWDATA ---->|     |                                                             |
 PRDATA <----|     +--> DATA write --> [TX FIFO 16x8] --> uart_tx --+--> txd     |
 PREADY <----|     |                                   ^            | loopback   |
 PSLVERR <---|     |                    uart_baud_gen --+ tick16     v            |
             |     +<-- DATA read  <-- [RX FIFO 16x8] <-- uart_rx <-+-- rxd      |
 irq   <-----|  INT_STAT (sticky W1C + level bits) & INT_EN                      |
             +-------------------------------------------------------------------+
```

- **apb_uart.sv** (top). The APB slave holds PREADY low for `WAIT_STATES`
  cycles of every access, then completes. All side effects (FIFO push/pop,
  register write, W1C) happen once, in the cycle where
  `PSEL & PENABLE & PREADY`. An unmapped address or a write to the read-only
  STATUS register gets PSLVERR and has no effect. Sticky status bits use
  "set wins over clear" when a hardware event and a W1C write hit the same
  cycle. `irq = |(INT_STAT & INT_EN)`.
- **uart_fifo.sv**. Single-clock FIFO with an explicit occupancy counter
  (`level`, 0..16), first-word fall-through read data. A push to a full FIFO is
  ignored unless a pop happens in the same cycle.
- **uart_baud_gen.sv**. Free-running counter that emits `tick16` every
  `DIV+1` clocks. One UART bit = 16 ticks. Writing BAUD restarts the counter.
- **uart_tx.sv**. FSM IDLE -> START -> DATA(8) -> [PARITY] -> STOP. A frame
  starts only on a tick so the start bit is exactly 16 ticks long; the byte is
  popped from the TX FIFO at that moment.
- **uart_rx.sv**. `rxd` comes from another clock domain, so it goes through a
  two-flop synchronizer first. A falling edge in IDLE starts a frame; the
  receiver samples the 7th, 8th and 9th tick of every bit and takes a majority
  vote. A start bit that is high at mid-bit is a glitch and is ignored. The
  stop bit is checked at its middle and the FSM returns to IDLE at once, which
  leaves half a bit of slack for a remote transmitter running slightly fast.
  A low stop bit is a framing error; a parity mismatch with a good stop bit is
  a parity error; either way the byte is dropped and a sticky flag set.

Register map and field details: [REGISTERS.md](REGISTERS.md).

## 2. Testbench architecture (tb/)

```
 uart_base_test  (selects a virtual sequence via the factory)
   uart_env
   |-- apb_agent   [sqr -> drv]  ---- apb_if ----+
   |       mon --(ap)--+------------------------ |------> uvm_reg_predictor --> RAL (uart_reg_block)
   |                   +--> scoreboard.apb_fifo  |                                ^
   |-- uart_agent  [sqr -> drv] --- uart_if.rxd  |  DUT                           | front door
   |       rx_mon (rxd) --(ap)--> scoreboard     |                                | (apb_reg_adapter)
   |       tx_mon (txd_int) --(start_ap, ap)--> scoreboard                         |
   |       drv --(drv_ap)--> scoreboard -> coverage (stimulus)                     |
   |-- uart_scoreboard (reference model) --> uart_coverage (10 covergroups)        |
   |-- uart_vsequencer {apb_sqr, uart_sqr, regmodel, cfg} ---- virtual sequences --+
 tb_top: clock/reset, DUT, interfaces, apb_sva (A01-A14, C01-C05), bind uart_dut_sva (A15-A21)
```

### APB agent (`tb/apb/apb_pkg.sv`)
- `apb_item`: direction, address, data, number of idle cycles before the
  transfer (constrained: 0 most often, so back-to-back transfers happen), and
  the response fields (PSLVERR, wait states, irq).
- `apb_driver`: drives at posedge+1 ns so nothing races the DUT's flops. It
  uses `try_next_item` at every clock edge: if a new item is ready right after
  a completed transfer it goes straight to SETUP with PSEL still high, which
  is how back-to-back APB transfers look; otherwise the bus idles.
- `apb_monitor`: samples on the falling edge, publishes one item per
  completed transfer (PSEL & PENABLE & PREADY) with the wait-state count and
  whether it was back-to-back.
- `apb_random_seq`: random accesses over the whole 4 KB window, including
  unaligned and unmapped addresses (DATA is excluded because reads/writes
  there have side effects owned by the directed parts of the test).

### UART agent (`tb/uart/uart_pkg.sv`)
- `uart_cfg`: divisor, parity, loopback. One object shared by the driver,
  both monitors and the scoreboard; the scoreboard updates it when it sees
  CTRL/BAUD written, so the serial side always follows the register
  programming.
- `uart_item`: data, frame kind (good, framing error, parity error, glitch,
  break), baud skew in parts per thousand (-25..+25), idle bits before the
  frame.
- `uart_driver`: places bit edges at `round(k * bit_clks * (1 + skew))`
  cycles from the start edge, i.e. it behaves like a remote transmitter with
  its own, slightly wrong, clock. It also publishes each driven item for
  stimulus coverage.
- `uart_monitor` (two instances): decodes frames on one line by sampling
  every bit at 1/4, 1/2 and 3/4 of its nominal length. The middle sample is
  the value; if the three disagree the bit was not stable over its centre half
  (`timing_err`). On the DUT transmitter this is a real check of the baud
  generator; it also checks the stop bit is still high at 3/4 of its length.
  The TX monitor watches the transmitter output in front of the loopback mux
  (`dut.txd_int`), so loopback traffic can be checked; the pin itself is
  checked by SVA A21. A separate `start_ap` port reports the start edge so the
  model knows the moment the DUT popped its TX FIFO.

### Register model (`tb/ral/uart_ral_pkg.sv`)
- One `uvm_reg` class per register, fields with access policies from the
  spec: `RW`, `RO`, `W1C`, `WO` (flush strobes). Hardware-updated fields are
  marked volatile. DATA is `RW` with `UVM_NO_CHECK` because a write and a read
  touch different FIFOs.
- `apb_reg_adapter` converts `uvm_reg_bus_op` to `apb_item` and back, mapping
  PSLVERR to `UVM_NOT_OK`.
- Prediction is explicit: `set_auto_predict(0)` plus a `uvm_reg_predictor`
  fed by the APB monitor, so the mirror follows what really happened on the
  bus (including accesses not made through the RAL, e.g. `apb_random_seq`).
- Built-in sequences used: `uvm_reg_hw_reset_seq`, `uvm_reg_bit_bash_seq`
  (DATA, STATUS and INT_STAT excluded through `NO_REG_*` resource
  attributes), plus `mirror(UVM_CHECK)`.

### Scoreboard / reference model (`tb/env/uart_env_pkg.sv`)
The scoreboard is a transaction-level model of the UART: queues for the TX
FIFO, the frames in flight, and the RX FIFO, plus the configuration and the
four sticky bits. It checks everything the DUT reports:
- every TX frame against the queue (data, parity, stop bit, bit timing);
- every DATA read against the RX queue;
- every STATUS field (levels, full/empty, busy, reserved bits);
- every register read-back (CTRL, BAUD, INT_EN, RX_THR);
- INT_STAT against the model and the irq pin against INT_STAT & INT_EN;
- PSLVERR on every transfer, and that errored reads return 0.

Timing details that matter:
- APB transactions are processed one clock after the monitor sees them, so a
  TX-FIFO pop in the same clock edge as a DATA write (DUT accepts the write
  into a full FIFO because a slot frees up) is ordered exactly as in the DUT.
- An RX byte reaches the DUT FIFO a few cycles after the monitor decides on
  the stop bit (synchronizer + tick phase). Comparisons that depend on RX
  events younger than `2*(DIV+1)+12` cycles are skipped and counted
  (`skipped_unsettled` in the log), never silently passed. The same applies to
  TX_BUSY within 4 cycles of a frame edge.

### Coverage (`uart_coverage`)
Ten covergroups sampled from the scoreboard and the driver: register x
direction x response, frame configuration (direction x parity mode x divisor
range x loopback), data patterns, RX stimulus (error kind x parity, baud skew
x back-to-back), FIFO level at push and overflow, flushes, interrupt
status x enable x irq, W1C behaviour per sticky bit, RX threshold, TX enable
with data queued. The mapping to the plan is in [VPLAN.md](VPLAN.md).
Verilator 5.054 writes the bins into `coverage.dat`, so the per-run numbers
from `get_coverage()` and the merged numbers from `scripts/coverage_report.py`
use the same formula.

### Assertions (`tb/sva/`)
- `apb_sva.sv` (14 asserts, 5 covers; `C01_zero_wait` can only hit in the
  `WAIT_STATES = 0` build, the others hit in the default build): master rules A01-A10 (no X on PSEL,
  PENABLE needs PSEL, SETUP -> ACCESS, ACCESS holds while waiting, PADDR /
  PWRITE / PWDATA stable, PENABLE drops after completion, no X on control /
  write data), slave rules A11-A14 (PREADY within 16 cycles, PREADY not X,
  PSLVERR only when completing, PRDATA not X on a good read).
- `uart_dut_sva.sv` (7 asserts, bound into `apb_uart` with `bind`): FIFO
  levels never above 16 and change by at most one per cycle (or flush to 0),
  irq is exactly the masked status, txd idles high when the transmitter is
  idle, and the txd pin is high in loopback.

### Virtual sequences and tests (`tb/tests/`)
`uart_base_vseq` has the "firmware" helpers (RAL write/read, configure,
wait-for-TX-idle by polling STATUS, drain RX by reading RX_LEVEL bytes) and
random divisor/parity. Derived sequences: `reg_vseq`, `tx_vseq`, `rx_vseq`,
`fifo_vseq`, `loopback_vseq`, `irq_vseq`, `duplex_vseq`, `apb_rand_vseq`,
`slow_baud_vseq`, and `rand_vseq`, which runs 4-8 of the others back to back
with fresh random settings. Each test class is a two-line wrapper created by
the `UART_TEST` macro; the test is picked at run time with `+UVM_TESTNAME`
(factory), the seed with `+verilator+seed+N`.

## 3. Flow

- `make lint`: `verilator --lint-only -Wall` on the RTL (clean).
- `make build`: one Verilator build of UVM + DUT + testbench, with line and
  toggle coverage on rtl/ only (`tb/coverage.vlt`). About 4-7 minutes;
  ccache makes rebuilds faster.
- `make test TEST=... SEED=...`: one run; log and coverage file in logs/.
- `make regress N=...`: `scripts/regress.py` runs N seeds round-robin over the
  tests, at most 4 at a time; a run passes only with "TEST PASSED", zero
  UVM_ERROR/UVM_FATAL and no Verilator `%Error` (which is how SVA failures
  appear).
- `make cov`: `scripts/coverage_report.py` merges the coverage files, prints
  functional coverage per covergroup and rtl/ line and toggle coverage (raw and
  after the waivers in `scripts/cov_waivers.txt`), and writes annotated sources.
- `make mutate`: `scripts/mutate.py` rebuilds with each `+define+MUT_*` RTL
  bug and runs the same fixed regression; a mutant is caught if any run fails.
