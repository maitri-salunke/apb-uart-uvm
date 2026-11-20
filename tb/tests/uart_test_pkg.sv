// uart_test_pkg.sv - UVM tests. Select with +UVM_TESTNAME=<name>.
package uart_test_pkg;
  import uvm_pkg::*;
  import uart_pkg::*;
  import uart_env_pkg::*;
  import uart_seq_pkg::*;
  `include "uvm_macros.svh"

  class uart_base_test extends uvm_test;
    `uvm_component_utils(uart_base_test)
    uart_env env;
    uart_cfg cfg;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      cfg = uart_cfg::type_id::create("cfg");
      uvm_config_db#(uart_cfg)::set(this, "*", "cfg", cfg);
      env = uart_env::type_id::create("env", this);
    endfunction

    function void end_of_elaboration_phase(uvm_phase phase);
      uvm_top.set_timeout(200ms, 0);
    endfunction

    // overridden by each test
    virtual function uart_base_vseq make_vseq();
      return null;
    endfunction

    task run_phase(uvm_phase phase);
      uart_base_vseq vs;
      phase.raise_objection(this);
      @(posedge env.sb.vif.presetn);
      repeat (5) @(posedge env.sb.vif.pclk);
      vs = make_vseq();
      if (vs != null) begin
        if (!vs.randomize()) `uvm_fatal("RAND", "top vseq")
        `uvm_info("TEST", $sformatf("running %s (div=%0d par_en=%0b par_odd=%0b)",
                  vs.get_type_name(), vs.div, vs.par_en, vs.par_odd), UVM_LOW)
        vs.start(env.vsqr);
      end
      repeat (200) @(posedge env.sb.vif.pclk);
      phase.drop_objection(this);
    endtask

    function void report_phase(uvm_phase phase);
      uvm_report_server rs = uvm_report_server::get_server();
      if (rs.get_severity_count(UVM_ERROR) + rs.get_severity_count(UVM_FATAL) == 0)
        `uvm_info("RESULT", "TEST PASSED", UVM_NONE)
      else
        `uvm_info("RESULT", "TEST FAILED", UVM_NONE)
    endfunction
  endclass

  `define UART_TEST(TNAME, VSEQ) \
    class TNAME extends uart_base_test; \
      `uvm_component_utils(TNAME) \
      function new(string name, uvm_component parent); super.new(name, parent); endfunction \
      virtual function uart_base_vseq make_vseq(); \
        VSEQ s = VSEQ::type_id::create("vseq"); \
        return s; \
      endfunction \
    endclass

  `UART_TEST(uart_reg_test,      reg_vseq)
  `UART_TEST(uart_tx_test,       tx_vseq)
  `UART_TEST(uart_rx_test,       rx_vseq)
  `UART_TEST(uart_fifo_test,     fifo_vseq)
  `UART_TEST(uart_loopback_test, loopback_vseq)
  `UART_TEST(uart_irq_test,      irq_vseq)
  `UART_TEST(uart_duplex_test,   duplex_vseq)
  `UART_TEST(uart_apb_rand_test, apb_rand_vseq)
  `UART_TEST(uart_rand_test,     rand_vseq)
  `UART_TEST(uart_slow_baud_test, slow_baud_vseq)
endpackage
