# Summary: `FNX 4.13A NON-PCT.bin`

## Source

| Field | Value |
|---|---|
| Device | Same product family/hardware as `dryer-fnx-4.20-pct.bin`, a different model/build - "NON-PCT" per the file's own name, i.e. not the Model PCT hot air resin dryer the other dump is from. Exact model not otherwise identified. |
| Firmware version | 4.13A |
| Role in this project | Comparison reference, supplied by the user specifically to help decode which factory-default parameters differ on the PCT build - see [`dryer-fnx-4.20-pct.nvram-params.md`](../dryer-fnx-4.20-pct.nvram-params.md) |

## Chip identifiers

| Field | Value |
|---|---|
| Package / pinout | Not recorded |
| Electronic ID | Not captured |
| Capacity (from file size) | 64KB - consistent with a 27C512 |

## Content-derived identifiers

- **File size**: 65536 bytes (64KB)
- **Used region**: `$0000`-`$EDFD` (60925 bytes, 93.0%); remainder is unprogrammed `$FF` fill
- **Architecture**: 8051-family MCU, likely 8052 (Timer 2 interrupt vector present, same as the PCT build)
- **Interrupt vector table**: byte-for-byte identical to `dryer-fnx-4.20-pct.bin` - same 7 vectors, same handler targets:

  | Offset | Vector | Handler |
  |---|---|---|
  | `$0000` | Reset | `$002E` |
  | `$0003` | External INT0 | `$0199` |
  | `$000B` | Timer 0 overflow | `$0287` |
  | `$0013` | External INT1 | `$0273` |
  | `$001B` | Timer 1 overflow | `$002E` (unused) |
  | `$0023` | Serial port (UART) | `$013B` |
  | `$002B` | Timer 2 overflow (8052-only) | `$0353` |

- **First instruction at reset target** (`$002E`): `75 81 5f` = `MOV SP,#$5F` - same as PCT

## Relationship to the PCT build

Directly diffed both full disassemblies. Findings:

- **Byte-for-byte identical at the same addresses**: the entire interrupt vector table, the reset/startup code shape (differs only in a couple of RAM-clear boundary pointer constants - `$A765`/`$A43C` here vs `$A776`/`$A481` in the PCT build), the serial-interrupt TI/RI handling at `$0148`, and the entire External INT0 keypad bit-serial shift-register handler (`$0199`-`~$0268`, P1.5 data-in/P1.6 clock/P1.7 data-out). This is shared low-level runtime code, unchanged between builds.
- **Different addresses, same structure**: UART init (`$4360` here vs `~$450F` in PCT - `CLR P3.5` then `SCON=$50`), NVRAM TIMEKEEPER read (`$56E4` here vs `$5728` in PCT), NVRAM TIMEKEEPER write/reset (`$576F` here vs `$57B0` in PCT). Same M48T02-70 chip, same `$C000` base, same `$C7F8`-`$C7FF` control registers, same READ/WRITE bit semantics - just recompiled at different addresses because the surrounding application code differs in size/layout.
- **Substantially different content**: everything past the shared low-level layer (NVRAM factory-default values, the display message table's base address and entry count, the cam-duration/PID-parameter defaults) - see [`dryer-fnx-4.20-pct.nvram-params.md`](../dryer-fnx-4.20-pct.nvram-params.md) for the specific factory-default comparison this build was used for.
- **Not re-verified for this build**: the SPI CCP protocol frame-builder (`$65B6`/`$65FB`/etc. in the PCT build) - a search for the PCT build's `DEVID=$22` immediate load found no match here, suggesting either a different DEVID for this device type or a relocated/restructured protocol handler. Not traced further; no `fnx-4.13a-non-pct.protocol.md` was written as a result.

## Peripherals identified from the code

- **Serial/UART**: real 8051 hardware UART, initialized at `$4362` (`SCON=$50`, mode 1, 8-bit, receive enabled) - part of a combined UART/timer init routine starting at `$4360`.
- **Keypad/button panel**: identical code to the PCT build, see above - `$0199` (INT0 dispatch) and `$01ED` (bit-serial shift-in), assembled byte lands in `$40`.
- **NVRAM**: M48T02-70 TIMEKEEPER, same as PCT. Read routine at `$56E4`, write/reset routine at `$576F`, plus a read-stability-check pair at `$57B2` (not traced in full, mirrors the PCT build's `$57F6`/`$5827`).

## Display messages

[`fnx-4.13a-non-pct.messages.md`](fnx-4.13a-non-pct.messages.md) - 191-entry display-message table (`$DFAC`-`$E662`), same 9-bytes/entry structure as the PCT build's table, located independently via known UI strings (`SETPOINT`, `DEWPOINT`) rather than copied from the PCT table's address. Not yet cross-referenced against its own lookup call sites in the code (the PCT table's `messages.md` includes that level of detail; this one is the raw catalog only).

## Full disassembly

[`fnx-4.13a-non-pct.disassembly.txt`](fnx-4.13a-non-pct.disassembly.txt) - `$0000`-`$EDFD` linear-sweep 8051/8052 disassembly, with the shared low-level routines (vectors, reset, keypad, serial-ISR) and this build's own NVRAM/UART/message-table routines annotated inline. Same method and same limitations as the PCT disassembly (misdecodes embedded data as bogus instructions - most notably the message table region).

## Format notes

Follows the same Source / Chip identifiers / Content-derived identifiers structure as `dryer-fnx-4.20-pct.summary.md`, plus an added "Relationship to the PCT build" section specific to this being a comparison dump rather than a first-of-its-kind find.
