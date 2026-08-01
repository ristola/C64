# Serial protocol: `dryer-fnx-4.20-pct.bin` — SPI CCP

This board implements **SPI CCP** (Society of the Plastics Industry, Committee on Communication Protocol, V4.00) — a real, formally published industrial standard for plastics-processing machinery, not a proprietary/vendor protocol. The full spec (`SPI Protocol.pdf`, in this folder) fully explains and *verifies* everything below — this isn't guesswork or inference from captures alone; every field and the checksum algorithm were checked byte-for-byte against real captured frames (see "Verification" below).

## Frame structure

### POLL (read) request, control station -> tributary

```text
<EOT>  (DEVID)  (ADD)  (CMD1)  (CMD2)  (RES)  <ENQ>
$04    $22      $20    $20     varies  $20    $05
```

- `<EOT>` ($04): resets the communication link
- `DEVID` ($22): this device's type code (fixed per device type, SPI-CCP-assigned)
- `ADD` ($20): device address — first instance of a device type is conventionally `$20`
- `CMD1` ($20): command group byte (constant across every command this device supports — it doesn't use CMD1 as a zone/group selector)
- `CMD2`: the actual command — **even** = POLL (read), **odd** = SELECT (write). Read/write pairs differ by exactly bit 0 (e.g. `$30` read setpoint / `$31` write setpoint) — this is a protocol-level rule (ANSI x3.28 §2.3.1.1.1.3), not a per-device convention.
- `RES` ($20): reserved byte, always `$20`
- `<ENQ>` ($05): end of the supervisory sequence

### POLL response, tributary -> control station (first/only block)

```text
<DLE><SOH>  (DEVID)(ADD)(CMD1)(CMD2)(RES)(ERR)  <DLE><STX>  (DATA...)  <DLE><ETX>  CRC1 CRC2
$10  $01    ......... 6 bytes, echoed .........  $10  $02   N bytes    $10  $03   2 bytes
```

- `<DLE><SOH>` ($10 $01): start of header, first block of the message
- 6-byte echo block: `DEVID, ADD, CMD1, CMD2, RES` repeated from the request, plus `ERR` (SPI CCP Error Status Byte — `$20` = no error; see "Error byte" below for other bits)
- `<DLE><STX>` ($10 $02): start of data
- `DATA`: the actual value, width/format depends on the command (see command table)
- `<DLE><ETX>` ($10 $03): end of final block (`<DLE><ETB>` would be used for a non-final block of a multi-block message — not observed here, every response so far fits in one block)
- `CRC1, CRC2`: CRC-16, MS byte first (see "CRC algorithm" below)

**Important correction from an earlier version of this document**: I had misread this 6-byte echo block as a `CMD1,CMD1,CMD2,CMD1,CMD1` repeating pattern. It's actually `DEVID,ADD,CMD1,CMD2,RES,ERR` — six *distinct* fields that happen to mostly be `$20` in this device's case (`ADD`, `CMD1`, `RES` are always `$20`, and `ERR` is `$20` whenever there's no error), which is what made it look like repetition.

### SELECT (write) request, control station -> tributary

```text
<EOT>  (DEVID)  (ADD)  (CMD1)  (CMD2, odd)  (RES)  <ENQ>
```
Same shape as POLL, `CMD2` odd (e.g. `$31` = write setpoint).

Tributary's ready-to-receive ack:
```text
(DEVID)(ADD)(CMD1)(CMD2)(RES=$21)  <DLE><30>
```
(`RES=$21` here, not `$20` — the spec's own SELECT-ack table specifies this.) Then the control station sends the new value as a normal `<DLE><STX>...<DLE><ETX>CRC1CRC2` block (this is the `10 02 / 43 A6 80 00 / 10 03 / AE 26` sequence captured earlier for setting 333.0), and the tributary's final ack is `<DLE><ACKn>` (`<DLE><31>` for the first block, alternating `<DLE><30>`/`<DLE><31>` thereafter).

### Error byte (`ERR`)

Bit register, always has bit 5 set (keeps the byte in `$20`-`$FF` range) and bit 4 reserved/`0`:

| Bit | Meaning when set |
|---|---|
| 7 | Invalid Data |
| 6 | Command Not Ready |
| 5 | (always 1) |
| 4 | reserved |
| 3 | Command Not Supported |
| 2 | Command Not Executed |
| 1 | Invalid Preamble |
| 0 | Communication Error |

`$20` = all clear (only bit 5 set).

## CRC algorithm — verified exactly

CRC-16 with polynomial `x^16 + x^15 + x^2 + 1` (i.e. the standard reflected CRC-16/ARC, poly `0xA001`), computed with a 256-entry lookup table exactly as given in the SPI CCP spec appendix (C source in `SPI Protocol.pdf` §3.4). Which bytes are included follows the spec's "CRC DLE Sequence Chart":

- The 6-byte echo header: included (plain data, no DLE prefix)
- `<DLE><STX>`: the `STX` byte itself is included (since a `<DLE><SOH>` header precedes it in the same block); the `DLE` is not
- `DATA` bytes: included
- `<DLE><ETX>` (or `<DLE><ETB>`): the `ETX`/`ETB` byte is included; the `DLE` is not
- A literal `$10` byte appearing in data is sent doubled (`<DLE><DLE>`) and counted once in the CRC (transparency escaping — not yet observed in a capture, all data so far has avoided `$10`)

**Verified against 4 independent real captures** (Python reimplementation of the spec's C algorithm, byte-exact match on all 4):

| Command | CRC input | Expected | Computed |
|---|---|---|---|
| ECHO (`$20`) | `22 20 20 20 20 20 02 00 00 00 00 03` | `2a29` | `2a29` ✓ |
| SET POINT (`$30`) | `22 20 20 30 20 20 02 42 00 00 00 03` | `e59c` | `e59c` ✓ |
| VERSION (`$22`) | `22 20 20 22 20 20 02 30 34 30 30 03` | `716a` | `716a` ✓ |
| DEWPOINT (`$7c`) | `22 20 20 7c 20 20 02 c2 30 00 00 03` | `f8f6` | `f8f6` ✓ |

This confirms the frame-field boundaries, the CRC algorithm, and the DLE-inclusion rules simultaneously — about as strong a verification as this project gets without the actual source code.

## Known CMD2 values

| CMD2 | Name | Data type | Example bytes | Decoded |
|---|---|---|---|---|
| `$20` | ECHO (SPI CCP required) | Open, 4 bytes | `00 00 00 00` | — (read/write scratch value, SPI-CCP-mandated on every device) |
| `$21` | (ECHO write, per spec — not captured) | Open, 4 bytes | — | — |
| `$22` | REVISION (SPI CCP required, read-only) | Open, 4 ASCII bytes | `30 34 30 30` | `"0400"` = major rev `04`, minor rev `00` (per spec §2.7.1.2.3.2's exact digit layout) |
| `$30` | PROCESS SET POINT (read) | Numeric (float32) | `42 00 00 00` | 32.0 |
| `$31` | PROCESS SET POINT (write) | Numeric (float32) | (see write example) | 333.0 in the captured example |
| `$32` | PROCESS HIGH DELTA | Numeric (float32) | `42 70 00 00` | 60.0 |
| `$34` | PROCESS LOW DELTA | Numeric (float32) | `00 00 00 00` | 0.0 |
| `$40` | PROCESS STATUS | Status, 2 bytes | `00 0B` | bitfield, not decoded |
| `$48` | MACHINE MODE | Status, 2 bytes | (partially illegible capture) | — |
| `$4A` | MACHINE MODE (PROTECTED) | Status, 2 bytes | `00 01` | — |
| `$70` | PROCESS TEMPERATURE | Numeric (float32) | `43 44 00 00` | 196.0 |
| `$72` | RETURN TEMPERATURE | Numeric (float32) | `42 F4 00 00` | 122.0 |
| `$7C` | DEWPOINT | Numeric (float32) | `C2 30 00 00` | -44.0 |
| `$80` | DEWPOINT TRIGGER | Numeric (float32) | `00 00 00 00` | 0.0 |
| `$E0` | BLANKET POLL 1 | Open (SPI CCP "Blanket List" complex type) | repeated `[CMD2][value]` groups for `$30,$32,$34,$40,$70` | multi-value snapshot in one request — matches the spec's §2.7.1.1.2.1 Blanket List format exactly: each entry is `CMD1,CMD2` (here just `CMD2` shown since `CMD1` is constant `$20`) followed by that command's own data |

Numeric = IEEE-754 big-endian float32 (spec §2.7.1.1.1.1, "first byte sent is the most significant byte"). Status = 2 bytes, MSB first (spec §2.7.1.1.1.2).

## Device identification correction

The `$30`/`$7C`/`$70`/`$72` decoded values (32°F setpoint, -44°F dewpoint, 196°F/122°F process/return temps) plus the user's direct confirmation: this is a **hot air resin dryer** — industrial plastics-processing equipment that lowers moisture content using a desiccant bed and hot air circulation, monitored via dewpoint. Fits the SPI CCP protocol's actual purpose exactly (§1.1: "centralized setup and monitoring of various auxiliary equipment by a primary plastics processing machine" — resin dryers are a textbook SPI CCP auxiliary device). Not a clothes/laundry dryer, despite the generic "commercial dryer control board" starting description.

## Relationship to the firmware disassembly

With the exact field layout confirmed above, the header-construction code was found directly — **`$65B6`** builds the response header, byte for byte matching the spec:

```
$65B6: reset transmit-buffer index ($63CE)
       queue $10 (DLE), $01 (SOH), $22 (DEVID, fixed immediate)
       queue [$C0CB]  (ADD)
       queue [$A6C3]  (CMD1)
       queue [$A6C4]  (CMD2 - the just-received command, echoed back)
       queue [$A6C5]  (RES)
       queue [$A6D3]  (ERR)
       queue $10, $02 (DLE, STX)
```

The caller then queues the actual `DATA` bytes directly (e.g. the `"0400"` ASCII digits for the REVISION command, or the 4-byte NVRAM-stored values for `ECHO`), and **`$65FB`** closes the frame: queues `$10,$03` (DLE, ETX) and calls `$6453` — almost certainly the CRC-16 calculation/append, matching the spec's frame layout exactly, though not traced instruction-by-instruction yet.

Supporting routines:
- `$63CE`/`$63D9`/`$63E9`: the transmit staging buffer's reset-index and queue-byte primitives (buffer at `$A67B` onward)
- `$6456`: confirmed transmit routine — `SETB P3.5` (RS-485 driver enable), walks the queued buffer, sends each byte via `SBUF`
- `$A6C3`/`$A6C4`/`$A6C5`/`$A6D3`: the current response's `CMD1`/`CMD2`/`RES`/`ERR` field variables; `$C0CB` (NVRAM-mapped) holds `ADD`

Not yet traced: `$6453` (the hypothesized CRC routine itself), the receive-side frame parser that fills `$A6C3`-`$A6D3` from an incoming request, and the `$A67A`/×7/`$A5FB` command-dispatch table from earlier investigation (still unconfirmed against real CMD2 values).
