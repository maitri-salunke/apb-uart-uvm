// uart_env_pkg.sv - reference model / scoreboard, functional coverage,
// virtual sequencer and environment
package uart_env_pkg;
  import uvm_pkg::*;
  import apb_pkg::*;
  import uart_pkg::*;
  import uart_ral_pkg::*;
  `include "uvm_macros.svh"

  localparam int DEPTH = 16;
  localparam bit [11:0] A_DATA = 12'h000, A_STATUS = 12'h004, A_CTRL = 12'h008,
                        A_BAUD = 12'h00C, A_INT_EN = 12'h010, A_INT_ST = 12'h014,
                        A_RXTHR = 12'h018;

  typedef enum {R_DATA, R_STATUS, R_CTRL, R_BAUD, R_INT_EN, R_INT_ST, R_RXTHR, R_UNMAPPED} reg_e;

  function automatic reg_e decode(bit [11:0] a);
    if (a[11:5] != 0) return R_UNMAPPED;
    case (a[4:2])
      3'd0: return R_DATA;   3'd1: return R_STATUS; 3'd2: return R_CTRL;
      3'd3: return R_BAUD;   3'd4: return R_INT_EN; 3'd5: return R_INT_ST;
      3'd6: return R_RXTHR;  default: return R_UNMAPPED;
    endcase
  endfunction

  // ===================================================================
  // Functional coverage (each covergroup maps to items in docs/VPLAN.md)
  // ===================================================================
  class uart_coverage extends uvm_component;
    `uvm_component_utils(uart_coverage)

    // VP-01..03: register accesses, direction and response
    covergroup cg_apb with function sample(reg_e r, bit wr, bit err, bit b2b);
      option.per_instance = 1;
      cp_reg:  coverpoint r;
      cp_dir:  coverpoint wr { bins rd = {0}; bins wr = {1}; }
      cp_err:  coverpoint err { bins ok = {0}; bins slverr = {1}; }
      cp_b2b:  coverpoint b2b { bins idle_before = {0}; bins back2back = {1}; }
      x_reg_dir: cross cp_reg, cp_dir;
      x_reg_err: cross cp_reg, cp_err {
        // only unmapped addresses and STATUS writes may error
        ignore_bins ok_only = binsof(cp_reg) intersect {R_DATA, R_CTRL, R_BAUD, R_INT_EN, R_INT_ST, R_RXTHR} &&
                              binsof(cp_err) intersect {1};
        ignore_bins unm_ok  = binsof(cp_reg) intersect {R_UNMAPPED} && binsof(cp_err) intersect {0};
      }
    endgroup

    // VP-04..06: line configuration under which frames were carried
    covergroup cg_frame_cfg with function sample(bit is_tx, int unsigned div, bit par_en, bit par_odd, bit lb);
      option.per_instance = 1;
      cp_dir:  coverpoint is_tx { bins rx = {0}; bins tx = {1}; }
      cp_div:  coverpoint div { bins min = {0}; bins fast = {[1:7]}; bins mid = {[8:31]}; bins slow = {[32:65535]}; }
      cp_mode: coverpoint {par_en, par_odd} { bins n81 = {2'b00, 2'b01}; bins e81 = {2'b10}; bins o81 = {2'b11}; }
      cp_lb:   coverpoint lb { bins pin = {0}; bins loopback = {1}; }
      x_dir_mode: cross cp_dir, cp_mode;
      x_dir_div:  cross cp_dir, cp_div;
      x_lb_mode:  cross cp_lb, cp_mode;
    endgroup

    // VP-07/08: data patterns in both directions
    covergroup cg_data with function sample(bit is_tx, bit [7:0] d);
      option.per_instance = 1;
      cp_dir:  coverpoint is_tx { bins rx = {0}; bins tx = {1}; }
      cp_data: coverpoint d { bins zero = {8'h00}; bins ones = {8'hFF}; bins alt55 = {8'h55};
                              bins altaa = {8'hAA}; bins low = {[8'h01:8'h54]}; bins high = {[8'h56:8'hFE]}; }
      x_dir_data: cross cp_dir, cp_data;
    endgroup

    // VP-09..12: receive stimulus: error kinds, baud skew, back-to-back
    covergroup cg_rx_stim with function sample(frame_kind_e k, int skew, int unsigned idle, bit par_en);
      option.per_instance = 1;
      cp_kind: coverpoint k;
      cp_skew: coverpoint skew { bins slow = {[-25:-10]}; bins slightly_slow = {[-9:-1]}; bins exact = {0};
                                 bins slightly_fast = {[1:9]}; bins fast = {[10:25]}; }
      cp_idle: coverpoint idle { bins back2back = {0}; bins gap = {[1:$]}; }
      cp_par:  coverpoint par_en;
      x_kind_par: cross cp_kind, cp_par {
        ignore_bins no_par_err = binsof(cp_kind) intersect {FR_PARITY_ERR} && binsof(cp_par) intersect {0};
      }
      x_skew_idle: cross cp_skew, cp_idle;
    endgroup

    // VP-13..16: FIFO occupancy at push, overflow, flush
    covergroup cg_fifo with function sample(bit is_tx, int unsigned level_before, bit ovf);
      option.per_instance = 1;
      cp_dir:   coverpoint is_tx { bins rx = {0}; bins tx = {1}; }
      cp_level: coverpoint level_before { bins empty = {0}; bins partial = {[1:14]}; bins almost = {15}; bins full = {16}; }
      cp_ovf:   coverpoint ovf { bins no = {0}; bins overflow = {1}; }
      x_dir_level: cross cp_dir, cp_level;
      x_dir_ovf:   cross cp_dir, cp_ovf;
    endgroup

    covergroup cg_flush with function sample(bit is_tx, int unsigned level);
      option.per_instance = 1;
      cp_dir:   coverpoint is_tx { bins rx = {0}; bins tx = {1}; }
      cp_level: coverpoint level { bins empty = {0}; bins nonempty = {[1:16]}; }
      x: cross cp_dir, cp_level;
    endgroup

    // VP-17..19: interrupt status/enable combinations and irq pin
    covergroup cg_int with function sample(bit [5:0] stat, bit [5:0] en, bit irq);
      option.per_instance = 1;
      cp_rx_thr: coverpoint {stat[0], en[0]};
      cp_tx_emp: coverpoint {stat[1], en[1]};
      cp_rx_ovf: coverpoint {stat[2], en[2]};
      cp_frame:  coverpoint {stat[3], en[3]};
      cp_parity: coverpoint {stat[4], en[4]};
      cp_tx_ovf: coverpoint {stat[5], en[5]};
      cp_irq:    coverpoint irq;
    endgroup

    // VP-20: W1C behaviour of each sticky bit
    covergroup cg_w1c with function sample(int unsigned bitno, bit was_set, bit wrote1);
      option.per_instance = 1;
      cp_bit: coverpoint bitno { bins rx_ovf = {2}; bins frame = {3}; bins parity = {4}; bins tx_ovf = {5}; }
      cp_op:  coverpoint {was_set, wrote1} { bins clear = {2'b11}; bins keep = {2'b10}; bins noop = {2'b01}; }
      x: cross cp_bit, cp_op;
    endgroup

    // VP-21: RX threshold values exercised while data arrives
    covergroup cg_thr with function sample(int unsigned thr, bit lvl);
      option.per_instance = 1;
      cp_thr: coverpoint thr { bins zero = {0}; bins one = {1}; bins mid = {[2:15]}; bins full = {16}; }
      cp_lvl: coverpoint lvl;
      x: cross cp_thr, cp_lvl { ignore_bins zero_never_low = binsof(cp_thr.zero) && binsof(cp_lvl) intersect {0}; }
    endgroup

    // VP-22: transmitter disabled with data queued, then re-enabled
    covergroup cg_txen with function sample(bit tx_en, int unsigned tx_level);
      option.per_instance = 1;
      cp_en:  coverpoint tx_en;
      cp_lvl: coverpoint tx_level { bins empty = {0}; bins queued = {[1:16]}; }
      x: cross cp_en, cp_lvl;
    endgroup

    function new(string name, uvm_component parent);
      super.new(name, parent);
      cg_apb = new; cg_frame_cfg = new; cg_data = new; cg_rx_stim = new;
      cg_fifo = new; cg_flush = new; cg_int = new; cg_w1c = new; cg_thr = new; cg_txen = new;
    endfunction

    function real total();
      real s = 0;
      s += cg_apb.get_coverage();   s += cg_frame_cfg.get_coverage();
      s += cg_data.get_coverage();  s += cg_rx_stim.get_coverage();
      s += cg_fifo.get_coverage();  s += cg_flush.get_coverage();
      s += cg_int.get_coverage();   s += cg_w1c.get_coverage();
      s += cg_thr.get_coverage();   s += cg_txen.get_coverage();
      return s / 10.0;
    endfunction

    function void report_phase(uvm_phase phase);
      `uvm_info("FCOV", $sformatf({"cg_apb=%0.1f cg_frame_cfg=%0.1f cg_data=%0.1f cg_rx_stim=%0.1f ",
                 "cg_fifo=%0.1f cg_flush=%0.1f cg_int=%0.1f cg_w1c=%0.1f cg_thr=%0.1f cg_txen=%0.1f"},
                 cg_apb.get_coverage(), cg_frame_cfg.get_coverage(), cg_data.get_coverage(),
                 cg_rx_stim.get_coverage(), cg_fifo.get_coverage(), cg_flush.get_coverage(),
                 cg_int.get_coverage(), cg_w1c.get_coverage(), cg_thr.get_coverage(),
                 cg_txen.get_coverage()), UVM_LOW)
      `uvm_info("FCOV", $sformatf("FUNCTIONAL_COVERAGE_THIS_RUN=%0.2f", total()), UVM_LOW)
    endfunction
  endclass

  // ===================================================================
  // Reference model + scoreboard
  // ===================================================================
  `uvm_analysis_imp_decl(_tx_start)
  `uvm_analysis_imp_decl(_tx_frame)
  `uvm_analysis_imp_decl(_rx_frame)
  `uvm_analysis_imp_decl(_rx_stim)

  typedef struct { bit [7:0] data; longint unsigned t; } rx_entry_t;

  class uart_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(uart_scoreboard)

    uvm_tlm_analysis_fifo #(apb_item)              apb_fifo;
    uvm_analysis_imp_tx_start #(uart_item, uart_scoreboard) tx_start_imp;
    uvm_analysis_imp_tx_frame #(uart_item, uart_scoreboard) tx_frame_imp;
    uvm_analysis_imp_rx_frame #(uart_item, uart_scoreboard) rx_frame_imp;
    uvm_analysis_imp_rx_stim  #(uart_item, uart_scoreboard) rx_stim_imp;

    apb_vif_t     vif;
    uart_cfg      cfg;
    uart_coverage cov;

    // ---- model state
    bit          tx_en = 1, rx_en = 1, par_en = 0, par_odd = 0, loopback = 0;
    bit [15:0]   div = 16'd26;
    bit [5:0]    int_en = 0;
    int unsigned rx_thr = 1;
    bit          st_rx_ovf, st_frame, st_parity, st_tx_ovf;
    bit [7:0]    txq[$];          // bytes waiting in the TX FIFO
    bit [7:0]    tx_expect[$];    // frames started, awaiting completion on txd
    rx_entry_t   rxq[$];          // bytes in the RX FIFO
    longint unsigned t_last_start;      // tx start edge time
    longint unsigned t_last_rx_event;   // any rx-side model event (push/ovf/err)
    longint unsigned t_frame_end;       // nominal end of the current tx frame
    bit              t_frame_valid;
    bit              dut_has_rx;        // last STATUS read said RX not empty

    // ---- statistics
    int unsigned n_checks, n_errors, n_skipped;
    int unsigned n_tx_frames, n_rx_frames, n_rx_reads;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      apb_fifo     = new("apb_fifo", this);
      tx_start_imp = new("tx_start_imp", this);
      tx_frame_imp = new("tx_frame_imp", this);
      rx_frame_imp = new("rx_frame_imp", this);
      rx_stim_imp  = new("rx_stim_imp", this);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(apb_vif_t)::get(this, "", "apb_vif", vif)) `uvm_fatal("NOVIF", "scoreboard")
      if (!uvm_config_db#(uart_cfg)::get(this, "", "cfg", cfg))  `uvm_fatal("NOCFG", "scoreboard")
    endfunction

    function longint unsigned now(); return longint'($time / 10); endfunction
    function int unsigned bitc();  return 16 * (int'(div) + 1); endfunction
    // DUT acts on an RX frame up to T+6 cycles after the monitor's decision
    function bit rx_unsettled(); return (now() - t_last_rx_event) < longint'(2 * (int'(div) + 1) + 12); endfunction
    function bit tx_unsettled(); return (now() - t_last_start) < 4; endfunction

    function void check(bit ok, string id, string msg);
      n_checks++;
      if (!ok) begin
        n_errors++;
        `uvm_error(id, msg)
      end
    endfunction

    // ---------------- serial-side events (processed immediately)
    function void write_tx_start(uart_item t);
      t_last_start = now();
      if (txq.size() == 0) begin
        check(0, "TX_START", "transmitter started a frame with the model TX FIFO empty");
        return;
      end
      tx_expect.push_back(txq.pop_front());
      t_frame_end   = now() + longint'(bitc() * (par_en ? 11 : 10));
      t_frame_valid = 1;
    endfunction

    function void write_tx_frame(uart_item t);
      bit [7:0] exp;
      `uvm_info("SB_TX", $sformatf("txd frame %s", t.convert2string()), UVM_HIGH)
      n_tx_frames++;
      if (t.glitch) begin
        check(0, "TX_GLITCH", "glitch on txd (start bit high at mid-bit)");
        return;
      end
      if (tx_expect.size() == 0) begin
        check(0, "TX_UNEXP", $sformatf("unexpected TX frame %s", t.convert2string()));
        return;
      end
      exp = tx_expect.pop_front();
      check(t.data == exp, "TX_DATA", $sformatf("TX data 0x%02h, expected 0x%02h", t.data, exp));
      check(!t.frame_err, "TX_STOP", "TX stop bit low");
      check(!t.parity_err, "TX_PARITY", $sformatf("TX parity bit wrong for %s", t.par_en ? (t.par_odd ? "odd" : "even") : "none"));
      check(!t.timing_err, "TX_TIMING", "TX bit not stable over its centre half (baud timing)");
      cov.cg_frame_cfg.sample(1, t.div, t.par_en, t.par_odd, loopback);
      cov.cg_data.sample(1, t.data);
      // loopback: the same frame goes into the receiver
      if (loopback && rx_en) rx_arrival(t);
    endfunction

    function void write_rx_frame(uart_item t);
      `uvm_info("SB_RX", $sformatf("rxd frame %s (loopback=%0b rx_en=%0b)", t.convert2string(), loopback, rx_en), UVM_HIGH)
      if (loopback || !rx_en) return;      // DUT ignores the pin
      n_rx_frames++;
      if (t.glitch) return;                // rejected start: no effect
      cov.cg_frame_cfg.sample(0, t.div, t.par_en, t.par_odd, 0);
      rx_arrival(t);
    endfunction

    function void write_rx_stim(uart_item t);
      `uvm_info("SB_STIM", $sformatf("driving %s skew=%0d idle=%0d", t.convert2string(), t.skew_ppt, t.idle_bits), UVM_HIGH)
      cov.cg_rx_stim.sample(t.kind, t.skew_ppt, t.idle_bits, t.par_en);
    endfunction

    function void rx_arrival(uart_item t);
      t_last_rx_event = now();
      if (t.frame_err) begin st_frame = 1; return; end
      if (t.parity_err) begin st_parity = 1; return; end
      cov.cg_data.sample(0, t.data);
      cov.cg_fifo.sample(0, rxq.size(), rxq.size() == DEPTH);
      if (rxq.size() == DEPTH) begin
        st_rx_ovf = 1;
        return;
      end
      rxq.push_back('{data: t.data, t: now()});
      cov.cg_thr.sample(rx_thr, rxq.size() >= rx_thr);
    endfunction

    // ---------------- bus side (processed one cycle late, see run_phase)
    task run_phase(uvm_phase phase);
      apb_item t;
      forever begin
        apb_fifo.get(t);
        @(negedge vif.pclk); #1;
        process_apb(t);
      end
    endtask

    function bit [5:0] model_int_stat();
      return {st_tx_ovf, st_parity, st_frame, st_rx_ovf, txq.size() == 0, rxq.size() >= rx_thr};
    endfunction

    function void process_apb(apb_item t);
      reg_e r = decode(t.addr);
      bit   exp_err = (r == R_UNMAPPED) || (t.write && r == R_STATUS);
      cov.cg_apb.sample(r, t.write, t.slverr, t.b2b);
      check(t.slverr == exp_err, "APB_ERR",
            $sformatf("%s: PSLVERR=%0b expected %0b", t.convert2string(), t.slverr, exp_err));
      if (exp_err) begin
        if (!t.write) check(t.data == 0, "APB_ERRDATA", $sformatf("errored read returned 0x%08h", t.data));
        return;
      end
      if (t.write) do_write(r, t.data);
      else         do_read(r, t.data, t.irq);
    endfunction

    function void do_write(reg_e r, bit [31:0] d);
      case (r)
        R_DATA: begin
          cov.cg_fifo.sample(1, txq.size(), txq.size() == DEPTH);
          if (txq.size() == DEPTH) st_tx_ovf = 1;
          else txq.push_back(d[7:0]);
        end
        R_CTRL: begin
          {loopback, par_odd, par_en, rx_en, tx_en} = d[4:0];
          cfg.par_en = par_en; cfg.par_odd = par_odd; cfg.loopback = loopback;
          if (d[8]) begin cov.cg_flush.sample(1, txq.size()); txq.delete(); end
          if (d[9]) begin cov.cg_flush.sample(0, rxq.size()); rxq.delete(); end
        end
        R_BAUD:   begin div = d[15:0]; cfg.div = div; end
        R_INT_EN: int_en = d[5:0];
        R_INT_ST: begin
          cov.cg_w1c.sample(2, st_rx_ovf, d[2]);
          cov.cg_w1c.sample(3, st_frame,  d[3]);
          cov.cg_w1c.sample(4, st_parity, d[4]);
          cov.cg_w1c.sample(5, st_tx_ovf, d[5]);
          if (d[2]) st_rx_ovf = 0;
          if (d[3]) st_frame  = 0;
          if (d[4]) st_parity = 0;
          if (d[5]) st_tx_ovf = 0;
        end
        R_RXTHR: rx_thr = d[4:0];
        default: ;
      endcase
    endfunction

    function void do_read(reg_e r, bit [31:0] d, bit irq);
      case (r)
        R_DATA: begin
          n_rx_reads++;
          if (rxq.size() == 0) begin
            check(d == 0, "RX_DATA", $sformatf("DATA read 0x%02h with model RX FIFO empty", d));
          end else if (!dut_has_rx && (now() - rxq[0].t) < longint'(2 * (int'(div) + 1) + 12) &&
                       d == 0 && rxq[0].data != 0) begin
            n_skipped++;     // byte still in the DUT synchronizer/sampling window
          end else begin
            check(d == {24'h0, rxq[0].data}, "RX_DATA",
                  $sformatf("DATA read 0x%08h, expected 0x%02h", d, rxq[0].data));
            void'(rxq.pop_front());
          end
          dut_has_rx = 0;
        end
        R_STATUS: begin
          bit tx_busy_exp = t_frame_valid && (now() < t_frame_end);
          dut_has_rx = !d[3];
          cov.cg_txen.sample(tx_en, txq.size());
          if (!tx_unsettled()) begin
            check(d[0] == (txq.size() == DEPTH), "ST_TXFULL",  $sformatf("STATUS.TX_FULL=%0b model level %0d", d[0], txq.size()));
            check(d[1] == (txq.size() == 0),     "ST_TXEMPTY", $sformatf("STATUS.TX_EMPTY=%0b model level %0d", d[1], txq.size()));
            check(d[12:8] == txq.size(),         "ST_TXLVL",   $sformatf("STATUS.TX_LEVEL=%0d model %0d", d[12:8], txq.size()));
          end else n_skipped++;
          if (!rx_unsettled()) begin
            check(d[2] == (rxq.size() == DEPTH), "ST_RXFULL",  $sformatf("STATUS.RX_FULL=%0b model level %0d", d[2], rxq.size()));
            check(d[3] == (rxq.size() == 0),     "ST_RXEMPTY", $sformatf("STATUS.RX_EMPTY=%0b model level %0d", d[3], rxq.size()));
            check(d[20:16] == rxq.size(),        "ST_RXLVL",   $sformatf("STATUS.RX_LEVEL=%0d model %0d", d[20:16], rxq.size()));
          end else n_skipped++;
          // TX_BUSY: skip within a few cycles of either frame edge
          if (tx_unsettled() || (t_frame_valid && (now() + 4 > t_frame_end) && (now() < t_frame_end + 4)))
            n_skipped++;
          else
            check(d[4] == tx_busy_exp, "ST_TXBUSY", $sformatf("STATUS.TX_BUSY=%0b expected %0b", d[4], tx_busy_exp));
          check(d[31:21] == 0 && d[15:13] == 0 && d[7:5] == 0, "ST_RSVD", $sformatf("STATUS reserved bits set: 0x%08h", d));
        end
        R_CTRL:   check(d == {27'h0, loopback, par_odd, par_en, rx_en, tx_en}, "RD_CTRL",
                        $sformatf("CTRL read 0x%08h", d));
        R_BAUD:   check(d == {16'h0, div}, "RD_BAUD", $sformatf("BAUD read 0x%08h expected 0x%04h", d, div));
        R_INT_EN: check(d == {26'h0, int_en}, "RD_INTEN", $sformatf("INT_EN read 0x%08h expected 0x%02h", d, int_en));
        R_RXTHR:  check(d == rx_thr, "RD_RXTHR", $sformatf("RX_THR read 0x%08h expected %0d", d, rx_thr));
        R_INT_ST: begin
          bit [5:0] m = model_int_stat();
          bit [5:0] mask = 6'b111111;
          if (tx_unsettled()) mask[1] = 0;
          if (rx_unsettled()) mask[4:2] = 0;
          if (rx_unsettled()) mask[0] = 0;
          if (mask != 6'b111111) n_skipped++;
          check(((d[5:0] ^ m) & mask) == 0 && d[31:6] == 0, "RD_INTST",
                $sformatf("INT_STAT read 0x%02h, model 0x%02h (mask 0x%02h)", d[5:0], m, mask));
          check(irq == |(d[5:0] & int_en), "IRQ",
                $sformatf("irq=%0b but INT_STAT=0x%02h INT_EN=0x%02h", irq, d[5:0], int_en));
          cov.cg_int.sample(d[5:0], int_en, irq);
          cov.cg_thr.sample(rx_thr, d[0]);
        end
        default: ;
      endcase
    endfunction

    function void check_phase(uvm_phase phase);
      check(tx_expect.size() == 0, "TX_PENDING",
            $sformatf("%0d started TX frames never completed", tx_expect.size()));
    endfunction

    function void report_phase(uvm_phase phase);
      `uvm_info("SB", $sformatf("checks=%0d errors=%0d skipped_unsettled=%0d tx_frames=%0d rx_frames=%0d rx_reads=%0d",
                n_checks, n_errors, n_skipped, n_tx_frames, n_rx_frames, n_rx_reads), UVM_LOW)
    endfunction
  endclass

  // ===================================================================
  // Virtual sequencer and environment
  // ===================================================================
  class uart_vsequencer extends uvm_sequencer;
    `uvm_component_utils(uart_vsequencer)
    apb_sequencer  apb_sqr;
    uart_sequencer uart_sqr;
    uart_reg_block regmodel;
    uart_cfg       cfg;
    uart_scoreboard sb;
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
  endclass

  class uart_env extends uvm_env;
    `uvm_component_utils(uart_env)
    apb_agent        apb;
    uart_agent       uart;
    uart_scoreboard  sb;
    uart_coverage    cov;
    uart_vsequencer  vsqr;
    uart_reg_block   regmodel;
    apb_reg_adapter  adapter;
    uvm_reg_predictor #(apb_item) predictor;
    uart_cfg         cfg;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(uart_cfg)::get(this, "", "cfg", cfg)) `uvm_fatal("NOCFG", "env")
      apb       = apb_agent::type_id::create("apb", this);
      uart      = uart_agent::type_id::create("uart", this);
      sb        = uart_scoreboard::type_id::create("sb", this);
      cov       = uart_coverage::type_id::create("cov", this);
      vsqr      = uart_vsequencer::type_id::create("vsqr", this);
      predictor = uvm_reg_predictor#(apb_item)::type_id::create("predictor", this);
      regmodel  = uart_reg_block::type_id::create("regmodel");
      regmodel.build();
      adapter   = apb_reg_adapter::type_id::create("adapter");
    endfunction

    function void connect_phase(uvm_phase phase);
      sb.cov = cov;
      apb.mon.ap.connect(sb.apb_fifo.analysis_export);
      uart.tx_mon.start_ap.connect(sb.tx_start_imp);
      uart.tx_mon.ap.connect(sb.tx_frame_imp);
      uart.rx_mon.ap.connect(sb.rx_frame_imp);
      uart.drv.drv_ap.connect(sb.rx_stim_imp);
      // RAL: front door through the APB sequencer, explicit prediction from the monitor
      regmodel.apb_map.set_sequencer(apb.sqr, adapter);
      regmodel.apb_map.set_auto_predict(0);
      predictor.map     = regmodel.apb_map;
      predictor.adapter = adapter;
      apb.mon.ap.connect(predictor.bus_in);
      vsqr.apb_sqr  = apb.sqr;
      vsqr.uart_sqr = uart.sqr;
      vsqr.regmodel = regmodel;
      vsqr.cfg      = cfg;
      vsqr.sb       = sb;
    endfunction
  endclass
endpackage
