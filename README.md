# C64 Development Workspace

Three related but independent hardware/software projects.

## Projects

- **[`hello/`](hello/README.md)** — SHACKMATE: a working 13-bank EasyFlash BASIC+ extension cartridge for the C64, plus a planned custom flash-based cartridge/expansion-platform PCB that supersedes it. The most developed project here; see its own README and `docs/` for full detail.
- **[`eprom-reader/`](eprom-reader/README.md)** — reads 27C64 through 27C512 EPROMs and stores the dump to disk. Scaffolding only, no design work started.
- **[`eeprom-writer/`](eeprom-writer/README.md)** — loads a 27CXX ROM binary and writes it to 27SF256-series EEPROMs. Scaffolding only, no design work started.

## Why these are grouped together

`eprom-reader/` and `eeprom-writer/` exist to support hardware bring-up for `hello/`'s planned custom board — dumping/archiving existing EPROM-based cartridges, and burning built ROM images onto sockets during development before the AM29F040B-based board itself is fabricated. They're independent projects (own toolchains, own hardware, own timelines) but share that practical relationship.

`EasyFlash-AppSupport.pdf` / `EasyFlash-ProgRef.pdf` are the real EasyFlash reference docs, kept here for cross-checking `hello/`'s hardware-platform design (GAME/EXROM behavior, register semantics) against something authoritative.
