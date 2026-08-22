# SUPER CARTRIDGE — verified IC and connector pinouts

Consolidated reference for the three parts on `supercart.kicad_pcb`/`.kicad_sch`:
U1 (ATF22V10C GAL), U2 (AM29F080B-90S flash), J1 (C64 44-pin edge connector).
Every pin map below was verified against a primary source (real datasheet,
real compiled GAL source, or a real second board's own Gerbers/PCB file) —
not recalled from memory or guessed. Sources are cited per section.

---

## U1 — ATF22V10C (24-pin SOIC/PLCC GAL)

**Datasheet**: `ATF22V10C_datasheet_doc0735.pdf` (Microchip doc0735), bundled
in this folder.

**Ground truth for pin *usage* is `EEPLD/SUPER_CART_R01.PLD`** — the real,
compiled CUPL source, rev 0.2 — not the datasheet (the datasheet only
confirms the physical package; the PLD defines what this specific design
actually wires each pin to):

| Pin | Signal | Notes |
|---|---|---|
| 1 | PHI2 | Dedicated clock input |
| 2–9 | D0–D7 | C64 data bus |
| 10 | IO1_N | C64 `/IO1`, low for `$DE00`-`$DEFF` |
| 11 | RW | C64 R/W (high=read, low=write) |
| 12 | GND | Standard SOIC power pin — not declared in CUPL (CUPL omits power pins by convention) |
| 13 | RESET_N | C64 `/RESET` |
| 14–20 | BANK0–BANK6 | → flash A13–A19, registered, one-to-one |
| 21 | FLASH_OE_N | → flash `/OE`, combinational: `= !RW` |
| 22 | FLASH_WE_N | → flash `/WE`, combinational: `= !(WRITE_ARM & !RW & PHI2)` |
| 23 | WRITE_ARM | Registered safety latch gating `/WE` — **internal only, not routed off-chip** |
| 24 | VCC | Standard SOIC power pin — not declared in CUPL |

All 22 usable I/O of the 24-pin package are accounted for (12 dedicated
inputs used as 1 clock + 9 data/control + 2 power, 10 configurable
macrocells used as 7 bank bits + `WRITE_ARM` + 2 flash control outputs).

**Not GAL-routed**: `/ROML` drives flash `/CE` **directly on the PCB**,
bypassing the GAL entirely.

Package: 24-lead 0.300" SOIC ("24S" in Microchip's own designation),
E=15.20–15.60mm (nom 15.4), D1=7.40–7.60mm (nom 7.5), e=1.27mm BSC — matches
KiCad's `Package_SO:SOIC-24W_7.5x15.4mm_P1.27mm` (the "W" matters — plain
"SOIC-24" without it is a different, narrower body not in KiCad's library).

---

## U2 — AM29F080B-90S (44-pin SO flash, 1Mb×8)

**Datasheet**: `AM29F080B_datasheet_21503G8.pdf` (AMD/Cypress/Infineon
Publication 21503, Rev G8, 2009-11-11), bundled in this folder.

**Ordering code decoded** (from the datasheet's own Ordering Information
table): `Am29F080B-90S` = 90ns speed, package type **`S` = 44-Pin Small
Outline Package (SO 044)**. There is no "PSOP" ordering code for this part
at all — only `E` (40-pin TSOP) or `S` (44-pin SO). U2 is a plain SO-44.
(KiCad has no bundled 3D `.step` model for this exact body, so the PCB's 3D
preview substitutes a scaled `PSOP-44` model for looks only — that's cosmetic,
not a package claim; pads/copper are real SO-44 geometry.)

**Pin map** (verified via `pdftotext -layout` extraction of the datasheet's
own "Connection Diagrams" page — not a visual/OCR read, which was ambiguous
on the NC-pin count):

Left side, pins 1–22, top to bottom:
`(1) NC, (2) RESET#, (3) A11, (4) A10, (5) A9, (6) A8, (7) A7, (8) A6, (9) A5, (10) A4, (11) NC, (12) NC, (13) A3, (14) A2, (15) A1, (16) A0, (17) DQ0, (18) DQ1, (19) DQ2, (20) DQ3, (21) VSS, (22) VSS`

Right side, pins 44 down to 23, top to bottom:
`(44) VCC, (43) CE#, (42) A12, (41) A13, (40) A14, (39) A15, (38) A16, (37) A17, (36) A18, (35) A19, (34) NC, (33) NC, (32) NC, (31) NC, (30) WE#, (29) OE#, (28) RY/BY#, (27) DQ7, (26) DQ6, (25) DQ5, (24) DQ4, (23) VCC`

Every net in `scripts/gen_pcb.py`'s `NETS` dict was cross-checked against
this table pin-by-pin (VCC/GND/RESET#/D0-7/A0-A19/CE#/OE#/WE#/RY-BY#) and
matches exactly.

Package: SO-44, body D=28.00–28.40mm (nom 28.20), E1=13.10–13.50mm (nom
13.30), pitch e=1.27mm BSC (JEDEC MO-180 (A) AA) — matches KiCad's
`Package_SO:SOP-44_13.3x28.2mm_P1.27mm` exactly (not the similarly-named
12.6×28.5mm candidate).

U2's board footprint is a **custom horizontal variant**
(`supercart.pretty/SOP-44_28.2x13.3mm_P1.27mm_HORIZ.kicad_mod`, built by
`scripts/make_u2_horizontal_footprint.py`) — a real 90° in-plane rotation of
KiCad's stock footprint pre-baked into the pad geometry (not a KiCad
footprint-angle rotation, which triggers a real DRC pad-overlap bug on this
part's roundrect pads at 90/270°). An earlier version of that script used a
coordinate transpose instead of a true rotation, which is a mirror
transformation, not a rotation — it silently reversed the pin-1→44 winding
order around the package. Fixed 2026-08-22; see that script's own header
comment for the full proof (shoelace-formula winding check).

---

## J1 — C64/C128 44-pin cartridge edge connector

**Source**: c64-wiki.com's "Expansion Port" page, parsed from the raw HTML
`<table>` (not that page's own AI summary, which mislabeled pin 6 as PHI2 —
pin 6 is actually the ~8MHz dot clock; the real 0.985MHz PHI2 is pin **E**).
Independently cross-checked pin-for-pin against a second real board,
`hardware/TestBoard/EpyxFastLoad.kicad_pcb` (a real Epyx FastLoad cartridge
reproduction) — matched on every single pin.

**Numeric side, pins 1–22**:
`(1) GND, (2) VCC, (3) reserved, (4) IRQ, (5) R/W, (6) DOTCLK, (7) IO1, (8) GAME, (9) EXROM, (10) IO2, (11) ROML, (12) BA, (13) DMA, (14) D7, (15) D6, (16) D5, (17) D4, (18) D3, (19) D2, (20) D1, (21) D0, (22) GND`

**Lettered side, A–Z (skips G/I/O/Q)**:
`(A) reserved, (B) ROMH, (C) RESET, (D) NMI, (E) PHI2, (F) A15, (H) A14, (J) A13, (K) A12, (L) A11, (M) A10, (N) A9, (P) A8, (R) A7, (S) A6, (T) A5, (U) A4, (V) A3, (W) A2, (X) A1, (Y) A0, (Z) GND`

Pins **3** and **A** are documented blank/reserved by c64-wiki. This project
ties pin 3 → VCC and pin A → GND (per EpyxFastLoad's own real, working
precedent — adopted 2026-08-21), rather than leaving them floating.
`/ROMH` (pin B) is intentionally left unconnected — not needed for this
board's permanent static-8K mode, kept open per `SUPER_CART_R01.PLD`'s own
"NEXT REVISION (0.3)" note in case that changes.

**Mechanical** (verified from real Gerbers, not an estimate): 2.54mm pitch,
rectangular pads 1.5mm × 9mm (matches EpyxFastLoad's own `EXPANSIO_SQ`
footprint), goldfinger board-width region 57.66mm (from the real skoe
EasyFlash 2 Gerbers) — cross-confirmed to ~57.7–58mm by two further
independent sources (EpyxFastLoad's own 58.0mm board width, and an earlier
AI-generated 58.1–58.7mm estimate).

**Which physical copper face carries which row — RESOLVED 2026-08-22**
(previously an open question in this project): inspected `EXPANSIO_SQ`'s own
pad-layer assignments directly in `EpyxFastLoad.kicad_pcb`. Both that
board's J1 and this project's J1 are placed unmirrored, footprint-level
layer F.Cu (confirmed by checking for a mirror flag on each — neither has
one; they differ only in in-plane rotation, which doesn't affect which
copper layer a pad sits on). Result: **numbered pins 1–22 → F.Cu, lettered
pins A–Z → B.Cu**. This project's footprint (`gen_footprints.py`) had that
backwards until this fix — corrected in the script and in the standalone
`supercart.pretty/C64_EDGE_CONNECTOR_44.kicad_mod` file.

**Known gap, not yet closed**: the corrected footprint has *not* been
propagated into the live `supercart.kicad_pcb` yet. That board currently has
real routing on it (added after the U2-footprint-rotation fix, outside of
any script run) using the *old, backwards* F.Cu/B.Cu assignment for J1.
Applying the fix means J1's pads move to the opposite copper layer, which
will require re-routing whatever traces currently land on them — do this
deliberately, not as a side effect of an unrelated regeneration.

Connector edge-connector goldfingers: no soldermask, no paste (bare plated
contacts, never soldered) — see `Pad` `layers` lists in
`scripts/gen_footprints.py` (`F.Cu`/`F.Mask` or `B.Cu`/`B.Mask` only).
