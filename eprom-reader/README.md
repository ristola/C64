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

## Relationship to other projects in this workspace

Complements `../eeprom-writer/` (which goes the other direction: takes a dumped ROM image and writes it to a rewritable EEPROM) and `../hello/` (the SHACKMATE cartridge project) — useful for archiving/dumping existing EPROM-based cartridges or ROMs before they're replaced or rewritten.
