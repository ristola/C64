# C64 Development Workspace

Four related but independent hardware/software projects.

## Projects

- **[`hello/`](hello/README.md)** — SHACKMATE: a working 13-bank EasyFlash BASIC+ extension cartridge for the C64, plus a planned custom flash-based cartridge/expansion-platform PCB that supersedes it, and a Magic Desk-format test build for an already-owned real-hardware bring-up board. The most developed project here; see its own README and `docs/` for full detail.
- **[`eprom-reader/`](eprom-reader/README.md)** — reads 27C64 through 27C512 EPROMs and stores the dump to disk. Scaffolding only, no design work started.
- **[`eeprom-writer/`](eeprom-writer/README.md)** — loads a 27CXX ROM binary and writes it to 27SF256-series EEPROMs. Scaffolding only, no design work started.
- **[`programmer-cartridge/`](programmer-cartridge/README.md)** — a C64 cartridge that programs other cartridges: a ZIF socket for loose EPROM/EEPROM chips plus a second socket for in-circuit programming a companion barebones (surface-mount, non-socketed) release cartridge, with all read/write/backup/clone/load tooling running on the C64 itself. Concept stage, no design work started.

## Why these are grouped together

`eprom-reader/`, `eeprom-writer/`, and `programmer-cartridge/` all exist to support hardware bring-up and eventual distribution for `hello/`'s planned custom board and its release cartridges — dumping/archiving existing EPROM-based cartridges, burning built ROM images during development, and (via `programmer-cartridge/`) eventually producing cheap, mass-producible release hardware. They're independent projects (own toolchains, own hardware, own timelines) but share that practical relationship, and `programmer-cartridge/`'s on-device software overlaps directly with `hello/`'s stubbed Bank 9 (`FLASHERASE`/`FLASHLOAD`/`FLASHVERIFY`) — the same flash erase/write/verify sequence serves both.

`EasyFlash-AppSupport.pdf` / `EasyFlash-ProgRef.pdf` are the real EasyFlash reference docs, kept here for cross-checking `hello/`'s hardware-platform design (GAME/EXROM behavior, register semantics) against something authoritative.
