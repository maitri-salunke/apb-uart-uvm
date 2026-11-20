# Verification plan: apb_uart

Each item says what must be true, how it is checked, and which coverage proves
it was exercised. "SB" = the reference-model scoreboard
(`tb/env/uart_env_pkg.sv`, `uart_scoreboard`), "SVA A.." = an assertion in
`tb/sva/`, "cg_x.y" = a coverpoint or cross in `uart_coverage`. An item is
closed when its checks never fire across the regression and its coverage
bins are all hit. Final status is in the README results table.

| ID | Feature | Requirement | Checker | Coverage | Tests |
|---|---|---|---|---|---|
| VP-01 | Register access | Every mapped register can be read and written through APB with the documented reset values and access policy | RAL `uvm_reg_hw_reset_seq`, `uvm_reg_bit_bash_seq`, RAL `mirror(UVM_CHECK)`, SB register compare | `cg_apb.x_reg_dir` | reg, apb_rand |
| VP-02 | Error response | Unmapped addresses and writes to STATUS return PSLVERR, have no side effects, read data 0; mapped accesses never error | SB `APB_ERR`, `APB_ERRDATA`; SVA A13 | `cg_apb.x_reg_err`, `C04_error_resp` | reg, apb_rand |
| VP-03 | APB transfer types | Zero-idle back-to-back transfers and transfers after idle gaps both work; PADDR[1:0] is ignored | SB on every transfer | `cg_apb.cp_b2b`, `C01`..`C05` covers | all |
| VP-04 | APB master protocol | SETUP is followed by ACCESS; PADDR/PWRITE/PWDATA stable through the transfer; PENABLE only with PSEL and drops after completion; no X on PSEL or on control/data while selected | SVA A01-A10 | `C02_wait_state`, `C03_back2back` | all |
| VP-05 | APB slave protocol | PREADY arrives within 16 cycles; PREADY/PRDATA never X when sampled; PSLVERR only in the completing cycle | SVA A11-A14 | `C02_wait_state`, `C04_error_resp` | all |
| VP-06 | Baud generator | Bit period is exactly 16*(DIV+1) PCLK cycles over the divisor range used (0 .. 2100) | TX monitor samples each bit at 1/4, 1/2, 3/4 (`TX_TIMING`); RX path decodes driver frames | `cg_frame_cfg.cp_div`, `x_dir_div` | tx, rx, slow_baud, rand |
| VP-07 | TX framing | Start bit, 8 data bits LSB first, optional parity, one full-length stop bit | SB `TX_DATA`, `TX_STOP`, `TX_PARITY`, `TX_TIMING`; monitor `TXSTOP`; SVA A18 | `cg_data.x_dir_data`, `cg_frame_cfg.x_dir_mode` | tx, duplex, irq, fifo |
| VP-08 | TX ordering | Bytes leave in write order; every started frame completes | SB `TX_DATA`, `TX_START`, `TX_PENDING` (check_phase) | `cg_fifo.x_dir_level` (tx) | tx, fifo |
| VP-09 | RX framing | Driver frames (8N1/8E1/8O1) are received and returned in order through DATA | SB `RX_DATA` | `cg_data.x_dir_data` (rx), `cg_frame_cfg.x_dir_mode` | rx, duplex, irq |
| VP-10 | RX framing error | Stop bit low sets INT_STAT.FRAME_ERR and the byte is discarded | SB `RD_INTST`, `RX_DATA`, `ST_RXLVL` | `cg_rx_stim.x_kind_par` (FR_FRAME_ERR) | rx, irq, rand |
| VP-11 | RX parity error | Parity mismatch (with good stop bit) sets PARITY_ERR and the byte is discarded; 8N1 never flags parity | SB `RD_INTST`, `RX_DATA` | `cg_rx_stim.x_kind_par` (FR_PARITY_ERR x parity on) | rx, irq |
| VP-12 | Break | A line held low for a whole frame plus a bit sets FRAME_ERR once and the receiver re-arms only after the line returns high | SB (single frame error, following frame received) | `cg_rx_stim.cp_kind` (FR_BREAK) | rx, irq |
| VP-13 | Glitch rejection | A low pulse of 1/4 bit is rejected at the mid-bit check; no byte, no error | SB (no RX entry, no error bit) | `cg_rx_stim.cp_kind` (FR_GLITCH) | rx, irq |
| VP-14 | Baud tolerance / CDC | Frames from a transmitter whose clock is off by up to +/-2.5 % are received correctly through the 2-flop synchronizer and majority vote, also back-to-back | SB `RX_DATA` | `cg_rx_stim.x_skew_idle` | rx, duplex, rand |
| VP-15 | RX FIFO | 16 entries; levels and flags in STATUS track the model | SB `ST_RXLVL`, `ST_RXFULL`, `ST_RXEMPTY`; SVA A16, A20 | `cg_fifo.x_dir_level` (rx) | rx, fifo |
| VP-16 | RX overflow | A good frame arriving at a full RX FIFO is dropped and sets RX_OVF; FIFO contents are untouched | SB `RD_INTST`, `RX_DATA` (order after overflow) | `cg_fifo.x_dir_ovf` (rx) | fifo, irq |
| VP-17 | TX FIFO and overflow | 16 entries; a DATA write to a full TX FIFO is dropped and sets TX_OVF | SB `ST_TXLVL`, `RD_INTST`; SVA A15, A19 | `cg_fifo.x_dir_level`, `x_dir_ovf` (tx) | fifo, tx, irq |
| VP-18 | FIFO flush | CTRL.TX_CLR / RX_CLR empty the FIFO (empty or not) and read back as 0 | SB level checks after flush, `RD_CTRL` | `cg_flush.x` | fifo |
| VP-19 | TX enable | With TX_EN = 0 bytes stay queued (TX_LEVEL holds); setting it drains them | SB `ST_TXLVL`, `TX_DATA` | `cg_txen.x` | fifo |
| VP-20 | Loopback | With LOOPBACK = 1 transmitted bytes are received internally, the txd pin idles high, the rxd pin is ignored | SB (loopback RX path), test byte count, SVA A21 | `cg_frame_cfg.x_lb_mode` | loopback, rand |
| VP-21 | Sticky W1C | RX_OVF / FRAME_ERR / PARITY_ERR / TX_OVF clear only on write-1; write-0 keeps them | SB `RD_INTST` | `cg_w1c.x` | irq, tx, rx |
| VP-22 | Interrupt output | irq = OR(INT_STAT & INT_EN) at all times, for every source | SVA A17 (every cycle), SB `IRQ` at INT_STAT reads | `cg_int.*` | irq |
| VP-23 | RX threshold | INT_STAT.RX_THR = (RX_LEVEL >= RX_THR) for thresholds 0, 1, 2..15, 16 | SB `RD_INTST` bit 0 | `cg_thr.x` | irq |
| VP-24 | TX empty status | INT_STAT.TX_EMPTY / STATUS.TX_EMPTY / TX_BUSY track the FIFO and shifter | SB `ST_TXEMPTY`, `ST_TXBUSY`, `RD_INTST` bit 1 | `cg_int.cp_tx_emp` | tx, fifo |
| VP-25 | Full duplex | Simultaneous TX and RX traffic with concurrent register polling | SB (all of the above) | `cg_frame_cfg.cp_dir` both | duplex, rand |
| VP-26 | Configuration | Parity mode, divisor and loopback reconfigured between traffic bursts take effect for the next frame | SB, monitors follow `uart_cfg` | `cg_frame_cfg.x_lb_mode`, `x_dir_div` | rand |
| VP-27 | Reserved bits | Reserved STATUS / register bits read 0 | SB `ST_RSVD`, register compares | toggle coverage of `prdata` | all |
| VP-28 | Code coverage | Line (block/branch) and toggle coverage of rtl/ closed or waived with reasons | `make cov` | `scripts/cov_waivers.txt` | regression |

## Out of scope / not verified
- Asynchronous reset asserted in the middle of traffic (reset is applied once at time 0).
- Divisors above 2100 (one 8N1 frame at DIV = 65535 is 10.5 M cycles); the
  upper divisor counter bits are waived in code coverage.
- Gate-level / timing: only RTL is simulated. The rxd synchronizer is checked
  functionally (delay and sampling), not for metastability, which RTL
  simulation cannot model.
