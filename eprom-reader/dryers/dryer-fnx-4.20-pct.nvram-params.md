# NVRAM factory-default parameters: `dryer-fnx-4.20-pct.bin`

Traced from the real "write NVRAM factory defaults" code path — a magic-number check
at `$49C8`-`$49E3` (tests `$C001==$2A` and `$C000==$02`, an "already initialized"
signature in the M48T02 TIMEKEEPER NVRAM), then a chain of subsystem-init
subroutines called from `$4B4B`-`$4B5A`:

```
$4A05  comm/system config defaults (ADD field, echo buffer, misc) + two of the temp/cam block
$4BA5  23-byte ROM($E278)->NVRAM($C118) copy loop - small values 0-7, NOT parameter data
       (unrelated selector/mode-flag table, ruled out earlier)
$4C70  PID (Electric) + PID (Gas) defaults - $C12F-$C146, confirmed below
$17CF  more comm/timer defaults ($C0AC-$C0BA range)
$42F2  8-entry ROM($DD4B)->NVRAM($C191-$C1A0) copy loop - small values, purpose unclear,
       does NOT match any of the 23 documented parameters
$2CDF  cam duration defaults ($C011-$C014) + calls $2B3E for more timer defaults
$1286  clears $C1A1/$C1A2 - not parameter data
```

Cross-checked against a second firmware dump, `FNX 4.13A NON-PCT.bin` (same 8051 code
base, different model/build, different NVRAM offsets due to a different code layout,
but structurally the same init pattern) — very useful for confirming the *encoding*
even where the PCT binary's own value differs or wasn't found directly.

## PID (Electric) and PID (Gas) — confirmed, `$C12F`-`$C146`

Two identical 12-byte blocks, one per PID channel, written by `$4C70`:

| Offset | Field | Electric (`$C12F`+) | Gas (`$C13B`+) | Doc value | Match? |
|---|---|---|---|---|---|
| 0 | Deadband | `$C12F`=10 | `$C13B`=10 | 10 | Electric ✓ / Gas ✓ |
| 1 | Deriv DivScale | `$C130`=2 | `$C13C`=2 | 2 | ✓ / ✓ |
| 2 | Integ DivScale | `$C131`=60 | `$C13D`=60 | 60 | ✓ / ✓ |
| 3 | Integ RunRate | `$C132`=3 | `$C13E`=3 | Electric 3 / Gas 2 | Electric ✓ / **Gas mismatch (firmware=3, doc=2)** |
| 4 | Integ StoreRate | `$C133`=5 | `$C13F`=5 | Electric 5 / Gas not in photo | Electric ✓ / Gas new info |
| 5 | P Coefficient | `$C134`=12 | `$C140`=12 | Electric 12 / Gas not in photo | Electric ✓ / Gas new info |
| 6 | I Coefficient | `$C135`=1 | `$C141`=1 | Electric 1 / Gas not in photo | Electric ✓ / Gas new info |
| 7 | D Coefficient | `$C136`=0 | `$C142`=0 | Electric 3 / Gas not in photo | **Electric mismatch (firmware=0, doc=3)** |
| 8-9 | unknown (16-bit) | `$C137`/`$C138`=0 | `$C143`/`$C144`=0 | not in photo | new info, both 0 |
| 10-11 | Max \[Heater/Gas\] On Time (16-bit) | `$C139`/`$C13A`=240 | `$C145`/`$C146`=255 (`$00FF`) | Electric 240 (25ms cycles) | Electric ✓ / Gas new info |

Ten clean matches. Two real discrepancies between this firmware build and the printed
table (Electric D-Coeff, Gas IntegRunRate) — not read errors, verified straight from
the immediate-load bytes. Several previously-undocumented Gas-channel values recovered
as a side effect of the block's parallel structure.

## Cam durations

| Param | Doc value | PCT (`dryer-fnx-4.20-pct.bin`) | Non-PCT (`FNX 4.13A NON-PCT.bin`) |
|---|---|---|---|
| Cam 0/50 Duration | 90s | not found at doc value; see note below | `$C009`/`$C00A` = **90** ✓ (exact literal match) |
| Cam 10/60 Duration | 1800s | `$C011`/`$C012` = **1800** ✓ (exact literal match) | `$C00B`/`$C00C` = **1800** ✓ |
| Cam 11/61 Duration | 5400s | `$C013`/`$C014` = **5400** ✓ (exact literal match) | `$C00D`/`$C00E` = **5400** ✓ |
| Cam 20/70 Duration | 1200s | not found at doc value; see note below | `$C00F`/`$C010` = **1200** ✓ |
| Cam 21/71 Duration | 5910s | not found | `$C017`/`$C018` = **5910** ✓ |

The non-PCT binary stores all five cam durations as plain 16-bit big-endian integers,
in seconds, in one consecutive init block (`$26DA`-`$270D`) — a clean, complete,
un-ambiguous confirmation of the encoding (no scaling, no float).

The PCT binary's `$2CDF`/`$2B3E` init chain writes the **same style** of value into
the **same relative part of the NVRAM map** (`$C00F`-`$C023` region, same calling
context as the confirmed `$C011`=1800/`$C013`=5400 pair), but two of the slots that
line up positionally with Cam 0/50 and Cam 20/70 hold different numbers:

- `$C00F`/`$C010` = **240** (position lines up with non-PCT's Cam 0/50 slot, which is 90)
- `$C015`/`$C016` = **120** (position lines up with non-PCT's Cam 20/70 slot, which is 1200)

Read as-is, that would mean **Cam 0/50 Duration = 240s** (up from 90s) and
**Cam 20/70 Duration = 120s** (down from 1200s, a 10x drop) on this PCT build.
This is inferred from relative position in a matching init routine, not from an exact
value match like the other five — flag it as a deduction, not a confirmed fact, before
using it anywhere. Cam 21/71's PCT slot wasn't identified with any confidence; the
nearest candidate (`$C01A`/`$C01B` = 5090) is close to but not equal to 5910 and is
more likely a coincidence than a real match.

## Temperatures — not found

`$C08D`/`$C08E` = 300 exactly matches the *old/generic* PowerCool Cutoff default from
the printed table, and `$C190` = 5 exactly matches Heater Control Delta — but neither
of these is the PCT-specific value you gave (240°F for PowerCool Cutoff). No location
in either binary stores 350, 240 (as a temperature), 200, or 550 as a plain 16-bit
integer or an IEEE-754 float32 constant — checked exhaustively: every `MOV DPTR,#$c0xx`/
`#$c1xx` immediate-write sequence in both full disassemblies, plus a brute-force scan
of every byte offset in both raw binaries for those four values in both integer and
float32 form.

Most likely explanation: these four values are stored as raw ADC/sensor counts (per a
thermocouple or RTD linearization curve) rather than literal degrees Fahrenheit —
consistent with `$C139`/`$C13A`'s own documented unit being "# of 25ms cycles" rather
than plain seconds, i.e. this firmware is not shy about non-literal encodings for
physical-value defaults. Not traced further; would need either a live NVRAM capture
from running hardware, or tracing the runtime comparison code that reads these cells
back and converts them for display, to find the actual scale/offset.
