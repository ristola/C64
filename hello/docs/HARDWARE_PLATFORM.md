# SHACKMATE Expansion Platform — Hardware Design

**Status: decided direction, not yet implemented.** This document describes a from-scratch custom cartridge PCB (built around an AM29F040B flash chip) that **supersedes** the EasyFlash-format build described in `ARCHITECTURE.md` as the shipping target. The existing EasyFlash `.crt` work remains valuable as proven technique (fixed-slot jump tables, cross-bank calling, the BASIC-extension hooks) — it just isn't the same physical cartridge going forward.

Decided 2026-07-31.

## Why a platform, not just a cartridge

Goal: design the hardware once so it can evolve across future revisions (networking, RTC, GPIO, audio) without breaking software that already exists for it — rather than shipping one fixed ROM image and re-deriving the memory map every time something new gets added.

## Version 1.0 design rules

1. Never conflict with existing C64 hardware or common cartridges.
2. Support the C64 Ultimate modem without changes.
3. Keep the software API stable even if the hardware changes later.
4. Leave room for future expansion.

## Memory map

### IO1 (`$DE00`-`$DEFF`) — not used by this project

Reserved for *external devices*: Ultimate SwiftLink, Turbo232, RR-Net, and any other existing software that expects standard I/O-1 hardware. This platform deliberately avoids IO1 entirely so all of that existing software keeps working unmodified. (Note: this is also where EasyFlash's own `$DE00`/`$DE02` registers live — see "Relationship to the EasyFlash build" below.)

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

Intentionally minimal:

- 1× **AM29F040B** (512KB flash)
- 1× **74HCT273** or **74HCT574** (bank/mode register)
- 1× **74HCT139** or **74HCT138** (address decoding)
- DIP switches / jumpers for development
- Expansion header for future add-ons
- All components socketed (not soldered), so parts can be swapped during bring-up

## Boot architecture

The AM29F040B itself has no concept of Ultimax/16K/8K mode — that's purely a function of what drives the C64 cartridge port's `GAME`/`EXROM` pins, independent of which chip supplies ROM data.

**Verified fact** (from `cartconv`'s own report on the built EasyFlash `.crt`): `exrom: 1 game: 0` = Ultimax. In this project's convention, "asserted" = driven low (`0`); so **Ultimax = `EXROM` deasserted (high/`1`), `GAME` asserted (low/`0`)**. Cross-check this against `EasyFlash-ProgRef.pdf`/`EasyFlash-AppSupport.pdf` before finalizing a schematic — those are the actual EasyFlash reference docs, not just this project's own reverse-engineering.

### Latch bit assignment (74HCT273/574, Q0-Q7)

| Bits | Signal | Wiring |
|---|---|---|
| Q0-Q4 | `BANK[4:0]` | 5 bits → 32 banks × 16KB (8K ROML + 8K ROMH per bank) = 512KB, exactly matching the AM29F040B |
| Q5 | `GAME` | Direct (non-inverted) drive to the cartridge port pin |
| Q6 | `EXROM` | **Inverted** before the cartridge port pin |
| Q7 | spare/reserved | Candidate use: flash write-enable gate (require this bit set + the vendor unlock sequence before any program/erase cycle reaches the chip) |

A 74HCT273 clears all outputs to `0` on its `MR` (master reset) pin, which ties to the cartridge's `/RESET` line. With the wiring above, that power-on default gives `Q5=0 → GAME=0` (asserted) and `Q6=0 → EXROM=NOT(0)=1` (deasserted) — **Ultimax, automatically, with no code having run yet.** That's the whole trick: the *default* state of the hardware has to already be correct, because nothing can execute before the CPU's first instruction fetch establishes some memory map.

Checked against all four real GAME/EXROM modes:

| Mode | GAME (pin) | EXROM (pin) | Q5 | Q6 |
|---|---|---|---|---|
| Ultimax (boot) | 0 | 1 | 0 | 0 |
| 8K (steady-state) | 1 | 0 | 1 | 1 |
| 16K | 0 | 0 | 0 | 1 |
| No cartridge / RAM | 1 | 1 | 1 | 0 |

### Flash addressing

- `Flash A[18:14] = BANK[4:0]` (from Q0-Q4)
- `Flash A13` = ROMH-select, driven from the cartridge port's own `/ROML`/`/ROMH` strobes (the C64 already decodes `$8000-$9FFF` vs `$E000-$FFFF`/`$A000-$BFFF` into those signals — no need to re-derive it from raw address lines)
- `Flash A[12:0] = C64 A[12:0]` straight through

This exactly reproduces the 16KB-per-bank layout `build_cart.sh` *already* produces today (8K ROML then 8K ROMH per bank, real ROMH content only in bank 0) — the existing flash image format carries over to the new hardware unchanged. Only the bank-register address and the bootloader's mode-switching sequence need to change.

### Why `/RESET` stays tied to the latch's clear pin

Considered decoupling the latch from `/RESET` (via a separate power-on-reset circuit) so a user-triggered reset could preserve whatever mode was last selected. Rejected:

- Users expect RESET to reliably return to the cartridge's own boot code — the same convention EasyFlash and other flash carts follow. A cartridge that could get stuck in a disabled/odd mode after RESET would be confusing and could hamper re-flashing/debugging.
- Preserving latch state across a reset pulse depends on analog/timing behavior (supply noise, pulse width, glitches) that's more fragile than the alternative below.

### Where persistent configuration actually lives

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

- Exact `74HCT139`/`138` address-decoder wiring (deriving flash chip-enable, the A13 ROML/ROMH select, and the `$DFxx` register-select strobes from `/ROML`, `/ROMH`, `/IO2`).
- Flash/EEPROM config-block layout the bootloader reads.
- Which inverting-gate part to use for the `EXROM` bit.
- Whether/how the existing 13-bank EasyFlash content maps onto the new Boot/BASIC/Networking/Utilities/Diagnostics/Games/DevTools bank scheme.
