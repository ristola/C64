# Summary: `omni ivwb 2.55 u3.bin` / `omni ivwb 2.55 u4.bin`

## Source

| Field | Value |
|---|---|
| Device | Unidentified gravimetric blender/feeder controller for plastics processing - confirmed by the on-board message table (recipe/component/fill-rate/calibration terminology), NOT the hot air resin dryer this project started with |
| Firmware version | 2.55 |
| File names | "OMNI IVWB" per the user-supplied file names - exact manufacturer/model not otherwise identified from the ROM content |
| Two-chip set | `u3` = main program (interrupt vectors, UART, UI, serial protocol code); `u4` = second chip, no vector table, hypothesized banked code extension - see omni-ivwb-2.55-u4.disassembly.txt for the evidence |

## Chip identifiers

| Field | Value |
|---|---|
| Package / pinout | Not recorded |
| Electronic ID | Not captured |
| Capacity (from file size) | Both files 64KB. U3's content is a 32KB image mirrored to fill the 64KB file (first and second halves are byte-identical) - real content is 32KB, consistent with a 27C256 read on a 27C512-capable programmer, or a board that only decodes 15 address lines. U4's two halves differ - it uses the full 64KB. |

## Content-derived identifiers

- **U3 used region**: effectively $0000-$7FFF (the real 32KB content; the file's second half is an exact copy)
- **U4 used region**: $0000-$F8FA (~95.7%); remainder is unprogrammed `$FF` fill
- **Architecture**: 8051-family MCU, likely 8052 (Timer 2 interrupt vector present in U3, same evidence class as both dryer dumps)
- **U3 interrupt vector table** (standard 8051/8052 layout, all `LJMP`):

  | Offset | Vector | Handler |
  |---|---|---|
  | `$0000` | Reset | `$002E` |
  | `$0003` | External INT0 | `$799C` |
  | `$000B` | Timer 0 overflow | `$786F` |
  | `$0013` | External INT1 | `$7498` |
  | `$001B` | Timer 1 overflow | `RETI` immediately (unused) |
  | `$0023` | Serial port (UART) | `$789F` |
  | `$002B` | Timer 2 overflow (8052-only) | `$74FE` |

- **First instruction at reset target** (`$002E`): `75 81 43` = `MOV SP,#$43` (dryer firmware used `#$5F` - different RAM layout, as expected for unrelated hardware)
- **U4 has no vector table** at all - its first bytes are already application logic (`MOV DPTR,#$4CEA` / `MOVX A,@DPTR` / conditional branch), meaning it is not itself directly reset-executed; see the "Relationship between U3 and U4" section below.

## Peripherals identified from the code

- **Serial/UART**: real 8051 hardware UART, initialized at `$0086` in U3 (`SCON=$50`, mode 1, 8-bit, REN=1 receive enabled; `TH1=TL1=$E8` baud-rate constant; `TMOD=$21`). `P3.3`/`P3.4` are set shortly after init - plausible RS-485 driver-enable lines by analogy with the dryer's `P3.5` usage, not confirmed against a schematic.
- **Serial protocol**: ANSI X3.28-family block protocol (SOH/STX/ETX/ENQ control codes explicitly handled) - see `omni-ivwb-2.55.protocol.md` for the full writeup, including what could and couldn't be confirmed relative to the dryer's SPI CCP implementation.
- **NVRAM/external config**: external memory address `$4CE3`, read in multiple places across both ROMs and confirmed writable - U4's `$984A` sets it and three neighbors (`$4CE4`-`$4CE6`) to `1` as a power-on default, called unconditionally from U3's startup code. Likely related to the dryer's `$C0CB` (SPI CCP `ADD` field) role, and the user has confirmed a real "Menu 54: Communication Address Setup" exists on this hardware, but the exact link between that menu and this field group is not yet traced - see `omni-ivwb-2.55.protocol.md` for the full history of what was confirmed vs. corrected while chasing this.
- **Keypad/display**: not traced in this pass - no shift-register/bit-serial keypad code was specifically looked for or found; the 130-entry message table (see below) confirms there's a text display, but the input/output driving code wasn't identified.

## Relationship between U3 and U4 - bank switching confirmed

U4 decodes as plausible, real 8051 code but is never reached from U3's
reset vector or interrupt table. **The bank-switch mechanism has now
been located**: `P1.0` is the bank-select line, and U3 contains a
call-out trampoline at `$4C5E`-`$4C83` (save state, force `P1.0` low
then high to select U4, jump to a caller-supplied `DPTR` now resolved
against U4's mapped content, and land back at `$4C7A` when the U4 code
finishes with `LJMP $4C7A`, which restores `P1.0` and returns). Seven
call sites in U3 use this trampoline (`$0140`, `$1B80`, `$1D44`,
`$1D58`, `$3D4F`, `$4ECA`, `$647B`), each with a different fixed
literal `DPTR` - seven distinct, hardcoded entry points into U4, not a
generic numbered-function table. See `omni-ivwb-2.55.protocol.md` for
the full trace and the corrected/superseded interpretation of the
`$4CE3`-`$4CE6` field group found via one of these entry points.

Not yet done: annotating U4's internal routine structure beyond these
seven known entry points, and finding how (or whether) a user-facing
numbered menu selects among them or among further, not-yet-found entry
points.

## Display messages

[`omni-ivwb-2.55.messages.md`](omni-ivwb-2.55.messages.md) - 130-entry
display-message table in U3 (`$6AE2`-`$7406`, 18 bytes/entry: 16-char
text + a 2-byte trailer). This is what identifies the device as a
gravimetric blender/feeder (`FILL-LBS`, `RATES IN LBS/HR`, `SELECT
COMPONENT`, `CALIBRATE`, `MIXER TIME`, `RECIPE RECALLED`, etc.) rather
than the dryer this project otherwise focuses on.

## Serial protocol

[`omni-ivwb-2.55.protocol.md`](omni-ivwb-2.55.protocol.md) - the
ANSI X3.28-family control-code framing confirmed in the UART ISR and
main-loop dispatcher, the range-based secondary command-dispatch table
at `$47A2`, and an honest list of what differs from (and couldn't be
confirmed against) the dryer's SPI CCP implementation - notably no DLE-
stuffing and no matching CRC-16 table were found.

## Full disassembly

- [`omni-ivwb-2.55-u3.disassembly.txt`](omni-ivwb-2.55-u3.disassembly.txt) - `$0000`-`$7FFF` linear-sweep 8051/8052 disassembly with the vector table, UART init, serial ISR, main dispatch, and message table annotated inline.
- [`omni-ivwb-2.55-u4.disassembly.txt`](omni-ivwb-2.55-u4.disassembly.txt) - `$0000`-`$F8FA` linear-sweep disassembly, unannotated beyond the header notes (no confirmed subsystem boundaries traced in this pass).

Same method and limitations as every other disassembly in this project
(misdecodes embedded data - most notably the message table - as bogus
instructions).

## Format notes

Follows the same Source / Chip identifiers / Content-derived identifiers
structure as the other summaries in this project, with an added
"Relationship between U3 and U4" section specific to this being a
two-chip dump.
