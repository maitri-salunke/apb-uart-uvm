// uart_dut_sva.sv - white-box assertions bound into the DUT (bind apb_uart ...)
module uart_dut_sva #(parameter int DEPTH = 16, parameter int LW = 5) (
  input logic          pclk,
  input logic          presetn,
  input logic [LW-1:0] tx_level,
  input logic [LW-1:0] rx_level,
  input logic          tx_busy,
  input logic          txd_int,
  input logic          irq,
  input logic [5:0]    int_stat,
  input logic [5:0]    int_en,
  input logic          loopback,
  input logic          txd
);
  default clocking cb @(posedge pclk); endclocking
  default disable iff (!presetn);

  // A15/A16 FIFO occupancy never exceeds the depth
  A15_txf_bound: assert property (tx_level <= LW'(DEPTH)) else $error("DUT A15: TX FIFO level > depth");
  A16_rxf_bound: assert property (rx_level <= LW'(DEPTH)) else $error("DUT A16: RX FIFO level > depth");
  // A17 interrupt output is exactly the masked status
  A17_irq_func:  assert property (irq == |(int_stat & int_en)) else $error("DUT A17: irq != |(INT_STAT & INT_EN)");
  // A18 serial line idles high when the transmitter is idle
  A18_tx_idle:   assert property (!tx_busy |-> txd_int) else $error("DUT A18: txd low while TX idle");
  // A19 FIFO level changes by at most one per cycle
  A19_txf_step:  assert property (tx_level == $past(tx_level) || tx_level == $past(tx_level) + 1'b1 ||
                                  tx_level == $past(tx_level) - 1'b1 || tx_level == '0)
                   else $error("DUT A19: TX FIFO level jumped");
  A20_rxf_step:  assert property (rx_level == $past(rx_level) || rx_level == $past(rx_level) + 1'b1 ||
                                  rx_level == $past(rx_level) - 1'b1 || rx_level == '0)
                   else $error("DUT A20: RX FIFO level jumped");
  // A21 txd pin follows the transmitter, or idles high in loopback
  A21_txd_pin:   assert property (txd == (loopback ? 1'b1 : txd_int)) else $error("DUT A21: txd pin wrong for loopback mode");
endmodule

bind apb_uart uart_dut_sva #(.DEPTH(FIFO_DEPTH), .LW(LW)) u_dut_sva (
  .pclk(pclk), .presetn(presetn), .tx_level(tx_level), .rx_level(rx_level),
  .tx_busy(tx_busy), .txd_int(txd_int), .irq(irq), .int_stat(int_stat), .int_en(int_en),
  .loopback(loopback), .txd(txd)
);
