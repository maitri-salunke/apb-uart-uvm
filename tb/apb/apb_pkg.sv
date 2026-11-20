// apb_pkg.sv - UVM agent for an AMBA 3 APB master
package apb_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  typedef virtual apb_if #(12) apb_vif_t;

  // ------------------------------------------------------------------ item
  class apb_item extends uvm_sequence_item;
    rand bit        write;
    rand bit [11:0] addr;
    rand bit [31:0] data;        // write data, or read data returned by the DUT
    rand int unsigned idle;      // idle cycles (PSEL low) before this transfer
    bit             slverr;      // response
    int unsigned    waits;       // observed wait states
    bit             irq;         // sideband irq sampled at completion
    bit             b2b;         // monitor: started right after previous transfer

    constraint c_align { addr[1:0] == 2'b00; }
    constraint c_idle  { idle dist {0 := 4, [1:3] := 3, [4:10] := 1}; }

    `uvm_object_utils(apb_item)
    function new(string name = "apb_item"); super.new(name); endfunction

    function void do_copy(uvm_object rhs);
      apb_item r;
      super.do_copy(rhs);
      if (!$cast(r, rhs)) `uvm_fatal("CAST", "do_copy")
      write = r.write; addr = r.addr; data = r.data; idle = r.idle;
      slverr = r.slverr; waits = r.waits; irq = r.irq; b2b = r.b2b;
    endfunction

    function string convert2string();
      return $sformatf("%s addr=0x%03h data=0x%08h err=%0b waits=%0d",
                       write ? "WR" : "RD", addr, data, slverr, waits);
    endfunction
  endclass

  // ------------------------------------------------------------- sequencer
  typedef uvm_sequencer #(apb_item) apb_sequencer;

  // ---------------------------------------------------------------- driver
  // Drives on posedge+1 so the DUT samples stable values on the next edge.
  class apb_driver extends uvm_driver #(apb_item);
    `uvm_component_utils(apb_driver)
    apb_vif_t vif;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(apb_vif_t)::get(this, "", "apb_vif", vif))
        `uvm_fatal("NOVIF", "apb_driver: no vif")
    endfunction

    task run_phase(uvm_phase phase);
      vif.psel    = 1'b0;
      vif.penable = 1'b0;
      vif.pwrite  = 1'b0;
      vif.paddr   = '0;
      vif.pwdata  = '0;
      @(posedge vif.presetn);
      forever begin
        @(posedge vif.pclk); #1;
        seq_item_port.try_next_item(req);
        if (req == null) begin
          vif.psel    = 1'b0;       // bus idle
          vif.penable = 1'b0;
          continue;
        end
        drive(req);
        seq_item_port.item_done();
      end
    endtask

    // Entered at posedge+1. With idle == 0 directly after a completed
    // transfer this produces a back-to-back SETUP (PSEL stays high).
    task drive(apb_item t);
      if (t.idle > 0) begin
        vif.psel    = 1'b0;
        vif.penable = 1'b0;
        repeat (t.idle) @(posedge vif.pclk);
        #1;
      end
      // SETUP
      vif.psel    = 1'b1;
      vif.penable = 1'b0;
      vif.pwrite  = t.write;
      vif.paddr   = t.addr;
      vif.pwdata  = t.write ? t.data : 32'h0;
      // ACCESS
      @(posedge vif.pclk); #1;
      vif.penable = 1'b1;
      t.waits = 0;
      forever begin
        @(negedge vif.pclk);
        if (vif.pready) break;
        t.waits++;
      end
      if (!t.write) t.data = vif.prdata;
      t.slverr = vif.pslverr;
    endtask
  endclass

  // --------------------------------------------------------------- monitor
  // Samples on negedge (mid-cycle) and publishes each completed transfer.
  class apb_monitor extends uvm_monitor;
    `uvm_component_utils(apb_monitor)
    apb_vif_t vif;
    uvm_analysis_port #(apb_item) ap;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(apb_vif_t)::get(this, "", "apb_vif", vif))
        `uvm_fatal("NOVIF", "apb_monitor: no vif")
    endfunction

    task run_phase(uvm_phase phase);
      int unsigned waits = 0;
      bit          last_done = 0;
      bit          in_xfer = 0;
      bit          b2b = 0;
      forever begin
        @(negedge vif.pclk);
        if (!vif.presetn) begin waits = 0; last_done = 0; in_xfer = 0; continue; end
        if (vif.psel && !vif.penable) begin
          b2b = last_done;
          in_xfer = 1;
        end
        last_done = 0;
        if (vif.psel && vif.penable) begin
          if (vif.pready) begin
            apb_item t = apb_item::type_id::create("mon_item");
            t.write  = vif.pwrite;
            t.addr   = vif.paddr;
            t.data   = vif.pwrite ? vif.pwdata : vif.prdata;
            t.slverr = vif.pslverr;
            t.waits  = waits;
            t.irq    = vif.irq;
            t.b2b    = b2b;
            ap.write(t);
            waits = 0;
            last_done = 1;
            in_xfer = 0;
          end else begin
            waits++;
          end
        end
      end
    endtask
  endclass

  // ----------------------------------------------------------------- agent
  class apb_agent extends uvm_agent;
    `uvm_component_utils(apb_agent)
    apb_sequencer sqr;
    apb_driver    drv;
    apb_monitor   mon;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      mon = apb_monitor::type_id::create("mon", this);
      if (get_is_active() == UVM_ACTIVE) begin
        sqr = apb_sequencer::type_id::create("sqr", this);
        drv = apb_driver::type_id::create("drv", this);
      end
    endfunction

    function void connect_phase(uvm_phase phase);
      if (get_is_active() == UVM_ACTIVE) drv.seq_item_port.connect(sqr.seq_item_export);
    endfunction
  endclass

  // ------------------------------------------------------------- sequences
  class apb_rw_seq extends uvm_sequence #(apb_item);
    `uvm_object_utils(apb_rw_seq)
    rand bit        write;
    rand bit [11:0] addr;
    rand bit [31:0] data;
    bit             slverr;
    function new(string name = "apb_rw_seq"); super.new(name); endfunction
    task body();
      apb_item t = apb_item::type_id::create("t");
      start_item(t);
      if (!t.randomize() with { write == local::write; addr == local::addr; data == local::data; })
        `uvm_fatal("RAND", "apb_rw_seq")
      finish_item(t);
      data = t.data;
      slverr = t.slverr;
    endtask
  endclass

  // Random accesses anywhere in the 4 KB window (mapped and unmapped)
  class apb_random_seq extends uvm_sequence #(apb_item);
    `uvm_object_utils(apb_random_seq)
    rand int unsigned n;
    bit allow_data_read = 0;
    constraint c_n { n inside {[20:60]}; }
    function new(string name = "apb_random_seq"); super.new(name); endfunction
    task body();
      repeat (n) begin
        apb_item t = apb_item::type_id::create("t");
        t.c_align.constraint_mode(0);     // PADDR[1:0] must be ignored by the slave
        start_item(t);
        if (!t.randomize() with {
              addr dist { [12'h000:12'h018] :/ 6, [12'h01C:12'h0FC] :/ 2, [12'h100:12'hFFC] :/ 1 };
              // keep DATA out of random traffic: it has side effects the
              // directed sequences own (TX push / RX pop)
              !(addr[11:2] == 0);
              (addr[11:2] == 10'h002) -> data[9:8] == 2'b00;
            }) `uvm_fatal("RAND", "apb_random_seq")
        finish_item(t);
      end
    endtask
  endclass
endpackage
