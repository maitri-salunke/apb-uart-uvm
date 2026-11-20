// apb_if.sv - AMBA 3 APB interface (master side driven by the UVM APB agent)
interface apb_if #(parameter int AW = 12) (input logic pclk, input logic presetn);
  logic          psel;
  logic          penable;
  logic          pwrite;
  logic [AW-1:0] paddr;
  logic [31:0]   pwdata;
  logic [31:0]   prdata;
  logic          pready;
  logic          pslverr;
  logic          irq;      // sideband: UART interrupt, sampled by the APB monitor
endinterface
