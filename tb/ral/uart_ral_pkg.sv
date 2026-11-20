// uart_ral_pkg.sv - UVM register model (RAL) for apb_uart + APB adapter
// Hand-written to match docs/REGISTERS.md.
package uart_ral_pkg;
  import uvm_pkg::*;
  import apb_pkg::*;
  `include "uvm_macros.svh"

  // DATA: write pushes TX FIFO, read pops RX FIFO -> volatile, never compared
  class reg_data extends uvm_reg;
    `uvm_object_utils(reg_data)
    rand uvm_reg_field data;
    function new(string name = "DATA"); super.new(name, 32, UVM_NO_COVERAGE); endfunction
    virtual function void build();
      data = uvm_reg_field::type_id::create("data");
      data.configure(this, 8, 0, "RW", 1, 8'h00, 1, 1, 0);
      data.set_compare(UVM_NO_CHECK);
    endfunction
  endclass

  class reg_status extends uvm_reg;
    `uvm_object_utils(reg_status)
    uvm_reg_field tx_full, tx_empty, rx_full, rx_empty, tx_busy, tx_level, rx_level;
    function new(string name = "STATUS"); super.new(name, 32, UVM_NO_COVERAGE); endfunction
    virtual function void build();
      tx_full  = uvm_reg_field::type_id::create("tx_full");
      tx_empty = uvm_reg_field::type_id::create("tx_empty");
      rx_full  = uvm_reg_field::type_id::create("rx_full");
      rx_empty = uvm_reg_field::type_id::create("rx_empty");
      tx_busy  = uvm_reg_field::type_id::create("tx_busy");
      tx_level = uvm_reg_field::type_id::create("tx_level");
      rx_level = uvm_reg_field::type_id::create("rx_level");
      //                parent size lsb access volatile reset has_reset rand indiv
      tx_full .configure(this, 1,  0, "RO", 1, 1'b0, 1, 0, 0);
      tx_empty.configure(this, 1,  1, "RO", 1, 1'b1, 1, 0, 0);
      rx_full .configure(this, 1,  2, "RO", 1, 1'b0, 1, 0, 0);
      rx_empty.configure(this, 1,  3, "RO", 1, 1'b1, 1, 0, 0);
      tx_busy .configure(this, 1,  4, "RO", 1, 1'b0, 1, 0, 0);
      tx_level.configure(this, 5,  8, "RO", 1, 5'd0, 1, 0, 0);
      rx_level.configure(this, 5, 16, "RO", 1, 5'd0, 1, 0, 0);
    endfunction
  endclass

  class reg_ctrl extends uvm_reg;
    `uvm_object_utils(reg_ctrl)
    rand uvm_reg_field tx_en, rx_en, par_en, par_odd, loopback;
    uvm_reg_field tx_clr, rx_clr;
    function new(string name = "CTRL"); super.new(name, 32, UVM_NO_COVERAGE); endfunction
    virtual function void build();
      tx_en    = uvm_reg_field::type_id::create("tx_en");
      rx_en    = uvm_reg_field::type_id::create("rx_en");
      par_en   = uvm_reg_field::type_id::create("par_en");
      par_odd  = uvm_reg_field::type_id::create("par_odd");
      loopback = uvm_reg_field::type_id::create("loopback");
      tx_clr   = uvm_reg_field::type_id::create("tx_clr");
      rx_clr   = uvm_reg_field::type_id::create("rx_clr");
      tx_en   .configure(this, 1, 0, "RW", 0, 1'b1, 1, 1, 0);
      rx_en   .configure(this, 1, 1, "RW", 0, 1'b1, 1, 1, 0);
      par_en  .configure(this, 1, 2, "RW", 0, 1'b0, 1, 1, 0);
      par_odd .configure(this, 1, 3, "RW", 0, 1'b0, 1, 1, 0);
      loopback.configure(this, 1, 4, "RW", 0, 1'b0, 1, 1, 0);
      // self-clearing flush strobes: write-only, read as 0
      tx_clr  .configure(this, 1, 8, "WO", 0, 1'b0, 1, 0, 0);
      rx_clr  .configure(this, 1, 9, "WO", 0, 1'b0, 1, 0, 0);
    endfunction
  endclass

  class reg_baud extends uvm_reg;
    `uvm_object_utils(reg_baud)
    rand uvm_reg_field div;
    function new(string name = "BAUD"); super.new(name, 32, UVM_NO_COVERAGE); endfunction
    virtual function void build();
      div = uvm_reg_field::type_id::create("div");
      div.configure(this, 16, 0, "RW", 0, 16'd26, 1, 1, 0);
    endfunction
  endclass

  class reg_int_en extends uvm_reg;
    `uvm_object_utils(reg_int_en)
    rand uvm_reg_field en;
    function new(string name = "INT_EN"); super.new(name, 32, UVM_NO_COVERAGE); endfunction
    virtual function void build();
      en = uvm_reg_field::type_id::create("en");
      en.configure(this, 6, 0, "RW", 0, 6'h00, 1, 1, 0);
    endfunction
  endclass

  class reg_int_stat extends uvm_reg;
    `uvm_object_utils(reg_int_stat)
    uvm_reg_field rx_thr, tx_empty, rx_ovf, frame_err, parity_err, tx_ovf;
    function new(string name = "INT_STAT"); super.new(name, 32, UVM_NO_COVERAGE); endfunction
    virtual function void build();
      rx_thr     = uvm_reg_field::type_id::create("rx_thr");
      tx_empty   = uvm_reg_field::type_id::create("tx_empty");
      rx_ovf     = uvm_reg_field::type_id::create("rx_ovf");
      frame_err  = uvm_reg_field::type_id::create("frame_err");
      parity_err = uvm_reg_field::type_id::create("parity_err");
      tx_ovf     = uvm_reg_field::type_id::create("tx_ovf");
      rx_thr    .configure(this, 1, 0, "RO",  1, 1'b0, 1, 0, 0);
      tx_empty  .configure(this, 1, 1, "RO",  1, 1'b1, 1, 0, 0);
      rx_ovf    .configure(this, 1, 2, "W1C", 1, 1'b0, 1, 0, 0);
      frame_err .configure(this, 1, 3, "W1C", 1, 1'b0, 1, 0, 0);
      parity_err.configure(this, 1, 4, "W1C", 1, 1'b0, 1, 0, 0);
      tx_ovf    .configure(this, 1, 5, "W1C", 1, 1'b0, 1, 0, 0);
    endfunction
  endclass

  class reg_rx_thr extends uvm_reg;
    `uvm_object_utils(reg_rx_thr)
    rand uvm_reg_field thr;
    function new(string name = "RX_THR"); super.new(name, 32, UVM_NO_COVERAGE); endfunction
    virtual function void build();
      thr = uvm_reg_field::type_id::create("thr");
      thr.configure(this, 5, 0, "RW", 0, 5'd1, 1, 1, 0);
    endfunction
  endclass

  class uart_reg_block extends uvm_reg_block;
    `uvm_object_utils(uart_reg_block)
    rand reg_data     DATA;
    reg_status        STATUS;
    rand reg_ctrl     CTRL;
    rand reg_baud     BAUD;
    rand reg_int_en   INT_EN;
    reg_int_stat      INT_STAT;
    rand reg_rx_thr   RX_THR;
    uvm_reg_map       apb_map;

    function new(string name = "uart_reg_block"); super.new(name, UVM_NO_COVERAGE); endfunction

    virtual function void build();
      DATA     = reg_data    ::type_id::create("DATA");
      STATUS   = reg_status  ::type_id::create("STATUS");
      CTRL     = reg_ctrl    ::type_id::create("CTRL");
      BAUD     = reg_baud    ::type_id::create("BAUD");
      INT_EN   = reg_int_en  ::type_id::create("INT_EN");
      INT_STAT = reg_int_stat::type_id::create("INT_STAT");
      RX_THR   = reg_rx_thr  ::type_id::create("RX_THR");
      DATA.configure(this);     DATA.build();
      STATUS.configure(this);   STATUS.build();
      CTRL.configure(this);     CTRL.build();
      BAUD.configure(this);     BAUD.build();
      INT_EN.configure(this);   INT_EN.build();
      INT_STAT.configure(this); INT_STAT.build();
      RX_THR.configure(this);   RX_THR.build();
      apb_map = create_map("apb_map", 'h0, 4, UVM_LITTLE_ENDIAN, 1);
      apb_map.add_reg(DATA,     'h00, "RW");
      apb_map.add_reg(STATUS,   'h04, "RO");
      apb_map.add_reg(CTRL,     'h08, "RW");
      apb_map.add_reg(BAUD,     'h0C, "RW");
      apb_map.add_reg(INT_EN,   'h10, "RW");
      apb_map.add_reg(INT_STAT, 'h14, "RW");
      apb_map.add_reg(RX_THR,   'h18, "RW");
      default_map = apb_map;
      // built-in sequence exclusions (side-effecting / volatile registers)
      uvm_resource_db#(bit)::set({"REG::", DATA.get_full_name()},     "NO_REG_TESTS", 1, this);
      uvm_resource_db#(bit)::set({"REG::", STATUS.get_full_name()},   "NO_REG_BIT_BASH_TEST", 1, this);
      uvm_resource_db#(bit)::set({"REG::", INT_STAT.get_full_name()}, "NO_REG_BIT_BASH_TEST", 1, this);
      lock_model();
    endfunction
  endclass

  // ---------------------------------------------------------------- adapter
  class apb_reg_adapter extends uvm_reg_adapter;
    `uvm_object_utils(apb_reg_adapter)
    function new(string name = "apb_reg_adapter");
      super.new(name);
      supports_byte_enable = 0;
      provides_responses   = 0;
    endfunction

    virtual function uvm_sequence_item reg2bus(const ref uvm_reg_bus_op rw);
      apb_item t = apb_item::type_id::create("reg_item");
      t.write = (rw.kind == UVM_WRITE);
      t.addr  = rw.addr[11:0];
      t.data  = rw.data[31:0];
      t.idle  = 0;
      return t;
    endfunction

    virtual function void bus2reg(uvm_sequence_item bus_item, ref uvm_reg_bus_op rw);
      apb_item t;
      if (!$cast(t, bus_item)) `uvm_fatal("CAST", "bus2reg")
      rw.kind   = t.write ? UVM_WRITE : UVM_READ;
      rw.addr   = {t.addr[11:2], 2'b00};   // the slave ignores PADDR[1:0]
      rw.data   = t.data;
      rw.status = t.slverr ? UVM_NOT_OK : UVM_IS_OK;
    endfunction
  endclass
endpackage
