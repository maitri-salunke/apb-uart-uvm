// uart_if.sv - serial lines seen from the testbench
//   rxd : driven by the UVM UART driver into the DUT
//   txd : driven by the DUT, observed by the UART TX monitor
interface uart_if (input logic clk, input logic rst_n);
  logic rxd;
  logic txd;
endinterface
