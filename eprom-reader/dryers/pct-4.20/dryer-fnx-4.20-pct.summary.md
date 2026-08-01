# Summary: `dryer-fnx-4.20-pct.bin`

## Source

| Field | Value |
|---|---|
| Device | Commercial dryer control board, Model PCT — **a hot air resin dryer** (industrial plastics-processing equipment: lowers moisture in plastic resin pellets using a desiccant bed and hot air circulation, monitored via dewpoint), confirmed directly by the user — not a clothes/laundry dryer |
| Firmware version | 4.20 |
| Date noted | 2026-07-31 |

The serial protocol captured directly from the board (see `dryer-fnx-4.20-pct.protocol.md`) and the full display-message table (see `dryer-fnx-4.20-pct.messages.md` — `SETPOINT`, `DEWPOINT`, `HOPR LVL`, `REGENHTR`/`REGENOUT`, `PROCFLTR`/`RGN FLTR`, `GASONOFF`, etc.) both independently confirm this equipment class.

## Chip identifiers

| Field | Value |
|---|---|
| Package / pinout | Not recorded at read time |
| Electronic ID (manufacturer/device bytes) | Not captured — the commercial programmer used for this read wasn't queried for it |
| Capacity (from file size) | 64KB — consistent with a 27C512 (28-pin, A0-A15) |

Real EPROM ID-mode support (raising A9 to `Vpp` and reading manufacturer/device bytes at A0=0/1) is **not universal on plain UV-erase 27Cxx parts** — it varies by manufacturer and part, and has to be confirmed per datasheet rather than assumed. Worth checking whether this specific chip supports it next time it's in a programmer that can query it.

## Content-derived identifiers

- **File size**: 65536 bytes (64KB)
- **Used region**: `$0000`-`$F28B` (62091 bytes, 94.7%); remainder is unprogrammed `$FF` fill
- **Architecture**: 8051-family MCU — likely an **8052** variant specifically, based on the Timer 2 interrupt vector (an 8052-only addition over base 8051)
- **Interrupt vector table** (all standard 8051/8052 vectors present, each a 3-byte `LJMP`):

  | Offset | Vector | Handler |
  |---|---|---|
  | `$0000` | Reset | `$002E` |
  | `$0003` | External INT0 | `$0199` |
  | `$000B` | Timer 0 overflow | `$0287` |
  | `$0013` | External INT1 | `$0273` |
  | `$001B` | Timer 1 overflow | `$002E` (unused — falls back to reset/main) |
  | `$0023` | Serial port (UART) | `$013B` |
  | `$002B` | Timer 2 overflow (8052-only) | `$0353` |

- **First instruction at the reset target** (`$002E`): `75 81 5F` = `MOV SP,#$5F` — the classic first instruction of 8051 startup code (`$81` is the SP special-function-register address)
- **Instruction mix**: heavy `LCALL`/`LJMP` and `MOVX` (external memory read/write — `0xE0`/`0xF0` among the most common bytes), consistent with a control board reading sensors/keypad and driving relays/a display through memory-mapped I/O
- **Embedded text strings**: correction — an earlier pass here said none were found, but that check was truncated (`head -60` on a `strings` scan of the whole file) and missed a full 193-entry, 9-bytes/entry display-message table at `$E460`-`$EB28`. See `dryer-fnx-4.20-pct.messages.md` for the complete catalog.

## Peripherals identified from the code (not just the chip)

Traced from actual code behavior, not inferred from the board alone:

- **Serial/UART**: real 8051 hardware UART, initialized at `$450F` (`SCON=$50`, mode 1, 8-bit, receive enabled), TX/RX primitives at `$645F`-`$64C9`. `P3.5` is toggled around transmission — likely an RS-485 driver-enable line, common for multi-board appliance networks.
- **Keypad/button panel**: read via the External INT0 handler (`$0199`) as a bit-serial shift register — `P1.5` data-in, `P1.6` clock strobe, `P1.7` data-out (for a daisy-chained second shift-register chip). Assembled byte lands in `$40`.
- **NVRAM**: an **M48T02-70 TIMEKEEPER** (battery-backed 2KB parallel NVRAM + real-time clock in one chip) — chip identity supplied directly from the real datasheet, then confirmed in the code: mapped at base `$C000`, control+clock registers at `$C7F8`-`$C7FF` exactly matching the datasheet's `7F8`-`7FF` layout. Read routine at `$5728` (sets the READ bit, reads hours/minutes, clears it); write/reset routine at `$57B0` (sets the WRITE bit, writes hours/minutes plus a zeroed date, clears it) — bit semantics match the datasheet's "seventh bit"/"eighth bit" wording exactly (0-indexed: bit 6 = READ, bit 7 = WRITE). Two more related routines at `$57F6`/`$5827` look like a read-twice-and-compare stability check but weren't traced in full.
- **Separately**, `$A000`-`$A7FF` looked like it could be the same NVRAM at first (same size, similar base) but is confirmed volatile — the startup code unconditionally zeroes it (`$00A9` and `$0037`) on every reset. A different, ordinary external RAM chip.

## Serial protocol (SPI CCP)

[`dryer-fnx-4.20-pct.protocol.md`](dryer-fnx-4.20-pct.protocol.md) — the real, published SPI CCP V4.00 industrial protocol (Society of the Plastics Industry). Full frame format (poll/write, DLE framing), the `CMD2` command table with decoded IEEE-754 float values across two command zones (`CMD1=$20` main zone, `CMD1=$ED` a second zone), and the CRC-16 algorithm verified byte-exact against 4 independent live captures. Also documents the confirmed firmware code that builds these frames (`$65B6` header builder, `$0A28` command dispatch).

## Display messages

[`dryer-fnx-4.20-pct.messages.md`](dryer-fnx-4.20-pct.messages.md) — the complete 193-entry display-message table (`$E460`-`$EB28`), covering the full menu/UI system: setpoints, config, diagnostics, alarm/fault names, I/O labels.

## Full disassembly

[`dryer-fnx-4.20-pct.disassembly.txt`](dryer-fnx-4.20-pct.disassembly.txt) — the complete `$0000`-`$F28B` used region, linear-sweep 8051/8052 disassembly (35,499 lines), with the NVRAM/serial/keypad/SPI-CCP/message-table routines above annotated inline. See the file's own header for the linear-sweep method's limitations (it will misdecode embedded data - lookup tables, the message table, other binary tables - as bogus instructions wherever they occur, since it doesn't trace real code flow).

## Format notes for future dumps

This file's structure (Source / Chip identifiers / Content-derived identifiers) is the template for future dump summaries — see `README.md`'s "Reference dumps" section for the running list.
