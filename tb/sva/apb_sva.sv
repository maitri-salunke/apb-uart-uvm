// apb_sva.sv - AMBA 3 APB protocol checker (concurrent SVA)
// Instantiated in tb_top on the APB signals. Master-side rules check the UVM
// driver (and anything that replaces it, e.g. a CPU bridge); slave-side rules
// check the DUT.
module apb_sva #(parameter int AW = 12, parameter int MAX_WAIT = 16) (
  input logic          pclk,
  input logic          presetn,
  input logic          psel,
  input logic          penable,
  input logic          pwrite,
  input logic [AW-1:0] paddr,
  input logic [31:0]   pwdata,
  input logic [31:0]   prdata,
  input logic          pready,
  input logic          pslverr
);
  wire setup  = psel && !penable;
  wire access = psel &&  penable;
  wire done   = access && pready;

  default clocking cb @(posedge pclk); endclocking
  default disable iff (!presetn);

  // ---- master side -------------------------------------------------------
  // A01 PSEL is never X/Z out of reset
  A01_psel_not_x:      assert property (!$isunknown(psel))
                         else $error("APB A01: PSEL is X/Z");
  // A02 PENABLE only together with PSEL
  A02_penable_has_sel: assert property (penable |-> psel)
                         else $error("APB A02: PENABLE without PSEL");
  // A03 SETUP is always followed by ACCESS
  A03_setup_to_access: assert property (setup |=> access)
                         else $error("APB A03: SETUP not followed by ACCESS");
  // A04 ACCESS that is not completed stays ACCESS
  A04_wait_holds:      assert property (access && !pready |=> access)
                         else $error("APB A04: ACCESS abandoned during wait state");
  // A05..A07 address/direction/write-data stable from SETUP through the end of ACCESS
  A05_paddr_stable:    assert property (psel && !done |=> $stable(paddr))
                         else $error("APB A05: PADDR changed during transfer");
  A06_pwrite_stable:   assert property (psel && !done |=> $stable(pwrite))
                         else $error("APB A06: PWRITE changed during transfer");
  A07_pwdata_stable:   assert property (psel && pwrite && !done |=> $stable(pwdata))
                         else $error("APB A07: PWDATA changed during write transfer");
  // A08 PENABLE drops after a completed transfer
  A08_penable_drops:   assert property (done |=> !penable)
                         else $error("APB A08: PENABLE held after completed transfer");
  // A09 control/address/data known whenever selected
  A09_ctrl_not_x:      assert property (psel |-> !$isunknown({penable, pwrite, paddr}))
                         else $error("APB A09: X on PENABLE/PWRITE/PADDR while selected");
  A10_pwdata_not_x:    assert property (psel && pwrite |-> !$isunknown(pwdata))
                         else $error("APB A10: X on PWDATA during write");

  // ---- slave side (DUT) --------------------------------------------------
  // A11 PREADY must arrive within MAX_WAIT cycles of entering ACCESS
  A11_pready_timeout:  assert property ($rose(access) |-> ##[0:MAX_WAIT] pready)
                         else $error("APB A11: PREADY timeout (> %0d wait states)", MAX_WAIT);
  // A12 PREADY known during ACCESS
  A12_pready_not_x:    assert property (access |-> !$isunknown(pready))
                         else $error("APB A12: X on PREADY during ACCESS");
  // A13 PSLVERR only in the completing cycle
  A13_pslverr_valid:   assert property (pslverr |-> done)
                         else $error("APB A13: PSLVERR outside completing ACCESS cycle");
  // A14 read data known when a read completes without error
  A14_prdata_not_x:    assert property (done && !pwrite && !pslverr |-> !$isunknown(prdata))
                         else $error("APB A14: X on PRDATA in completing read");

  // ---- protocol scenario covers -----------------------------------------
  C01_zero_wait:   cover property (setup ##1 (access && pready));
  C02_wait_state:  cover property (setup ##1 (access && !pready) ##1 (access && pready));
  C03_back2back:   cover property (done ##1 setup);
  C04_error_resp:  cover property (done && pslverr);
  C05_idle_gap:    cover property (done ##1 !psel ##1 setup);
endmodule
