// uart_seq_pkg.sv - virtual sequences (run on uart_vsequencer)
package uart_seq_pkg;
  import uvm_pkg::*;
  import apb_pkg::*;
  import uart_pkg::*;
  import uart_ral_pkg::*;
  import uart_env_pkg::*;
  `include "uvm_macros.svh"

  // ------------------------------------------------------------ base
  class uart_base_vseq extends uvm_sequence;
    `uvm_object_utils(uart_base_vseq)
    `uvm_declare_p_sequencer(uart_vsequencer)
    uart_reg_block rm;

    rand int unsigned div;
    rand bit          par_en, par_odd;
    // mostly fast baud rates (simulation time); sometimes the real 115200 setting
    constraint c_div { div dist {0 :/ 1, [1:3] :/ 5, [4:12] :/ 3, [13:40] :/ 1}; }

    function new(string name = "uart_base_vseq"); super.new(name); endfunction

    task pre_body();
      rm = p_sequencer.regmodel;
    endtask

    task wr(uvm_reg r, bit [31:0] v);
      uvm_status_e st;
      r.write(st, v, .parent(this));
      if (st != UVM_IS_OK) `uvm_error("VSEQ", $sformatf("write %s failed", r.get_name()))
    endtask

    task rd(uvm_reg r, output bit [31:0] v);
      uvm_status_e   st;
      uvm_reg_data_t d;
      r.read(st, d, .parent(this));
      v = d[31:0];
      if (st != UVM_IS_OK) `uvm_error("VSEQ", $sformatf("read %s failed", r.get_name()))
    endtask

    task raw(bit write, bit [11:0] addr, bit [31:0] data = 0);
      apb_rw_seq s = apb_rw_seq::type_id::create("raw");
      s.write = write; s.addr = addr; s.data = data;
      s.start(p_sequencer.apb_sqr, this);
    endtask

    task configure(int unsigned d, bit pe, bit po, bit lb = 0, bit txe = 1, bit rxe = 1);
      wr(rm.BAUD, d);
      wr(rm.CTRL, {27'h0, lb, po, pe, rxe, txe});
      idle_clks(2);   // scoreboard -> uart_cfg update lands one cycle after the write
    endtask

    task configure_random();
      configure(div, par_en, par_odd);
    endtask

    // poll until the transmitter has nothing left to send
    task wait_tx_idle(int unsigned max_polls = 100000, int unsigned gap = 0);
      bit [31:0] s;
      repeat (max_polls) begin
        rd(rm.STATUS, s);
        if (s[1] && !s[4]) return;
        if (gap) idle_clks(gap);
      end
      `uvm_error("VSEQ", "timeout waiting for TX idle")
    endtask

    // read every byte the DUT reports as available (firmware style)
    task drain_rx(output int unsigned n);
      bit [31:0] s, d;
      n = 0;
      rd(rm.STATUS, s);
      while (s[20:16] != 0) begin
        repeat (s[20:16]) begin rd(rm.DATA, d); n++; end
        rd(rm.STATUS, s);
      end
    endtask

    task idle_clks(int unsigned n);
      repeat (n) @(negedge p_sequencer.sb.vif.pclk);
    endtask

    // frame time in clocks for the current configuration
    function int unsigned frame_clks();
      return 16 * (p_sequencer.cfg.div + 1) * (p_sequencer.cfg.par_en ? 11 : 10);
    endfunction

    task send_frames(int unsigned n, bit only_good = 0, bit no_skew = 0);
      uart_frame_seq fs = uart_frame_seq::type_id::create("fs");
      if (!fs.randomize() with { n == local::n; }) `uvm_fatal("RAND", "frames")
      fs.only_good = only_good;
      fs.no_skew   = no_skew;
      fs.start(p_sequencer.uart_sqr, this);
      idle_clks(16 * (p_sequencer.cfg.div + 1) + 40);   // let the last frame settle
    endtask

    task clear_int();
      wr(rm.INT_STAT, 32'h3C);
    endtask
  endclass

  // ------------------------------------------------------------ register tests
  class reg_vseq extends uart_base_vseq;
    `uvm_object_utils(reg_vseq)
    function new(string name = "reg_vseq"); super.new(name); endfunction
    task body();
      uvm_reg_hw_reset_seq rst;
      uvm_reg_bit_bash_seq bb;
      apb_random_seq       rnd;
      bit [31:0]           v;
      // reset values of all registers (STATUS/INT_STAT checked by the scoreboard)
      rd(rm.STATUS, v);
      rd(rm.INT_STAT, v);
      rst = uvm_reg_hw_reset_seq::type_id::create("rst");
      rst.model = rm;
      rst.start(null, this);
      bb = uvm_reg_bit_bash_seq::type_id::create("bb");
      bb.model = rm;
      bb.start(null, this);
      // writes to RO STATUS, reads/writes to unmapped space
      raw(1, 12'h004, 32'hFFFF_FFFF);
      raw(1, 12'h01C, 32'h1234_5678);
      raw(0, 12'h01C);
      raw(0, 12'hFFC);
      raw(1, 12'h800, 32'h1);
      rnd = apb_random_seq::type_id::create("rnd");
      if (!rnd.randomize()) `uvm_fatal("RAND", "rnd")
      rnd.start(p_sequencer.apb_sqr, this);
      // RAL mirror check of the non-volatile registers
      begin
        uvm_status_e st;
        rm.CTRL.mirror(st, UVM_CHECK, .parent(this));
        rm.BAUD.mirror(st, UVM_CHECK, .parent(this));
        rm.INT_EN.mirror(st, UVM_CHECK, .parent(this));
        rm.RX_THR.mirror(st, UVM_CHECK, .parent(this));
      end
      configure(1, 0, 0);
    endtask
  endclass

  // ------------------------------------------------------------ transmit
  class tx_vseq extends uart_base_vseq;
    `uvm_object_utils(tx_vseq)
    rand int unsigned nbytes;
    constraint c_n { nbytes dist {[1:8] := 3, [9:16] := 3, [17:24] := 2}; }
    function new(string name = "tx_vseq"); super.new(name); endfunction
    task body();
      bit [31:0] v;
      configure_random();
      repeat (nbytes) begin
        bit [7:0] b;
        void'(std::randomize(b) with { b dist {8'h00 := 1, 8'hFF := 1, 8'h55 := 1, 8'hAA := 1, [1:254] :/ 8}; });
        wr(rm.DATA, b);
      end
      rd(rm.STATUS, v);
      rd(rm.INT_STAT, v);
      wait_tx_idle();
      idle_clks(16 * (div + 1) * 3);
      rd(rm.INT_STAT, v);
      clear_int();
      rd(rm.INT_STAT, v);
    endtask
  endclass

  // ------------------------------------------------------------ receive
  class rx_vseq extends uart_base_vseq;
    `uvm_object_utils(rx_vseq)
    rand int unsigned nframes;
    bit only_good = 0;
    constraint c_n { nframes inside {[4:14]}; }
    function new(string name = "rx_vseq"); super.new(name); endfunction
    task body();
      bit [31:0]   v;
      int unsigned n;
      configure_random();
      send_frames(nframes, only_good);
      rd(rm.INT_STAT, v);
      drain_rx(n);
      rd(rm.INT_STAT, v);
      clear_int();
      rd(rm.INT_STAT, v);
    endtask
  endclass

  // ------------------------------------------------------------ FIFO limits
  class fifo_vseq extends uart_base_vseq;
    `uvm_object_utils(fifo_vseq)
    function new(string name = "fifo_vseq"); super.new(name); endfunction
    task body();
      bit [31:0]   v;
      int unsigned n;
      configure_random();
      // RX overflow: 16 + 1..3 frames without reading
      wr(rm.INT_EN, 32'h04);
      send_frames(DEPTH + 1 + $urandom_range(0, 2), 1, 1);
      rd(rm.STATUS, v);
      rd(rm.INT_STAT, v);
      drain_rx(n);
      clear_int();
      rd(rm.INT_STAT, v);
      // TX with transmitter disabled: fill, overflow, then flush
      configure(div, par_en, par_odd, 0, 0, 1);
      repeat (DEPTH + 2) wr(rm.DATA, $urandom_range(0, 255));
      rd(rm.STATUS, v);
      rd(rm.INT_STAT, v);
      wr(rm.CTRL, {22'h0, 2'b01, 3'h0, 1'b0, par_odd, par_en, 2'b10});   // TX_CLR, tx still off
      rd(rm.STATUS, v);
      // refill a few, enable, drain on the line
      repeat ($urandom_range(1, 6)) wr(rm.DATA, $urandom_range(0, 255));
      rd(rm.STATUS, v);
      configure(div, par_en, par_odd);
      wait_tx_idle();
      idle_clks(frame_clks());
      // RX flush with data present
      send_frames($urandom_range(2, 5), 1, 1);
      rd(rm.STATUS, v);
      wr(rm.CTRL, {22'h0, 2'b10, 3'h0, 1'b0, par_odd, par_en, 2'b11});   // RX_CLR
      rd(rm.STATUS, v);
      // flushes of empty FIFOs
      wr(rm.CTRL, {22'h0, 2'b11, 3'h0, 1'b0, par_odd, par_en, 2'b11});
      rd(rm.STATUS, v);
      clear_int();
      rd(rm.INT_STAT, v);
    endtask
  endclass

  // ------------------------------------------------------------ loopback
  class loopback_vseq extends uart_base_vseq;
    `uvm_object_utils(loopback_vseq)
    rand int unsigned nbytes;
    constraint c_n { nbytes inside {[1:16]}; }
    function new(string name = "loopback_vseq"); super.new(name); endfunction
    task body();
      bit [31:0]   v;
      int unsigned n;
      configure(div, par_en, par_odd, 1);
      repeat (nbytes) wr(rm.DATA, $urandom_range(0, 255));
      wait_tx_idle();
      idle_clks(frame_clks());
      rd(rm.STATUS, v);
      drain_rx(n);
      if (n != nbytes) `uvm_error("LOOPBACK", $sformatf("looped back %0d of %0d bytes", n, nbytes))
      configure(div, par_en, par_odd, 0);
    endtask
  endclass

  // ------------------------------------------------------------ interrupts
  class irq_vseq extends uart_base_vseq;
    `uvm_object_utils(irq_vseq)
    rand bit [5:0]    en;
    rand int unsigned thr;
    constraint c_thr { thr dist {0 :/ 1, 1 :/ 2, [2:15] :/ 4, 16 :/ 2}; }
    function new(string name = "irq_vseq"); super.new(name); endfunction
    task body();
      bit [31:0]   v;
      int unsigned n;
      configure_random();
      wr(rm.INT_EN, en);
      wr(rm.RX_THR, thr);
      rd(rm.INT_STAT, v);
      // mixed good / bad frames, polling INT_STAT while they arrive
      fork
        send_frames($urandom_range(3, 18));
        repeat (6) begin
          idle_clks(frame_clks() * 2);
          rd(rm.INT_STAT, v);
        end
      join
      rd(rm.INT_STAT, v);
      // TX overflow + TX empty interrupt
      repeat ($urandom_range(1, 20)) wr(rm.DATA, $urandom_range(0, 255));
      rd(rm.INT_STAT, v);
      wait_tx_idle();
      idle_clks(frame_clks());
      rd(rm.INT_STAT, v);
      // W1C: write zeros (no clear), then clear one bit at a time
      wr(rm.INT_STAT, 0);
      rd(rm.INT_STAT, v);
      for (int b = 5; b >= 2; b--) begin wr(rm.INT_STAT, 1 << b); rd(rm.INT_STAT, v); end
      drain_rx(n);
      rd(rm.INT_STAT, v);
      wr(rm.INT_EN, 0);
      wr(rm.RX_THR, 1);
    endtask
  endclass

  // ------------------------------------------------------------ full duplex
  class duplex_vseq extends uart_base_vseq;
    `uvm_object_utils(duplex_vseq)
    function new(string name = "duplex_vseq"); super.new(name); endfunction
    task body();
      int unsigned n;
      bit [31:0]   v;
      configure_random();
      fork
        send_frames($urandom_range(5, 15));
        repeat ($urandom_range(5, 15)) begin
          wr(rm.DATA, $urandom_range(0, 255));
          idle_clks($urandom_range(0, frame_clks()));
        end
        repeat (4) begin idle_clks(frame_clks() * 3); drain_rx(n); end
      join
      wait_tx_idle();
      idle_clks(frame_clks());
      drain_rx(n);
      rd(rm.INT_STAT, v);
      clear_int();
    endtask
  endclass

  // ------------------------------------------------------------ slow baud rates
  // One frame each way at a large divisor (bit = 16*(DIV+1) cycles), polling sparsely.
  class slow_baud_vseq extends uart_base_vseq;
    `uvm_object_utils(slow_baud_vseq)
    constraint c_div { div inside {[1024:2100]}; }   // replaces the base distribution
    function new(string name = "slow_baud_vseq"); super.new(name); endfunction
    task body();
      int unsigned n;
      bit [31:0]   v;
      configure_random();
      fork
        wr(rm.DATA, $urandom_range(0, 255));
        send_frames(1, 1, 1);
      join
      wait_tx_idle(1000, frame_clks() / 8);
      idle_clks(frame_clks() / 4);
      drain_rx(n);
      if (n != 1) `uvm_error("SLOW", $sformatf("received %0d frames at DIV=%0d, expected 1", n, div))
      rd(rm.INT_STAT, v);
      configure(1, 0, 0);
    endtask
  endclass

  // ------------------------------------------------------------ random APB traffic
  class apb_rand_vseq extends uart_base_vseq;
    `uvm_object_utils(apb_rand_vseq)
    function new(string name = "apb_rand_vseq"); super.new(name); endfunction
    task body();
      apb_random_seq rnd = apb_random_seq::type_id::create("rnd");
      if (!rnd.randomize()) `uvm_fatal("RAND", "rnd")
      rnd.start(p_sequencer.apb_sqr, this);
      // leave a sane configuration behind (random seq may have changed it)
      configure(div, par_en, par_odd);
      wr(rm.INT_EN, 0);
      wr(rm.RX_THR, 1);
      clear_int();
    endtask
  endclass

  // ------------------------------------------------------------ everything, randomly
  class rand_vseq extends uart_base_vseq;
    `uvm_object_utils(rand_vseq)
    rand int unsigned iters;
    constraint c_it { iters inside {[4:8]}; }
    function new(string name = "rand_vseq"); super.new(name); endfunction
    task body();
      repeat (iters) begin
        uart_base_vseq s;
        case ($urandom_range(0, 6))
          0: s = tx_vseq::type_id::create("tx");
          1: s = rx_vseq::type_id::create("rx");
          2: s = fifo_vseq::type_id::create("fifo");
          3: s = loopback_vseq::type_id::create("lb");
          4: s = irq_vseq::type_id::create("irq");
          5: s = duplex_vseq::type_id::create("dup");
          default: s = apb_rand_vseq::type_id::create("apb");
        endcase
        if (!s.randomize()) `uvm_fatal("RAND", "sub vseq")
        s.start(p_sequencer, this);
      end
    endtask
  endclass
endpackage
