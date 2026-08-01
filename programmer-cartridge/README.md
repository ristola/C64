# Universal Programmer Cartridge

**Status: concept/vision stage, no design work started yet.**

## Goal

A C64 cartridge that programs *other* cartridges — reads, writes, backs up, and clones EPROM/EEPROM/flash chips, with all control software running on the C64 itself. No separate PC or microcontroller toolchain: plug the programmer into the expansion port, boot into a menu, do everything from there.

## Two physical pieces

1. **Barebones cartridge** (the "clone"/release board) — minimal and cheap: a surface-mount (non-socketed) EEPROM/flash chip plus whatever's the bare minimum supporting logic needed to load and play. No ZIF socket, no development features — this is the thing you'd actually ship/distribute once a ROM is finished.
2. **Programmer cartridge** — plugs into the C64 expansion port like any cartridge:
   - A **ZIF socket** for loose DIP EPROM/EEPROM chips, covering the same chip families as `../eprom-reader/` and `../eeprom-writer/` (27C64 through 27C512, 27SF256, etc.)
   - A **second connector**, at the end of the card, for plugging in a barebones cartridge directly — in-circuit programming of its non-socketed chip, no desoldering required
   - **On-board software** (its own ROM): a menu offering Read / Write / Backup / Clone / Load, running entirely on the C64's own 6510 and talking to whichever chip is currently connected (ZIF socket or target socket)

## Why this shape

Using the C64 itself as the programming host means the tooling is just more cartridge software — the same kind of thing already being built in `../hello/` — rather than a second, unrelated toolchain (Arduino/Pi firmware, a PC-side script, a USB driver). One skillset, one codebase style, covers both "run a program" and "program a chip."

## Relationship to `../hello/` (SHACKMATE)

Directly overlaps with `hello/`'s Bank 9 (`FLASHERASE`/`FLASHLOAD`/`FLASHVERIFY`), which was deliberately left stubbed — real flash programming needs a separately-verified erase/write/unlock sequence, not something guessed at alongside everything else (see `hello/docs/ARCHITECTURE.md`). That's the exact same capability this programmer needs, just generalized to chips on the ZIF/target socket instead of only the cartridge's own on-board flash. Worth verifying and implementing the erase/write/verify sequence once, and sharing it between the two projects, rather than deriving it twice.

## Relationship to `../eprom-reader/` and `../eeprom-writer/`

Kept as separate, narrower-scoped projects (dump-to-disk; image-to-27SF256) rather than merged into this one. This project is a different form factor and approach — a C64-hosted cartridge with an on-device menu, not a PC-connected standalone tool — but covers overlapping chip families, so datasheet research (programming voltages, unlock sequences, timing) should be done once and reused across all three rather than re-derived per project.

## Open questions

- **Barebones cartridge addressing**: does it need Magic Desk-style bank switching (74LS273 @ `$DE00`, matching the Phase 0 test board and `hello/`'s existing `build_cart_md.sh` target — see `hello/docs/HARDWARE_PLATFORM.md`), or is "bare essentials to load/play" simple enough to mean a fixed 8K/16K image with no bank switching at all (`cartconv -t normal`)? Depends on whether the shipped ROM content ever exceeds 16K.
- **Target socket interface**: how does the barebones cartridge physically/electrically connect to the programmer's target socket — its own 44-pin C64 edge connector into a card-edge socket on the programmer, or something else?
- **ZIF socket coverage**: one ZIF (28-pin or 32-pin) with adapter jumpering, similar to the Phase 0 test board's `PIN1`/`PIN31`/`28PIN-32PIN` scheme, or something wider?
- **Programming voltage/sequence** per chip family: needs real datasheets, not assumption — same open item already flagged in `../eeprom-writer/README.md`.
- **The programmer's own bootstrap**: does the programmer cartridge itself reuse `hello/`'s existing Magic Desk or EasyFlash bank-switching software (it doesn't need anywhere near 1MB of banks), or is something simpler more appropriate here?
