# Serial protocol: omni ivwb 2.55 (u3/u4)

This device (a gravimetric blender/feeder - see the message table in
`omni-ivwb-2.55.messages.md`) implements a block-oriented serial protocol
built on the same **ANSI X3.28**-family control codes as the dryer's SPI
CCP implementation (`dryer-fnx-4.20-pct.protocol.md`) - SOH/STX/ETX/ENQ are
explicitly compared against every received byte in the UART receive
interrupt. That much is directly confirmed from the code. Whether this is
literally SPI CCP (same industry standard, different device class) or a
related-but-distinct ANSI X3.28 protocol variant was **not** confirmed -
unlike the dryer, no matching CRC-16 table or DLE-stuffing logic was
found (see "What's different from the dryer's SPI CCP" below), so treat
the "SPI CCP" label for this device as an open hypothesis, not a
verified fact.

## What's confirmed

### Control-code framing (receive side)

Traced directly from the serial ISR at `$789F` (`omni-ivwb-2.55-u3.disassembly.txt`):
every received byte is compared against:

| Byte | Meaning (ANSI X3.28) | Effect on receipt |
|---|---|---|
| `$01` | SOH | `$40=$26`, `$42=1` |
| `$02` | STX | `$40=$18`, `$42=1` |
| `$03` | ETX | `$40=$0C`, `$42=0` |
| `$05` | ENQ | `$40=$04`, `$42=0` |
| (anything else) | data byte | `$40=1`, flag byte at `$880A` set to `$80` |

`$40` looks like a per-control-code byte-count/threshold value (used
later against a running counter at `$41`), and `$42` looks like an
"inside a block" flag. The received byte stream is accumulated into a
buffer starting at `$8808` (pointer pair `$3A:$3B`).

### Main-loop dispatch (once a block/frame is flagged complete)

Gated on flag `$25.5`, set by the ISR above. Code at `$2869` reads the
first buffered byte (`$8808`) and branches:

| First byte | Handler |
|---|---|
| `$01` (SOH) | `LCALL $3D3D` |
| `$02` (STX) | `LCALL $28B9` |
| `$03` or `$05` (ETX/ENQ) | `LCALL $387C` |
| anything else | error path - sets `$841A=5`, queues a ROM-sourced message via `$3AD9` (R5=2,R6=$65,R7=$34 - a 2-byte string/message reference, not decoded further) |

`$28B9` (the STX handler) stashes a buffer descriptor, calls `$39A6`
(a frame-field parser - not traced instruction-by-instruction), and
feeds whatever `$39A6` returns into `$47A2`.

### `$47A2`: range-based dispatch table

Same "pop your own return address to use the caller's inline data as a
table" trick as the dryer firmware's `$0A28` command dispatcher, but
**not** the same table shape - `$47A2` reads TWO pairs of table bytes per
entry via `MOVC` and does signed subtraction against the value in R6:R7,
testing the sign bit (`JB ACC.7,...`) to decide "in range" vs "try next
entry" - i.e. each table entry covers a **[low, high] range** rather than
a single match byte. This is consistent with dispatching on a numeric
field (a CMD or field-ID range) rather than an exact opcode compare, but
the actual table contents (i.e. what ranges map to what handler
addresses, and what they mean) were **not decoded** in this pass - would
need the caller's exact inline table bytes read as data, the same way
the dryer's `$0A28` tables were decoded by hand.

### Candidate ADD/device-address field - confirmed writable, exact role still open

The response-buffer builder (`$3E08`-`$3E4C` in U3) writes a frame
starting with `$02` (STX) directly into the TX buffer at `$882E`, and at
buffer offset 3 writes a byte read from external memory address `$4CE3`.
That address is read in 8 places across U3 and 2 places in U4.

**Correction from an earlier pass**: this was first reported as *never
written anywhere in either ROM* (implying a hardware/DIP-switch-set
value). That was wrong - U4 writes it at `$9858`, alongside three
neighboring fields:

```
$984a  MOV DPTR,#$4CE6 / MOV A,#$01 / MOVX @DPTR,A   ($4CE6 = 1)
$9850  MOV DPTR,#$4CE5 / MOVX @DPTR,A                 ($4CE5 = 1, A unchanged)
$9854  MOV DPTR,#$4CE4 / MOVX @DPTR,A                 ($4CE4 = 1, A unchanged)
$9858  MOV DPTR,#$4CE3 / MOVX @DPTR,A                 ($4CE3 = 1, A unchanged)
```

**Second correction, from tracing this further**: this is *not* a
"save what the user just typed" routine - all four fields are set to
the same fixed immediate (`1`), not to a value derived from the
per-field validation loop above it in the same U4 routine. Tracing the
call site confirms it: U3 calls this exact address (`$984A`) unconditionally
from its startup code (`$012E`-`$0140`, right after writing a `$55 $55
$55 $55` signature to `$8581`-`$8584`) - i.e. this is a **power-on
default initializer** for `$4CE3`-`$4CE6`, not an interactive setup
screen's save handler. The real "enter and validate 4 fields, then do
something" loop earlier in the same U4 function ($96A1-$9778, see
below) evidently drives a *different* piece of state than the
`$4CE3`-`$4CE6` group - which one wasn't pinned down in this pass.

**Still not confirmed**: which external-memory field (if any of
`$4CE3`-`$4CE6`) actually holds the user-editable SPI address, where
its *interactive* setter lives, and how the numbered menu system (the
user's "Menu 54") reaches it. No fixed DEVID immediate (the dryer's
analog was a hardcoded `$22`) was found anywhere

### U3/U4 bank switching - confirmed mechanism

Chasing the above led to a genuinely new, useful finding: **`P1.0` is
the U3/U4 bank-select line**, and U3 contains a real call-out trampoline
to U4 at `$4C5E`-`$4C83`:

```
$4c5e  save B and P1.0's current state
$4c6a  force P1.0 low, then...
$4c70  SETB P1.0                  ; select U4 (0->1 edge, not just a level -
                                   ; suggests an edge-latched bank register)
$4c78  CLR A
$4c79  JMP @A+DPTR                ; jump to the caller-supplied DPTR - now
                                   ; resolved against U4's mapped content
$4c7a  POP ACC                    ; U4 code returns here via "LJMP $4C7A"
$4c7c  restore P1.0 to its saved pre-call state, RET
```

Callers set `DPTR` to the target address *within U4's address space*
and `LCALL $4C5E`; the callee in U4 finishes with `LJMP $4C7A` to
return through the trampoline (confirmed - every U4 handler block found
so far, including the `$984A` initializer above, ends exactly this
way). Seven call sites were found in U3 (`$0140`, `$1B80`, `$1D44`,
`$1D58`, `$3D4F`, `$4ECA`, `$647B`), each loading a different literal
`DPTR` before the call - i.e. seven distinct, fixed entry points into
U4, not a generic numbered-function table. This resolves the "how does
U3 reach U4" open question from the summary/disassembly headers, though
it does **not** by itself explain how a *user-facing menu number* like
54 selects one of these (or some other) U4 entry point - that lookup,
if it exists as a single table, wasn't located.

**Notable: three of the seven targets land in unprogrammed memory.**
Checked all seven DPTR targets directly against `omni ivwb 2.55
u4.bin`'s raw bytes: `$984A` (real code, the initializer above) and
`$A794` and `$A5D1` (both real code - `$A5D1` itself contains another
`LCALL $4C5E`, this time targeting `$D578`, which is also real code -
and notably the very first instructions of U4 itself, at file offset
`$000E`, make this same `$D578` call, marking it as some kind of common
utility invoked from multiple places) land on genuine instructions. But `$4F70`, `$580D`, and `$47E3` (the
latter itself called *from* the `$A794` handler) are **entirely `$FF`
fill** - unprogrammed EPROM space. That means at least three of the
"features" U3 is wired to call into U4 for **are not present in this
specific firmware dump** - either build-time-excluded (a cost-reduced
or OEM variant missing certain options), a partially-erased/incomplete
read, or genuinely dead/future-reserved hooks never populated. This is
a plausible, concrete explanation for why "Menu 54: Communication
Address Setup" hasn't turned up: if it's gated behind one of these
blank entry points, its code simply isn't in this ROM to find,
regardless of how thoroughly it's searched. Not proven either way -
flagged as the most likely explanation given the evidence so far.
in the response-builder code that was traced.

## What's different from the dryer's SPI CCP - and what that means

- **No DLE-stuffing found.** The dryer's protocol prefixes SOH/STX/ETX
  with a `$10` (DLE) byte and doubles any literal `$10` in the data
  stream. Nothing in the U3 receive ISR treats `$10` specially, and the
  outgoing frame built at `$882E` starts directly with `$02` (STX), not
  `$10,$02`. Either this device's protocol variant doesn't use DLE
  transparency, or the DLE handling happens somewhere not traced in this
  pass.
- **No CRC-16 table found.** A byte-exact search (the same technique
  used to confirm the dryer's CRC table) for the standard CRC-16/ARC
  (poly `0xA001`) 256-entry lookup table, in both byte orders, found
  nothing in either ROM. This doesn't rule out CRC-16 computed via a
  shift-and-XOR loop instead of a table (which would leave no fixed
  fingerprint to search for), but it means the dryer's exact
  verification method (byte-for-byte table match) doesn't carry over
  here.
- **The outgoing frame's second byte is `$3D` (ASCII `=`).** That's an
  unusual thing to see right after STX in a binary SPI-CCP-style frame,
  and raises the possibility that `$3E08` builds something other than a
  live wire frame (e.g. a formatted local status string) that just
  happens to share the same buffer/pointer mechanism as actual
  transmissions. This was not resolved - flagged here rather than
  asserted either way.

## Honest summary

Confirmed: this device speaks an ANSI X3.28-derived block protocol with
real SOH/STX/ETX/ENQ control-code handling on receive, has a real
main-loop dispatcher keyed on those same codes, a range-based secondary
dispatch table for whatever comes after STX, and a real U3/U4
bank-switch trampoline (`P1.0`-controlled, `$4C5E` in U3) with seven
known fixed entry points into U4. `$4CE3`-`$4CE6` are a real,
power-on-initialized field group (set to `1` at startup via one of
those seven entry points, `$984A`) that includes our SPI `ADD`
candidate - confirmed writable, which corrects an earlier claim that it
was never written anywhere. Not confirmed: the actual DEVID, which
field in that group (if any) is the `ADD` value specifically, the
CMD/field values and their meanings, the exact outgoing frame format,
how the user's numbered menu system (e.g. "Menu 54: Communication
Address Setup") maps to any of this, and whether this is literally SPI
CCP or a related variant. Further work would mean decoding
`$47A2`'s inline range
table(s) by hand (the same technique already used successfully on the
dryer's `$0A28` tables) and tracing `$39A6`'s field-parsing logic.
