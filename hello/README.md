# SHACKMATE — C64 BASIC+ Extension Cartridge / Expansion Platform

Part of the [C64 development workspace](../README.md). Two parts, documented in `docs/`:

1. **Working software**: a 13-bank EasyFlash BASIC+ extension cartridge, built and tested in VICE. See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).
2. **Planned hardware**: a from-scratch custom cartridge PCB ("C64 Expansion Platform") that supersedes the EasyFlash build as the shipping target. See [`docs/HARDWARE_PLATFORM.md`](docs/HARDWARE_PLATFORM.md).

`../EasyFlash-AppSupport.pdf` / `../EasyFlash-ProgRef.pdf` are the real EasyFlash reference docs, kept in the workspace root for cross-checking hardware facts (GAME/EXROM behavior, register semantics) against something authoritative rather than recalled knowledge.

## Status at a glance

### Software (EasyFlash build) — done

- Cartridge boot flow (Ultimax → own KERNAL-equivalent init → 8K mode → `JMP ($A000)` into real `READY.`)
- F1 hotkey menu, reentrant against BASIC's own jiffy IRQ
- 13-bank cross-bank call mechanism (fixed-slot jump table, RAM-resident bank-switch trampoline)
- BASIC+ tokenizer/detokenizer/dispatcher (`EXTTOK`/`EXTFUNCTOK` 2-byte extended tokens)
- Bank 6 (CARTRIDGE non-flash: `CARTINFO`/`BANK`/`BANKS`) — real
- Bank 10 (DISK: `DIR`/`DEVICE`/`CD`/`DELETE`/`RENAME`/`DLOAD`/`DSAVE`) — real, KERNAL-verified live in VICE
- Bank 5's `HEX$`/`DEC$` — real string-returning BASIC functions (verified against BASIC ROM's own `CHR$` string-descriptor convention)
- Graphics demo, SID demo, sprite editor, joystick tester, CIA/VIC/memory hex-dump viewers (original single-bank menu, Bank 0)

### Software — still stubs / not started

- Bank 2 GRAPHICS, Bank 3 SPRITES, Bank 4 INPUT, Bank 8 SOUND — print their own name + "NOT YET IMPLEMENTED", no real logic yet
- Bank 5's `DOKE`/`DUMP`/`FILL`/`MOVE`/`DEEK`/`FIND` — stubs
- Bank 7 (inline-ASM engine) — not started
- Bank 9 (CARTRIDGE-flash: `FLASHERASE`/`FLASHLOAD`/`FLASHVERIFY`) — deliberately stubbed, needs a separately-verified EAPI erase/write sequence
- Banks 11–12 — reserved, unused

### Hardware platform — decided, not yet implemented

- Memory map (`IO1` untouched, `IO2`/`$DF00`-`$DFFF` registers + reserved expansion ranges), ROM banking scheme, ROM API jump table — all designed
- Phase 1 BOM chosen (AM29F040B + 74HCT273/574 + 74HCT139/138)
- Boot architecture worked out: Ultimax forced in hardware at power-on, latch bit assignment for `GAME`/`EXROM`/bank select, flash addressing, why `/RESET` stays tied to the latch, where persistent config lives
- **Not yet done**: actual schematic/PCB, address-decoder wiring detail, flash/EEPROM config-block format, the inverting-gate part choice, and reconciling the existing 13 EasyFlash banks' content with the new Boot/BASIC/Networking/Utilities/Diagnostics/Games/DevTools bank scheme

## Build

```sh
./build_cart.sh        # 13-bank EasyFlash build -> ../build/hello.crt
```

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the single-bank cartridge build command and full architecture detail.
