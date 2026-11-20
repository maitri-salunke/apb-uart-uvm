// tb_top.sv - testbench top: clock/reset, DUT, interfaces, SVA, run_test()
`timescale 1ns/1ps
`ifndef TB_WAIT_STATES
  `define TB_WAIT_STATES 1
`endif
module tb_top;
  import uvm_pkg::*;
  import apb_pkg::*;
  import uart_pkg::*;
  import uart_test_pkg::*;

  logic pclk = 0;
  logic presetn = 0;
  always #5 pclk = ~pclk;           // 100 MHz
  initial begin
    repeat (4) @(posedge pclk);
    #1 presetn = 1;
  end

  apb_if #(12) apb (.pclk(pclk), .presetn(presetn));
  uart_if      ser (.clk(pclk),  .rst_n(presetn));

  apb_uart #(.ADDR_W(12), .FIFO_DEPTH(16), .WAIT_STATES(`TB_WAIT_STATES)) dut (
    .pclk(pclk), .presetn(presetn),
    .psel(apb.psel), .penable(apb.penable), .pwrite(apb.pwrite),
    .paddr(apb.paddr), .pwdata(apb.pwdata), .prdata(apb.prdata),
    .pready(apb.pready), .pslverr(apb.pslverr),
    .rxd(ser.rxd), .txd(), .irq(apb.irq)
  );
  // The TX monitor watches the transmitter output before the loopback mux so
  // loopback traffic is observable; the pin itself is checked by SVA A21.
  assign ser.txd = dut.txd_int;

  apb_sva #(.AW(12), .MAX_WAIT(16)) u_apb_sva (
    .pclk(pclk), .presetn(presetn), .psel(apb.psel), .penable(apb.penable),
    .pwrite(apb.pwrite), .paddr(apb.paddr), .pwdata(apb.pwdata),
    .prdata(apb.prdata), .pready(apb.pready), .pslverr(apb.pslverr)
  );

  initial begin
    uvm_config_db#(apb_vif_t)::set(null, "*", "apb_vif", apb);
    uvm_config_db#(uart_vif_t)::set(null, "*", "uart_vif", ser);
    run_test();
  end
endmodule
