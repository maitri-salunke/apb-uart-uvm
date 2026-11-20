# apb_uart register map

AMBA 3 APB slave, 32-bit data, word-aligned (`PADDR[1:0]` ignored). Default
`ADDR_W = 12`; any address with `PADDR[11:5] != 0` or `PADDR[4:2] == 7` is
unmapped.

## Bus behaviour

| Item | Behaviour |
|---|---|
| Wait states | Every access holds `PREADY = 0` for `WAIT_STATES` cycles (default 1) of the access phase, then completes. |
| `PSLVERR` | Asserted with `PREADY` for an unmapped address or a write to `STATUS`. An errored transfer has no side effects and reads return 0. |
| `PRDATA` | Valid only in the completing cycle of a read; 0 otherwise. |
| Side effects | Happen once, in the cycle where `PSEL & PENABLE & PREADY`. |

## Summary

| Offset | Name | Access | Reset | Description |
|---|---|---|---|---|
| 0x00 | DATA | W / R | 0x0000_0000 | Write: push `PWDATA[7:0]` to the TX FIFO. Read: pop the RX FIFO head (returns 0 and does not pop when empty). |
| 0x04 | STATUS | RO | 0x0000_000A | FIFO flags, levels, TX busy. Writing returns `PSLVERR`. |
| 0x08 | CTRL | RW | 0x0000_0003 | Enables, parity, loopback, FIFO clears. |
| 0x0C | BAUD | RW | 0x0000_001A | Baud divisor. |
| 0x10 | INT_EN | RW | 0x0000_0000 | Interrupt enables, one per `INT_STAT` bit. |
| 0x14 | INT_STAT | RO / W1C | 0x0000_0002 | Interrupt status. |
| 0x18 | RX_THR | RW | 0x0000_0001 | RX FIFO level threshold for `RX_THR` interrupt. |

## Fields

### DATA (0x00)
| Bits | Field | Access | Description |
|---|---|---|---|
| 7:0 | DATA | W: TX push, R: RX pop | A write when the TX FIFO is full is dropped and sets `INT_STAT.TX_OVF` (unless the transmitter pops in the same cycle). |
| 31:8 | - | RO 0 | |

### STATUS (0x04)
| Bits | Field | Description |
|---|---|---|
| 0 | TX_FULL | TX FIFO holds `FIFO_DEPTH` bytes |
| 1 | TX_EMPTY | TX FIFO empty (the shifter may still be sending, see TX_BUSY) |
| 2 | RX_FULL | RX FIFO full |
| 3 | RX_EMPTY | RX FIFO empty |
| 4 | TX_BUSY | Transmit shifter is sending a frame |
| 12:8 | TX_LEVEL | TX FIFO occupancy (0..16) |
| 20:16 | RX_LEVEL | RX FIFO occupancy (0..16) |

### CTRL (0x08)
| Bits | Field | Access | Reset | Description |
|---|---|---|---|---|
| 0 | TX_EN | RW | 1 | Transmitter takes bytes from the TX FIFO when set. Clearing it lets the current frame finish. |
| 1 | RX_EN | RW | 1 | Receiver looks for start bits when set. |
| 2 | PAR_EN | RW | 0 | Add/check a parity bit after the data bits (8E1/8O1). |
| 3 | PAR_ODD | RW | 0 | 0 = even parity, 1 = odd parity. |
| 4 | LOOPBACK | RW | 0 | Internal TX -> RX; the `txd` pin idles high. |
| 8 | TX_CLR | W1 (reads 0) | 0 | Flush the TX FIFO. |
| 9 | RX_CLR | W1 (reads 0) | 0 | Flush the RX FIFO. |

### BAUD (0x0C)
| Bits | Field | Description |
|---|---|---|
| 15:0 | DIV | `tick16` every `DIV+1` PCLK cycles; one bit = `16*(DIV+1)` cycles. 50 MHz, DIV = 26 -> 115 741 baud (+0.47 %). A write restarts the divider. DIV >= 1 is recommended so the 2-flop synchronizer delay stays well under the half-bit sampling margin. |

### INT_EN (0x10) and INT_STAT (0x14)
`irq = |(INT_STAT & INT_EN)` (level-sensitive).

| Bit | INT_STAT field | Type | Set when |
|---|---|---|---|
| 0 | RX_THR | RO level | `RX_LEVEL >= RX_THR` |
| 1 | TX_EMPTY | RO level | TX FIFO empty |
| 2 | RX_OVF | W1C sticky | A good frame arrived while the RX FIFO was full (and not being popped); the byte is dropped |
| 3 | FRAME_ERR | W1C sticky | Stop bit sampled low; the byte is discarded |
| 4 | PARITY_ERR | W1C sticky | Parity mismatch with a valid stop bit; the byte is discarded |
| 5 | TX_OVF | W1C sticky | `DATA` write while the TX FIFO was full |

If a sticky event and a W1C write to the same bit happen in the same cycle,
the set wins.

### RX_THR (0x18)
| Bits | Field | Description |
|---|---|---|
| 4:0 | THR | RX interrupt threshold. 0 makes `RX_THR` permanently set. |

## Frame format
Idle high, 1 start bit (0), 8 data bits LSB first, optional parity, 1 stop
bit (1). The receiver synchronizes `rxd` with two flops, starts on a falling
edge, takes a 3-sample majority vote at the 7th/8th/9th tick of each bit,
rejects a start bit that is high at mid-bit, and checks only the middle of the
stop bit before re-arming.
