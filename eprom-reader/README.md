# EPROM Reader — 27C64 to 27C512

**Status: scaffolding only, no design work started yet.**

## Goal

Read the contents of parallel UV/OTP EPROMs in the 27C64 (8KB) through 27C512 (64KB) family and store the dump to disk on a host computer.

## Chips in scope

| Part | Capacity | Address lines |
|---|---|---|
| 27C64 | 8 KB | A0-A12 |
| 27C128 | 16 KB | A0-A13 |
| 27C256 | 32 KB | A0-A14 |
| 27C512 | 64 KB | A0-A15 |

These are pin-compatible within the family (same JEDEC-standard 28-pin layout, differing mainly in how many address lines are used and where `Vpp`/`PGM` fall on the higher-capacity parts) — worth confirming exact pinout differences per part before finalizing a socket/ZIF design that's meant to cover the whole range.

## Open questions

- Host interface: USB-serial to a PC script, direct to SD card, or something else?
- Controller: microcontroller choice not yet decided (needs enough GPIO for a 16-bit address bus + 8-bit data bus + control lines, or a shift-register/latch-based address multiplexing scheme to reduce pin count).
- Read timing/access requirements per part (pull from datasheets, not assumed).

## Planned feature: chip identification + summary on every read

Every read should produce two things, not just a raw `.bin`: the chip's own **electronic ID** where the chip supports it (manufacturer/device bytes, read by raising `A9` to `Vpp` with `A0=0`/`1` — **not universal on plain UV-erase 27Cxx parts**, needs per-datasheet confirmation, not assumed), and a **content-derived summary** — used-vs-`$FF` fill boundary, detected MCU architecture from the reset-vector pattern, the interrupt vector table if one is recognizable, instruction-mix fingerprint, and any other identifying characteristics found along the way. The goal is a running, growing set of identifiers that make it possible to tell dumps apart and recognize a chip/architecture again later, not just a byte-for-byte image.

[`dryer-fnx-4.20-pct.summary.md`](dryers/pct-4.20/dryer-fnx-4.20-pct.summary.md) (see below) is the first example of this, written by hand as a template for what the reader should eventually generate automatically.

## Reference dumps

| File | Summary | Source | Firmware | Size | How obtained |
|---|---|---|---|---|---|
| `dryer-fnx-4.20-pct.bin` | [`dryer-fnx-4.20-pct.summary.md`](dryers/pct-4.20/dryer-fnx-4.20-pct.summary.md) · [disassembly](dryers/pct-4.20/dryer-fnx-4.20-pct.disassembly.txt) · [protocol](dryers/pct-4.20/dryer-fnx-4.20-pct.protocol.md) · [messages](dryers/pct-4.20/dryer-fnx-4.20-pct.messages.md) · [NVRAM params](dryers/dryer-fnx-4.20-pct.nvram-params.md) | Hot air resin dryer control board, Model PCT (industrial plastics-processing equipment, not a laundry dryer — see summary) | v4.20 | 64KB (27C512) | Read with a commercial EPROM programmer (not this project's own reader, which doesn't exist yet) |
| `FNX 4.13A NON-PCT.bin` | [`fnx-4.13a-non-pct.summary.md`](dryers/non-pct-4.13a/fnx-4.13a-non-pct.summary.md) · [disassembly](dryers/non-pct-4.13a/fnx-4.13a-non-pct.disassembly.txt) · [messages](dryers/non-pct-4.13a/fnx-4.13a-non-pct.messages.md) — also see [NVRAM params](dryers/dryer-fnx-4.20-pct.nvram-params.md) for the cross-model comparison this dump was used for | Same product family, non-PCT model/build | v4.13A | 64KB (27C512) | Same as above |
| `omni ivwb 2.55 u3.bin` + `u4.bin` | [`omni-ivwb-2.55.summary.md`](blender/omni-ivwb-2.55.summary.md) · [disassembly u3](blender/omni-ivwb-2.55-u3.disassembly.txt) · [disassembly u4](blender/omni-ivwb-2.55-u4.disassembly.txt) · [protocol](blender/omni-ivwb-2.55.protocol.md) · [messages](blender/omni-ivwb-2.55.messages.md) | Unidentified gravimetric blender/feeder for plastics processing (not the dryer — different product entirely, see summary) | 2.55 | 64KB each (27C512; u3's real content is 32KB, mirrored) | Same as above |

Not C64-related — kept here as a known-good reference dump: real firmware data (8051-family MCU, confirmed via a textbook interrupt vector table and stack-init instruction — see the summary file), obtained from hardware known to work. Once this project's own reader exists, dumping the same chip and diffing against this file is a cheap way to confirm the reader is accurate, without needing a second known-good source.

## Relationship to other projects in this workspace

Complements `../eeprom-writer/` (which goes the other direction: takes a dumped ROM image and writes it to a rewritable EEPROM) and `../hello/` (the SHACKMATE cartridge project) — useful for archiving/dumping existing EPROM-based cartridges or ROMs before they're replaced or rewritten. See also `../programmer-cartridge/` — a separate, later-stage concept for a C64-hosted cartridge that combines read/write/backup/clone into one device via a ZIF socket; this project stays a narrower, simpler standalone tool rather than merging into that one.
