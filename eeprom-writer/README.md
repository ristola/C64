# EEPROM Writer — 27CXX image to 27SF256

**Status: scaffolding only, no design work started yet.**

## Goal

Load a 27CXX-family ROM binary (e.g. dumped by `../eprom-reader/`, or from any other source) and write it to a 27SF256-series EEPROM/flash chip.

## Chip in scope

**27SF256**: 32KB (256Kbit) 5V in-circuit-programmable flash/EEPROM, sector/chip-erasable, JEDEC 28-pin pinout compatible with the 27C256 socket footprint. Being electrically rewritable (unlike UV-erase 27Cxx parts), it's a much more practical target for iterative development.

## Open questions

- Programming voltage/sequence: confirm the exact software algorithm (unlock sequence, sector erase, byte-program timing) directly from the 27SF256 datasheet before implementing — not assumed or recalled from a similar-sounding part.
- Source image size vs. target size: what happens when a 27C64/27C128 (8KB/16KB) image is written to a 32KB 27SF256 — pad, replicate, or require an exact-size image only?
- Host interface and controller choice: likely shares hardware/tooling with `../eprom-reader/` given the overlapping address/data bus needs — worth deciding whether these two projects share a board design or stay fully separate.

## Relationship to other projects in this workspace

Downstream of `../eprom-reader/` (reads an existing chip) and useful for `../hello/` (the SHACKMATE cartridge project) — e.g. burning a built cartridge image onto a real EEPROM for hardware bring-up before the custom AM29F040B-based board exists, or for socket-based (non-soldered) iteration during Phase 1 hardware bring-up. See also `../programmer-cartridge/` — a separate, later-stage concept for a C64-hosted cartridge that combines this project's write capability with reading, backup, cloning, and in-circuit programming of a companion release cartridge; this project stays a narrower, simpler standalone tool rather than merging into that one.
