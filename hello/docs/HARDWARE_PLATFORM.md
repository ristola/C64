# SHACKMATE Expansion Platform — Hardware Design

**Status: decided direction, in progress.** This document describes a from-scratch custom cartridge PCB (built around an AM29F080B flash chip) that **supersedes** the EasyFlash-format build described in `ARCHITECTURE.md` as the shipping target. The existing EasyFlash `.crt` work remains valuable as proven technique (fixed-slot jump tables, cross-bank calling, the BASIC-extension hooks) — it just isn't the same physical cartridge going forward.

Decided 2026-07-31. **Superseded in part on 2026-08-10** when `EEPLD/SUPER_CART_R01.PLD` (the actual compiled GAL source, real project ground truth) turned out to use a different memory-map and banking approach than the one originally planned below — see "GAL-based redesign (2026-08-10)" note inside each affected section. **Superseded further on 2026-08-21** (PLD rev 0.2): cartridge mode is now a confirmed, permanent decision — hardwired static 8K (`/EXROM`=GND, `/GAME`=high on the PCB, not GAL signals), not the Ultimax-boot-then-switch scheme described lower in this doc; and the bank register is now real registered logic (not the rev 0.1 "forced to 0" placeholder), with a `WRITE_ARM` safety latch gating flash `/WE`. See "GAL bank/control assignment (ATF22V10C, rev 0.2)" below. KiCad schematic capture for this board lives in `hardware/supercart/` (see that folder's own files for verified chip pinouts).

## Why a platform, not just a cartridge

Goal: design the hardware once so it can evolve across future revisions (networking, RTC, GPIO, audio) without breaking software that already exists for it — rather than shipping one fixed ROM image and re-deriving the memory map every time something new gets added.

## Version 1.0 design rules

1. Never conflict with existing C64 hardware or common cartridges.
2. Support the C64 Ultimate modem without changes.
3. Keep the software API stable even if the hardware changes later.
4. Leave room for future expansion.

## Phase 0: bring-up/test board

Before any Phase 1 hardware exists, an already-owned board can validate the *software* side today: a "Universal C64 Cartridge" (functionally matching, possibly identical to, the open-source [msolajic/c64-uni-cart](https://github.com/msolajic/c64-uni-cart) design). It's a fixed-protocol EPROM/flash cartridge board, not a flexible EasyFlash-style platform, and its behavior was verified against that project's own README/schematic (not guessed):

- **Chip support**: 27C512 (28-pin) through 27C010/020/040/29F010/020/040/27C080 (32-pin), selected via `PIN1`/`PIN31`/`28PIN-32PIN` jumpers per chip family. Directly covers the AM29F040B (in the `29F040` row).
- **Bank register**: a single 74LS273 8-bit latch at `$DE00`, write-only. No separate control register.
- **`MODE` jumper — Magic Desk** (board default): bits 0-6 of the byte written to `$DE00` select 1 of up to 128 8KB banks (1MB max). Bit 7 disables the cartridge (forces `/EXROM` high, RAM shows through at `$8000-$9FFF`) — the classic "free RAM after loading" trick. `LOCK` jumper (default `YES`): once bit 7 disables the cart, further `$DE00` writes are ignored until a hardware reset; `LOCK=NO` makes it reversible.
- **`MODE` jumper — Ocean**: same `$DE00` bank-select, but bit 7 is ignored — no disable feature.
- **`SIZE`/`GAME` jumpers**: fixed 8K mode (default) or fixed 16K mode (`/GAME` pulled low alongside `/EXROM`, mapping `$A000-$BFFF` too). Unlike EasyFlash or the Phase 1 design, **`GAME`/`EXROM` are hardwired by jumper, not software-latch-controlled** — this board has no Ultimax mode at all.
- **`MD` jumper + 2× 1N4148 + 10kΩ**: routes `/ROML` and `/ROMH` to the EPROM's `/OE`; the diodes/resistor are only needed when `SIZE=16K`.

**Boot implication**: since this board never enters Ultimax, the KERNAL's real reset vector runs directly and does its own CBM80-autostart check (`$FD02`, verified byte-for-byte against the real KERNAL ROM: `$C3,$C2,$CD,$38,$30` at ROM offset `$8004-$8008`) before jumping into the cartridge — no `romh_boot.asm`-style bridge needed. `hello/bank0_content.asm` already carries that exact signature (it was never EasyFlash-specific), and `$DE00` is already the address `ram_bank_switch` writes to — so a Magic Desk build needed **zero ROM content changes**, only a different packaging step. See `hello/build_cart_md.sh` (`cartconv -t md`) — builds `build/hello_md.crt`, `Hardware ID: 19 (Magic Desk)`, verified `exrom: 0 game: 1 (8k Game)` matching the table below. Not yet tested on the real board.

## Memory map

### IO1 (`$DE00`-`$DEFF`) — GAL-based redesign (2026-08-10): now used by this project

**Superseded.** This section originally said IO1 was off-limits, reserved for external devices (Ultimate SwiftLink, Turbo232, RR-Net). `SUPER_CART_R01.PLD` — the real, compiled GAL source and current ground truth — instead reads `/IO1` directly on a dedicated ATF22V10C pin (`PIN 10 = IO1_N`), with the bank register living in the `$DE00` area via `/IO1`. This was not a deliberate reversal of the design rule below, it's what the actual hardware ended up doing; flagged here rather than silently overwritten so the original rationale (below) isn't lost.

Original rationale, now void unless this gets revisited: reserve IO1 for *external devices* — Ultimate SwiftLink, Turbo232, RR-Net, and any other existing software that expects standard I/O-1 hardware — so that software keeps working unmodified. (This is also where EasyFlash's own `$DE00`/`$DE02` registers live — see "Relationship to the EasyFlash build" below.) If IO1 use is truly locked in going forward, compatibility with SwiftLink/Turbo232/RR-Net-alike hardware needs to be re-examined.

### IO2 (`$DF00`-`$DFFF`) — belongs to this cartridge

| Address | Register |
|---|---|
| `$DF00` | Control Register |
| `$DF01` | Flash Bank Register |
| `$DF02` | EEPROM Register |
| `$DF03` | Status Register |
| `$DF04` | Flash Programming |
| `$DF05` | Flash Unlock |
| `$DF06` | ROM Configuration |
| `$DF07` | Hardware ID / capability register (bitfield — see below) |
| `$DF10`-`$DF1F` | *Reserved:* Future Network Functions |
| `$DF20`-`$DF2F` | *Reserved:* RTC |
| `$DF30`-`$DF3F` | *Reserved:* GPIO |
| `$DF40`-`$DF4F` | *Reserved:* Expansion Bus |
| `$DF50`-`$DF5F` | *Reserved:* Audio |
| `$DF60`-`$DF6F` | *Reserved:* Diagnostics |
| `$DF70`-`$DFFF` | Reserved |

Registers are reserved rather than densely packed, specifically so future functionality can be added without renumbering anything software already depends on.

### `$DF07` capability register (bitfield)

Lets software auto-detect which features are actually installed on a given board instead of assuming a specific hardware revision:

| Bit | Meaning |
|---|---|
| 0 | Flash Present |
| 1 | EEPROM Present |
| 2 | RTC Present |
| 3 | Network ROM Installed |
| 4 | GPIO Present |
| 5 | Audio Present |
| 6 | Reserved |
| 7 | Development Board |

## ROM banking (standardized purposes)

| Bank | Purpose |
|---|---|
| 0 | Boot ROM |
| 1 | BASIC Extensions |
| 2 | Networking |
| 3 | Utilities |
| 4 | Diagnostics |
| 5 | Games |
| 6 | Development Tools |
| 7 | Reserved |

Not yet decided: how (or whether) the existing EasyFlash build's 13-bank content (BASIC+ core, `HEX$`/`DEC$`, DISK commands, etc. — see `ARCHITECTURE.md`) maps onto this new scheme once real hardware exists to target.

## ROM API

A fixed jump table at `$8000` so BASIC (and other software) calls stable entry points instead of POKEing hardware registers directly — "if the hardware ever changes, the ROM hides those details":

| Address | Entry |
|---|---|
| `$8000` | INIT |
| `$8003` | BANK |
| `$8006` | FLASH READ |
| `$8009` | FLASH WRITE |
| `$800C` | NET INIT |
| `$800F` | NET CONNECT |
| `$8012` | NET SEND |
| `$8015` | NET RECEIVE |
| `$8018` | RTC READ |
| `$801B` | RTC WRITE |

Usage sketch: `SYS API_INIT`, `SYS API_NETCONNECT`, `SYS API_BANK`, etc. Each entry is a fixed 3-byte slot, presumably holding a `JMP <real routine>` — the same fixed-slot-table technique `slots.asm` already uses for per-bank command dispatch in the current EasyFlash build.

## Phase 1 hardware (first real PCB)

**GAL-based redesign (2026-08-10):** `SUPER_CART_R01.PLD` replaces the originally-planned discrete 74HCT273/574 + 74HCT139/138 pair with a single ATF22V10C GAL doing bank/control decode. Current BOM:

- 1× **AM29F080B** (1MB flash, 44-pin SO — the "Final" chip from the PLD's own header comment; supersedes the AM29F040B prototype mentioned in earlier revisions of this doc)
- 1× **ATF22V10C** (24-pin SOIC/PLCC GAL, `U1` in `SUPER_CART_R01.PLD`) — combined bank register + control decode, replacing the 74HCT273/574 + 74HCT139/138 pair below
- ~~74HCT273 / 74HCT574 (bank/mode register)~~ — superseded by the GAL
- ~~74HCT139 / 74HCT138 (address decoding)~~ — superseded by the GAL
- DIP switches / jumpers for development
- Expansion header for future add-ons
- All components socketed (not soldered), so parts can be swapped during bring-up

KiCad schematic capture (verified pinouts for both ICs plus the C64 44-pin edge connector) lives in `hardware/supercart/`.

## Boot architecture

**Superseded 2026-08-21 by the static-8K decision** (see "GAL bank/control assignment (ATF22V10C, rev 0.2)" above) — this whole section describes an Ultimax-boot-then-switch scheme that was considered but not built. The real board never enters Ultimax mode at all: `/EXROM`/`/GAME` are hardwired on the PCB, there is no mode-switching bootloader, and boot works the same way as the Phase 0 test board's Magic-Desk mode (see above) — the KERNAL's own reset vector runs directly and does its CBM80-autostart check. Kept below for the addressing/reasoning history, since the *bank* (as opposed to *mode*) register logic it describes is now real (rev 0.2).

The AM29F040B itself has no concept of Ultimax/16K/8K mode — that's purely a function of what drives the C64 cartridge port's `GAME`/`EXROM` pins, independent of which chip supplies ROM data.

**Verified fact** (from `cartconv`'s own report on the built EasyFlash `.crt`): `exrom: 1 game: 0` = Ultimax. In this project's convention, "asserted" = driven low (`0`); so **Ultimax = `EXROM` deasserted (high/`1`), `GAME` asserted (low/`0`)**. Cross-check this against `EasyFlash-ProgRef.pdf`/`EasyFlash-AppSupport.pdf` before finalizing a schematic — those are the actual EasyFlash reference docs, not just this project's own reverse-engineering.

### GAL bank/control assignment (ATF22V10C, `SUPER_CART_R01.PLD` rev 0.2) — supersedes both rev 0.1 and the 74HCT273/574 Q0-Q7 scheme below

**Cartridge mode decided 2026-08-21: static 8K, permanently.** There is no Ultimax boot phase and no mode-switching bootloader in this design — `/EXROM` is tied directly to GND and `/GAME` directly to +5V on the PCB (neither is a GAL signal, neither is software-controlled). This is a deliberate abandonment of the Ultimax-boot-then-switch plan described later in this doc, not an oversight — that whole plan (the 74HCT273 auto-Ultimax trick, the four-mode GAME/EXROM table, the "persistent configuration in flash" bootloader sequence) is kept below only as historical reasoning for a discrete-logic board that was never built. All 10 of the ATF22V10C's I/O macrocells are used, per the PLD's own header comment:

| PLD pin(s) | Signal | Type | Wiring |
|---|---|---|---|
| 14-20 (`BANK0`-`BANK6`) | 7 bits → flash `A13`-`A19` directly, one-to-one | Registered | 128 banks × 8KB = 1MB, matching the AM29F080B. Flash `A[12:0]` connects straight to the C64's own `A[12:0]` (see `hardware/supercart/` schematic, net map `A0`-`A12`) — no ROML/ROMH-derived strobe. |
| 23 (`WRITE_ARM`) | Flash-write-safety latch bit | Registered | **Not routed externally on the PCB** — a real macrocell, used only internally to gate `FLASH_WE_N`. |
| 21 (`FLASH_OE_N`, was `CTRL0`) | → Flash `/OE` | Combinational | `FLASH_OE_N = !RW` — asserted only during a C64 read. |
| 22 (`FLASH_WE_N`, was `CTRL1`) | → Flash `/WE` | Combinational | `FLASH_WE_N = !(WRITE_ARM & !RW & PHI2)` — asserted only when armed, during a write, on PHI2's high phase. A 10kΩ pull-up (R1) holds this high (write-protected) any time the GAL isn't actively driving it. |
| 1 (`PHI2`), 10 (`IO1_N`), 11 (`RW`), 13 (`RESET_N`) | C64 bus inputs | Input | Clock and qualifying signals for the bank register below. |
| 2-9 (`D0`-`D7`) | C64 data bus | Input | Latched into `BANK0`-`BANK6`/`WRITE_ARM` on a qualifying `$DE00` write. |

`/ROML` from the cartridge edge connector drives flash `/CE` **directly on the PCB** — it is not a GAL pin at all and does not route through the ATF22V10C.

**Bank register + write-arm behavior:** on each `PHI2` rising edge, if the C64 is writing while `/IO1` is asserted (a `$DE00` write), the GAL latches `BANK0..BANK6 <= D0..D6` and `WRITE_ARM <= D7`; otherwise all eight bits hold their previous value (feedback, since the 22V10 has no dedicated clock-enable pin). `/RESET` asynchronously clears all eight bits to 0, so the cartridge always comes back up on bank 0 with flash writes disabled. Software interface (`$DE00` = 56832 decimal):

- `POKE 56832, 0..127` — select bank 0-127, flash writes stay disabled (D7=0)
- `POKE 56832, 128..255` — select bank `(value AND 127)`, flash writes **armed** (D7=1)

See `EEPLD/SUPER_CART_R01.PLD` itself for the full CUPL equations and reasoning (dated, so future revisions won't overwrite this history).

### Originally-planned latch bit assignment (74HCT273/574, Q0-Q7) — NOT what the real PLD implements (superseded twice: first by the GAL redesign, then by the static-8K decision); kept only as historical reasoning

| Bits | Signal | Wiring |
|---|---|---|
| Q0-Q4 | `BANK[4:0]` | 5 bits → 32 banks × 16KB (8K ROML + 8K ROMH per bank) = 512KB, matching the AM29F040B prototype size |
| Q5 | `GAME` | Direct (non-inverted) drive to the cartridge port pin |
| Q6 | `EXROM` | **Inverted** before the cartridge port pin |
| Q7 | spare/reserved | Candidate use: flash write-enable gate (require this bit set + the vendor unlock sequence before any program/erase cycle reaches the chip) |

A 74HCT273 clears all outputs to `0` on its `MR` (master reset) pin, which ties to the cartridge's `/RESET` line. With the wiring above, that power-on default gives `Q5=0 → GAME=0` (asserted) and `Q6=0 → EXROM=NOT(0)=1` (deasserted) — **Ultimax, automatically, with no code having run yet.** That's the whole trick: the *default* state of the hardware has to already be correct, because nothing can execute before the CPU's first instruction fetch establishes some memory map. **This reasoning still needs to be reproduced somehow in the GAL-based design** — it just isn't, yet.

Checked against all four real GAME/EXROM modes:

| Mode | GAME (pin) | EXROM (pin) | Q5 | Q6 |
|---|---|---|---|---|
| Ultimax (boot) | 0 | 1 | 0 | 0 |
| 8K (steady-state) | 1 | 0 | 1 | 1 |
| 16K | 0 | 0 | 0 | 1 |
| No cartridge / RAM | 1 | 1 | 1 | 0 |

### Flash addressing

**Current (GAL-based, matches `SUPER_CART_R01.PLD` and `hardware/supercart/`):**

- `Flash A[19:13] = BANK[6:0]` — from the GAL's `BANK0`-`BANK6` outputs directly, **8KB granularity**
- `Flash A[12:0] = C64 A[12:0]` straight through (no ROML/ROMH-derived strobe)
- `Flash /CE` = C64 `/ROML`, wired directly on the PCB (not through the GAL)
- `Flash /OE` = GAL `FLASH_OE_N` = `!RW` (asserted only on a C64 read)
- `Flash /WE` = GAL `FLASH_WE_N` = `!(WRITE_ARM & !RW & PHI2)` (asserted only when armed via `$DE00` bit 7, during a write, on PHI2 high); a 10kΩ pull-up (R1, PCB) holds it deasserted/write-protected by default

This is a real change from the originally-planned scheme below, not a compatible reproduction of it — 8KB banks are half the size of the 16KB banks `build_cart.sh` currently produces, so **the existing flash image format does *not* carry over unchanged**; the ROM build/packaging step needs rework to match, in addition to the bank-register address. (No bootloader mode-switching sequence applies — cartridge mode is now hardwired static 8K, not software-selected; see "Boot architecture" above.)

**Originally planned (NOT current):**

- `Flash A[18:14] = BANK[4:0]` (from Q0-Q4)
- `Flash A13` = ROMH-select, driven from the cartridge port's own `/ROML`/`/ROMH` strobes (the C64 already decodes `$8000-$9FFF` vs `$E000-$FFFF`/`$A000-$BFFF` into those signals — no need to re-derive it from raw address lines)
- `Flash A[12:0] = C64 A[12:0]` straight through

This would have exactly reproduced the 16KB-per-bank layout `build_cart.sh` already produces today (8K ROML then 8K ROMH per bank, real ROMH content only in bank 0).

### Why `/RESET` stays tied to the latch's clear pin

Considered decoupling the latch from `/RESET` (via a separate power-on-reset circuit) so a user-triggered reset could preserve whatever mode was last selected. Rejected:

- Users expect RESET to reliably return to the cartridge's own boot code — the same convention EasyFlash and other flash carts follow. A cartridge that could get stuck in a disabled/odd mode after RESET would be confusing and could hamper re-flashing/debugging.
- Preserving latch state across a reset pulse depends on analog/timing behavior (supply noise, pulse width, glitches) that's more fragile than the alternative below.

### Where persistent configuration actually lives

**Superseded 2026-08-21** — this section's premise (mode reprogrammed by a bootloader on every boot) doesn't apply now that cartridge mode is hardwired static 8K. Bank selection still isn't persistent across a reset by design (see "bank register + write-arm behavior" above: `/RESET` clears `BANK0-6`/`WRITE_ARM` to 0, always coming back up on bank 0 with flash writes disabled) — kept below for the general "don't persist selectable state in the register itself" reasoning, which still holds.

Not in the latch — in flash (or the `$DF02` EEPROM), which is already non-volatile. Boot sequence:

1. Power-on / `/RESET` → hardware forces Ultimax (fixed, per the table above).
2. CPU fetches its reset vector from ROMH.
3. A small, fixed **bootloader** (Bank 0) runs — guaranteed to run on every single boot, since RESET reliably re-forces Ultimax.
4. Bootloader reads a saved configuration block from a known flash/EEPROM address.
5. Bootloader reprograms the latch (bank + mode) to match.
6. Jump into the configured bank/mode.

Same overall shape as the current EasyFlash build's `cart_start` (Ultimax → own init → switch mode → jump onward, see `ARCHITECTURE.md`) — just with the mode/bank choice now data-driven instead of hardcoded.

## Relationship to the EasyFlash build

The currently-working cartridge (`ARCHITECTURE.md`) targets real EasyFlash hardware/VICE's EasyFlash emulation, whose bank-select register is hardwired at `$DE00` — inside what this platform calls IO1 and declares off-limits. That register location can't be reused here without abandoning the EasyFlash cartridge type entirely, which is exactly what this redesign does. The EasyFlash build isn't being extended by this platform; it's being replaced by it, while reusing the software techniques (bank-switching trampoline-in-RAM, fixed-slot dispatch tables, cross-bank calling) that already proved out there.

## Open items

Resolved as of PLD rev 0.2 / 2026-08-21 (kept struck through for history, not removed, since earlier text in this doc still references them as open):

- ~~GAL logic for flash `/CE`, `/OE`, `/WE`~~ — done. `/CE`=`/ROML` (direct on PCB, not through the GAL), `/OE`/`/WE` are real GAL equations (see "GAL bank/control assignment (ATF22V10C, rev 0.2)" above).
- ~~GAL logic (or other mechanism) for `GAME`/`EXROM`~~ — resolved by decision, not implementation: both are hardwired on the PCB (static 8K), not GAL signals at all.
- ~~`CTRL0`-`CTRL2` function~~ — resolved: renamed `FLASH_OE_N`/`FLASH_WE_N`/`WRITE_ARM` with real logic.
- Board mechanical dimensions (AM29F080B SO-44 footprint, C64 edge-connector goldfinger spec) — resolved by tracing the real `hardware/TestBoard/EpyxFastLoad.kicad_pcb` reference board; `hardware/supercart/` is now a fully routed, DRC-clean board with Gerbers exported.

Still open:

- Since banks are now 8KB (not 16KB), `build_cart.sh`'s ROM image packaging needs rework to match — it currently produces 16KB (8K ROML + 8K ROMH) per bank.
- `$DFxx` register-select strobe derivation from `/IO2` — not used by the PLD at all yet (only `/IO1` is read, per the PLD's own header comment); the whole `$DF00`-`$DFFF` register map above is still aspirational, not wired to anything.
- `/ROMH` (edge connector pin B) still undefined/unconnected — not needed for static 8K mode, left open in case that changes (per PLD's own "NEXT REVISION (0.3)" note).
- Flash `RY/BY#` (pin 28) not read by the GAL at all yet (per PLD's own "NEXT REVISION (0.3)" note).
- Whether/how the existing 13-bank EasyFlash content maps onto the new Boot/BASIC/Networking/Utilities/Diagnostics/Games/DevTools bank scheme.
