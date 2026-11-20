# Mutation campaign: 14/14 caught

Each mutant: 10 tests x seeds 1..2.

| Mutation | File | Bug | Result | Failing runs | First detector |
|---|---|---|---|---|---|
| MUT_FIFO_LEVEL | uart_fifo.sv | simultaneous push+pop decrements the level | caught | 2/20 | ST_TXLVL |
| MUT_BAUD_OFF_BY_ONE | uart_baud_gen.sv | baud divider terminal count one short | caught | 14/20 | ST_TXBUSY |
| MUT_PARITY_INV | uart_tx.sv | TX parity sense inverted | caught | 11/20 | TX_PARITY |
| MUT_TX_MSB_FIRST | uart_tx.sv | TX shifts MSB first | caught | 14/20 | TX_DATA |
| MUT_TX_STOP_SHORT | uart_tx.sv | TX stop bit half length | caught | 12/20 | ST_TXBUSY |
| MUT_RX_NO_FRAME_CHECK | uart_rx.sv | RX ignores the stop bit (no framing error) | caught | 4/20 | RD_INTST |
| MUT_PREADY_HANG | apb_uart.sv | PREADY never asserted for writes to RX_THR | caught | 8/20 | SVA A11_pready_timeout |
| MUT_NO_PSLVERR | apb_uart.sv | unmapped addresses accepted without PSLVERR | caught | 5/20 | APB_ERR |
| MUT_RX_OVF_NOSET | apb_uart.sv | RX overflow sticky bit never set | caught | 3/20 | RD_INTST |
| MUT_CTRL_RESET | apb_uart.sv | CTRL resets with RX disabled | caught | 2/20 | UVM_ERROR RAL mirror check (uvm_reg.svh) |
| MUT_W1C_AS_RW | apb_uart.sv | INT_STAT is plain RW, writing 0 clears | caught | 10/20 | RD_INTST |
| MUT_RX_THR_GT | apb_uart.sv | RX threshold compares > instead of >= | caught | 3/20 | RD_INTST |
| MUT_STATUS_SWAP | apb_uart.sv | STATUS TX_FULL/TX_EMPTY bits swapped | caught | 18/20 | ST_TXFULL |
| MUT_LOOPBACK_BROKEN | apb_uart.sv | loopback mux ignores CTRL.LOOPBACK | caught | 4/20 | ST_RXEMPTY |

First failure message per mutant:

- MUT_FIFO_LEVEL: `UVM_ERROR tb/env/uart_env_pkg.sv(230) @ 321000: uvm_test_top.env.sb [ST_TXLVL] STATUS.TX_LEVEL=2 model 3`
- MUT_BAUD_OFF_BY_ONE: `UVM_ERROR tb/env/uart_env_pkg.sv(230) @ 3741000: uvm_test_top.env.sb [ST_TXBUSY] STATUS.TX_BUSY=0 expected 1`
- MUT_PARITY_INV: `UVM_ERROR tb/env/uart_env_pkg.sv(230) @ 5260000: uvm_test_top.env.sb [TX_PARITY] TX parity bit wrong for  odd`
- MUT_TX_MSB_FIRST: `UVM_ERROR tb/env/uart_env_pkg.sv(230) @ 5260000: uvm_test_top.env.sb [TX_DATA] TX data 0x76, expected 0x6e`
- MUT_TX_STOP_SHORT: `UVM_ERROR tb/env/uart_env_pkg.sv(230) @ 5271000: uvm_test_top.env.sb [ST_TXBUSY] STATUS.TX_BUSY=0 expected 1`
- MUT_RX_NO_FRAME_CHECK: `UVM_ERROR tb/env/uart_env_pkg.sv(230) @ 137521000: uvm_test_top.env.sb [RD_INTST] INT_STAT read 0x13, model 0x1b (mask 0x3f)`
- MUT_PREADY_HANG: `[11725000] %Error: apb_sva.sv:56: Assertion failed in tb_top.u_apb_sva.A11_pready_timeout: APB A11: PREADY timeout (> 16 wait states)`
- MUT_NO_PSLVERR: `UVM_ERROR tb/env/uart_env_pkg.sv(230) @ 15511000: uvm_test_top.env.sb [APB_ERR] WR addr=0x01c data=0x12345678 err=0 waits=1: PSLVERR=0 expected 1`
- MUT_RX_OVF_NOSET: `UVM_ERROR tb/env/uart_env_pkg.sv(230) @ 150751000: uvm_test_top.env.sb [RD_INTST] INT_STAT read 0x03, model 0x07 (mask 0x3f)`
- MUT_CTRL_RESET: `UVM_ERROR RAL mirror check (uvm_reg.svh)) @ 170000: reporter [RegModel] Register "regmodel.CTRL" value read from DUT (0x0000000000000001) does not match mirrored value (0x000000000`
- MUT_W1C_AS_RW: `UVM_ERROR tb/env/uart_env_pkg.sv(230) @ 92001000: uvm_test_top.env.sb [RD_INTST] INT_STAT read 0x3e, model 0x02 (mask 0x3f)`
- MUT_RX_THR_GT: `UVM_ERROR tb/env/uart_env_pkg.sv(230) @ 14371000: uvm_test_top.env.sb [RD_INTST] INT_STAT read 0x02, model 0x03 (mask 0x3f)`
- MUT_STATUS_SWAP: `UVM_ERROR tb/env/uart_env_pkg.sv(230) @ 121000: uvm_test_top.env.sb [ST_TXFULL] STATUS.TX_FULL=1 model level 0`
- MUT_LOOPBACK_BROKEN: `UVM_ERROR tb/env/uart_env_pkg.sv(230) @ 7131000: uvm_test_top.env.sb [ST_RXEMPTY] STATUS.RX_EMPTY=1 model level 1`
