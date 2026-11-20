// uart_pkg.sv - UVM agent for the UART serial side
//   driver  : generates frames on the DUT's rxd line (with error injection)
//   monitor : decodes frames on a line (one instance on rxd, one on txd)
package uart_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  typedef virtual uart_if uart_vif_t;

  typedef enum {FR_GOOD, FR_FRAME_ERR, FR_PARITY_ERR, FR_GLITCH, FR_BREAK} frame_kind_e;

  // ------------------------------------------------------------- config
  // Line configuration shared by the driver, both monitors and the
  // scoreboard. The scoreboard updates it when CTRL / BAUD are written.
  class uart_cfg extends uvm_object;
    `uvm_object_utils(uart_cfg)
    int unsigned div     = 26;
    bit          par_en  = 0;
    bit          par_odd = 0;
    bit          loopback = 0;
    function new(string name = "uart_cfg"); super.new(name); endfunction
    function int unsigned bit_clks(); return 16 * (div + 1); endfunction
    function string mode_str();
      return par_en ? (par_odd ? "8O1" : "8E1") : "8N1";
    endfunction
  endclass

  // --------------------------------------------------------------- item
  class uart_item extends uvm_sequence_item;
    `uvm_object_utils(uart_item)
    rand bit [7:0]    data;
    rand frame_kind_e kind;
    rand int          skew_ppt;     // baud error in parts per thousand
    rand int unsigned idle_bits;    // idle (high) bit times before the frame
    // observed by the monitor
    bit               par_bit;
    bit               frame_err;
    bit               parity_err;
    bit               glitch;
    bit               timing_err;   // a bit was not stable over its centre half
    bit               par_en;
    bit               par_odd;
    int unsigned      div;
    longint unsigned  t_end;        // cycle count at the stop-bit sample

    constraint c_kind { kind dist {FR_GOOD := 80, FR_FRAME_ERR := 6, FR_PARITY_ERR := 6,
                                   FR_GLITCH := 5, FR_BREAK := 3}; }
    constraint c_skew { skew_ppt inside {[-25:25]};
                        skew_ppt dist {0 := 4, [-25:-1] :/ 3, [1:25] :/ 3}; }
    constraint c_idle { idle_bits dist {0 := 3, [1:2] := 2, [3:8] := 1}; }
    constraint c_data { data dist {8'h00 := 1, 8'hFF := 1, 8'h55 := 1, 8'hAA := 1, [8'h01:8'hFE] :/ 12}; }

    function new(string name = "uart_item"); super.new(name); endfunction

    function void do_copy(uvm_object rhs);
      uart_item r;
      super.do_copy(rhs);
      if (!$cast(r, rhs)) `uvm_fatal("CAST", "do_copy")
      data = r.data; kind = r.kind; skew_ppt = r.skew_ppt; idle_bits = r.idle_bits;
      par_bit = r.par_bit; frame_err = r.frame_err; parity_err = r.parity_err;
      glitch = r.glitch; timing_err = r.timing_err; par_en = r.par_en;
      par_odd = r.par_odd; div = r.div; t_end = r.t_end;
    endfunction

    function string convert2string();
      return $sformatf("data=0x%02h kind=%s fe=%0b pe=%0b gl=%0b te=%0b %s div=%0d",
                       data, kind.name(), frame_err, parity_err, glitch, timing_err,
                       par_en ? (par_odd ? "8O1" : "8E1") : "8N1", div);
    endfunction
  endclass

  typedef uvm_sequencer #(uart_item) uart_sequencer;

  // ------------------------------------------------------------- driver
  // Drives DUT.rxd. Bit edges are placed at round(k * bit_clks * (1+skew))
  // clock cycles from the start edge, i.e. a remote transmitter whose baud
  // clock is off by skew_ppt / 1000.
  class uart_driver extends uvm_driver #(uart_item);
    `uvm_component_utils(uart_driver)
    uart_vif_t vif;
    uart_cfg   cfg;
    uvm_analysis_port #(uart_item) drv_ap;   // driven stimulus (for coverage)

    function new(string name, uvm_component parent);
      super.new(name, parent);
      drv_ap = new("drv_ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(uart_vif_t)::get(this, "", "uart_vif", vif)) `uvm_fatal("NOVIF", "uart_driver")
      if (!uvm_config_db#(uart_cfg)::get(this, "", "cfg", cfg))   `uvm_fatal("NOCFG", "uart_driver")
    endfunction

    task run_phase(uvm_phase phase);
      vif.rxd = 1'b1;
      forever begin
        seq_item_port.get_next_item(req);
        drive(req);
        seq_item_port.item_done();
      end
    endtask

    task wait_clks(int n);
      repeat (n) @(posedge vif.clk);
      #1;
    endtask

    task drive(uart_item t);
      bit          bits[$];
      real         bclk;
      int unsigned prev_edge = 0;
      bit          par;

      @(posedge vif.clk); #1;
      vif.rxd = 1'b1;
      if (t.idle_bits > 0) wait_clks(t.idle_bits * cfg.bit_clks());
      // read the line configuration only now, at the start of the frame: the
      // scoreboard updates cfg one cycle after a CTRL/BAUD write completes
      bclk = real'(cfg.bit_clks()) * (1.0 + real'(t.skew_ppt) / 1000.0);
      par  = ^t.data ^ cfg.par_odd;

      if (t.kind == FR_GLITCH) begin
        uart_item c = uart_item::type_id::create("drv_copy");
        c.copy(t);
        c.par_en = cfg.par_en; c.par_odd = cfg.par_odd; c.div = cfg.div;
        drv_ap.write(c);
        // low pulse of 1/4 bit: a receiver must reject it at mid-bit
        vif.rxd = 1'b0;
        wait_clks(cfg.bit_clks() / 4);
        vif.rxd = 1'b1;
        wait_clks(cfg.bit_clks() * 2);
        return;
      end

      bits.push_back(1'b0);                                     // start
      for (int i = 0; i < 8; i++)
        bits.push_back(t.kind == FR_BREAK ? 1'b0 : t.data[i]);  // data LSB first
      if (cfg.par_en)
        bits.push_back(t.kind == FR_BREAK ? 1'b0 :
                       (t.kind == FR_PARITY_ERR ? !par : par));
      bits.push_back((t.kind == FR_FRAME_ERR || t.kind == FR_BREAK) ? 1'b0 : 1'b1);  // stop

      begin
        uart_item c = uart_item::type_id::create("drv_copy");
        c.copy(t);
        c.par_en = cfg.par_en; c.par_odd = cfg.par_odd; c.div = cfg.div;
        drv_ap.write(c);
      end
      foreach (bits[k]) begin
        int unsigned edge_at = $rtoi(real'(k + 1) * bclk + 0.5);
        vif.rxd = bits[k];
        wait_clks(edge_at - prev_edge);
        prev_edge = edge_at;
      end
      vif.rxd = 1'b1;
      // a break holds the line low for a further bit time
      if (t.kind == FR_BREAK) begin
        vif.rxd = 1'b0;
        wait_clks(cfg.bit_clks());
        vif.rxd = 1'b1;
      end
      wait_clks(1);
    endtask
  endclass

  // ------------------------------------------------------------ monitor
  // Decodes frames on one line. Samples every bit at 1/4, 1/2 and 3/4 of
  // its nominal length: the middle sample is the value, disagreement among
  // the three flags a timing error (used on txd to check the DUT's bit
  // timing; on rxd the skewed driver legitimately trips it, so it is ignored).
  class uart_monitor extends uvm_monitor;
    `uvm_component_utils(uart_monitor)
    uart_vif_t vif;
    uart_cfg   cfg;
    bit        watch_tx = 1;   // 1: DUT txd, 0: DUT rxd
    uvm_analysis_port #(uart_item) ap;        // completed frames (and glitches)
    uvm_analysis_port #(uart_item) start_ap;  // start-bit edge (txd only)
    longint unsigned cycle;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      ap = new("ap", this);
      start_ap = new("start_ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(uart_vif_t)::get(this, "", "uart_vif", vif)) `uvm_fatal("NOVIF", "uart_monitor")
      if (!uvm_config_db#(uart_cfg)::get(this, "", "cfg", cfg))   `uvm_fatal("NOCFG", "uart_monitor")
    endfunction

    function bit line();
      return watch_tx ? vif.txd : vif.rxd;
    endfunction

    int unsigned elapsed;   // cycles since the detected start edge

    task wait_until(int unsigned target);
      while (elapsed < target) begin @(negedge vif.clk); cycle++; elapsed++; end
    endtask

    task run_phase(uvm_phase phase);
      bit prev = 1;
      forever begin
        uart_item    t;
        int unsigned bc, q, h, base;
        bit          s1, s2, s3;
        int          nbits;
        // wait for a falling edge
        @(negedge vif.clk); cycle++;
        if (!vif.rst_n) begin prev = 1; continue; end
        if (!(prev && !line())) begin prev = line(); continue; end
        // edge seen at this negedge: bit k spans [k*bc, (k+1)*bc) from here
        elapsed = 0;
        t = uart_item::type_id::create(watch_tx ? "tx_frame" : "rx_frame");
        bc = cfg.bit_clks();
        q  = bc / 4;
        h  = bc / 2;
        t.par_en = cfg.par_en; t.par_odd = cfg.par_odd; t.div = cfg.div;
        if (watch_tx) start_ap.write(t);
        // start bit
        wait_until(q);     s1 = line();
        wait_until(h);     s2 = line();
        if (s2) begin      // high at mid-start: false start / glitch
          t.glitch = 1;
          t.t_end = cycle;
          ap.write(t);
          prev = line();
          continue;
        end
        wait_until(h + q); s3 = line();
        if (s1 || s3) t.timing_err = 1;
        nbits = cfg.par_en ? 10 : 9;              // data (8) + parity + stop
        for (int k = 1; k <= nbits; k++) begin
          base = k * bc;
          wait_until(base + q); s1 = line();
          wait_until(base + h); s2 = line();
          if (k == nbits) begin
            // stop bit: decide at its middle, like the DUT
            t.frame_err = !s2;
            t.t_end = cycle;
            if (s1 != s2) t.timing_err = 1;
            break;
          end
          wait_until(base + h + q); s3 = line();
          if (s1 != s2 || s2 != s3) t.timing_err = 1;
          if (k <= 8) t.data[k-1] = s2;
          else        t.par_bit   = s2;
        end
        if (cfg.par_en && !t.frame_err)
          t.parity_err = (t.par_bit != (^t.data ^ cfg.par_odd));
        // publish at mid-stop (the receiver's decision point) ...
        ap.write(t);
        if (watch_tx) begin
          // ... then check that the DUT's stop bit is still high at 3/4 of its length
          wait_until(nbits * bc + h + q); s3 = line();
          if (!t.frame_err && !s3)
            `uvm_error("TXSTOP", $sformatf("DUT stop bit ended early (frame data 0x%02h)", t.data))
        end
        prev = line();
        // after a low stop bit (framing error / break) wait for the line to idle
        if (!prev) begin
          while (!line()) begin @(negedge vif.clk); cycle++; end
          prev = 1;
        end
      end
    endtask
  endclass

  // -------------------------------------------------------------- agent
  class uart_agent extends uvm_agent;
    `uvm_component_utils(uart_agent)
    uart_sequencer sqr;
    uart_driver    drv;
    uart_monitor   rx_mon;   // DUT rxd line (what the driver sent)
    uart_monitor   tx_mon;   // DUT txd line

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      rx_mon = uart_monitor::type_id::create("rx_mon", this);
      tx_mon = uart_monitor::type_id::create("tx_mon", this);
      rx_mon.watch_tx = 0;
      tx_mon.watch_tx = 1;
      if (get_is_active() == UVM_ACTIVE) begin
        sqr = uart_sequencer::type_id::create("sqr", this);
        drv = uart_driver::type_id::create("drv", this);
      end
    endfunction

    function void connect_phase(uvm_phase phase);
      if (get_is_active() == UVM_ACTIVE) drv.seq_item_port.connect(sqr.seq_item_export);
    endfunction
  endclass

  // ---------------------------------------------------------- sequences
  class uart_frame_seq extends uvm_sequence #(uart_item);
    `uvm_object_utils(uart_frame_seq)
    rand int unsigned n;
    bit only_good = 0;
    bit no_skew   = 0;
    constraint c_n { soft n inside {[4:20]}; }
    function new(string name = "uart_frame_seq"); super.new(name); endfunction
    task body();
      repeat (n) begin
        uart_item t = uart_item::type_id::create("t");
        start_item(t);
        if (!t.randomize() with { only_good -> kind == FR_GOOD; no_skew -> skew_ppt == 0; })
          `uvm_fatal("RAND", "uart_frame_seq")
        finish_item(t);
      end
    endtask
  endclass
endpackage
