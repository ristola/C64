#!/usr/bin/env python3
"""
Builds supercart.kicad_pcb: places J1/U1/U2, assigns verified footprints,
wires up the same net map as the schematic (gen_schematic.py), and draws a
board outline sized to the real, fab-verified C64 edge-connector width
(57.66mm, from the real EasyFlash Gerbers -- see reference_supercart_pinouts.md).

NOT yet verified: which physical face (F.Cu vs B.Cu) carries the "numbered"
vs "lettered" connector pins on a real cartridge -- flagged in the board's
own text annotation too. Component placement below is a reasonable first
pass (clearance-checked by DRC), not a final/optimized layout.

Requires: pip install kiutils. Run after gen_footprints.py and gen_symbols.py.
"""
import uuid, re

from kiutils.board import Board, GeneralSettings, LayerToken, SetupData, GrLine, GrArc, GrText
from kiutils.footprint import Footprint
from kiutils.items.common import Position, Effects, Font, Net as CommonNet
from kiutils.board import Net as BoardNet

PROJECT_DIR = "/Users/rts/Development/C64/hardware/supercart"


def mkuuid():
    return str(uuid.uuid4())


def insert_embedded_fonts(text):
    """Same KiCad-10-requires-this-token gotcha as the schematic/symbol files
    (see gen_symbols.py) -- applies to footprints embedded in a board file too."""
    top_level_re = re.compile(r'\(footprint "([^"]+)"')
    out, pos = [], 0
    for m in top_level_re.finditer(text):
        start = m.start()
        depth, i = 0, start
        while i < len(text):
            if text[i] == '(':
                depth += 1
            elif text[i] == ')':
                depth -= 1
                if depth == 0:
                    break
            i += 1
        close_idx = i
        out.append(text[pos:close_idx])
        line_start = text.rfind('\n', 0, close_idx) + 1
        indent = text[line_start:close_idx]
        out.append(f'{indent}  (embedded_fonts no)\n{indent}')
        pos = close_idx
    out.append(text[pos:])
    return ''.join(out)


board = Board(version="20241229", generator="pcbnew")
board.general = GeneralSettings(thickness=1.6)
board.paper.paperSize = "A4"
board.layers = [
    LayerToken(0, "F.Cu", "signal"),
    LayerToken(2, "B.Cu", "signal"),
    LayerToken(9, "F.Adhes", "user", "F.Adhesive"),
    LayerToken(11, "B.Adhes", "user", "B.Adhesive"),
    LayerToken(13, "F.Paste", "user"),
    LayerToken(15, "B.Paste", "user"),
    LayerToken(5, "F.SilkS", "user", "F.Silkscreen"),
    LayerToken(7, "B.SilkS", "user", "B.Silkscreen"),
    LayerToken(1, "F.Mask", "user"),
    LayerToken(3, "B.Mask", "user"),
    LayerToken(17, "Dwgs.User", "user", "User.Drawings"),
    LayerToken(19, "Cmts.User", "user", "User.Comments"),
    LayerToken(21, "Eco1.User", "user", "User.Eco1"),
    LayerToken(23, "Eco2.User", "user", "User.Eco2"),
    LayerToken(25, "Edge.Cuts", "user"),
    LayerToken(27, "Margin", "user"),
    LayerToken(31, "F.CrtYd", "user", "F.Courtyard"),
    LayerToken(29, "B.CrtYd", "user", "B.Courtyard"),
    LayerToken(35, "F.Fab", "user"),
    LayerToken(33, "B.Fab", "user"),
]
# solderMaskMinWidth: leaving this unset made KiCad's DRC apply a stricter
# fallback than any real fab minimum, falsely flagging every adjacent pad on
# the 1.27mm-pitch IC footprints (0.67mm real gap) as a "solder mask bridge" --
# confirmed by rendering the board and visually checking pad spacing was
# actually correct. 0.1mm matches common real fab-house minimums (JLCPCB/OSHPark).
board.setup = SetupData(packToMaskClearance=0.05, solderMaskMinWidth=0.1)

# ---------------------------------------------------------------------------
# Net table: identical net names/pin membership to gen_schematic.py's `nets`.
# Keep these two files in sync by hand -- there is no automated netlist-sync
# step in this pipeline (kicad-cli has no headless "update pcb from schematic").
# ---------------------------------------------------------------------------
nets = {
    # Pins 3/A: tied to +5V/GND per a real precedent found in
    # hardware/TestBoard/EpyxFastLoad.kicad_pcb -- see gen_schematic.py's note.
    # J1 GAME_N/EXROM_N join VCC/GND too -- static 8K cartridge mode, decided
    # 2026-08-21, no Ultimax/mode-switching bootloader.
    "VCC": [("J1", "2"), ("J1", "3"), ("J1", "8"), ("U1", "24"), ("U2", "44"), ("U2", "23"), ("C1", "1"), ("C2", "1"), ("R1", "1"),
            ("R2", "1"), ("R5", "1"), ("R6", "1"), ("R7", "1")],
    "GND": [("J1", "1"), ("J1", "22"), ("J1", "9"), ("J1", "A"), ("J1", "Z"), ("U1", "12"), ("U2", "21"), ("U2", "22"), ("C1", "2"), ("C2", "2"),
            ("LED1", "1"), ("LED2", "1"), ("LED3", "1"), ("Q1", "2"), ("Q2", "2")],
    "PHI2": [("J1", "E"), ("U1", "1")],
    "IO1_N": [("J1", "7"), ("U1", "10")],
    "RW": [("J1", "5"), ("U1", "11")],
    "RESET_N": [("J1", "C"), ("U1", "13"), ("U2", "2")],
    "D0": [("J1", "21"), ("U1", "2"), ("U2", "17")],
    "D1": [("J1", "20"), ("U1", "3"), ("U2", "18")],
    "D2": [("J1", "19"), ("U1", "4"), ("U2", "19")],
    "D3": [("J1", "18"), ("U1", "5"), ("U2", "20")],
    "D4": [("J1", "17"), ("U1", "6"), ("U2", "24")],
    "D5": [("J1", "16"), ("U1", "7"), ("U2", "25")],
    "D6": [("J1", "15"), ("U1", "8"), ("U2", "26")],
    "D7": [("J1", "14"), ("U1", "9"), ("U2", "27")],
    "A0": [("J1", "Y"), ("U2", "16")],
    "A1": [("J1", "X"), ("U2", "15")],
    "A2": [("J1", "W"), ("U2", "14")],
    "A3": [("J1", "V"), ("U2", "13")],
    "A4": [("J1", "U"), ("U2", "10")],
    "A5": [("J1", "T"), ("U2", "9")],
    "A6": [("J1", "S"), ("U2", "8")],
    "A7": [("J1", "R"), ("U2", "7")],
    "A8": [("J1", "P"), ("U2", "6")],
    "A9": [("J1", "N"), ("U2", "5")],
    "A10": [("J1", "M"), ("U2", "4")],
    "A11": [("J1", "L"), ("U2", "3")],
    "A12": [("J1", "K"), ("U2", "42")],
    "BANK0": [("U1", "14"), ("U2", "41")],
    "BANK1": [("U1", "15"), ("U2", "40")],
    "BANK2": [("U1", "16"), ("U2", "39")],
    "BANK3": [("U1", "17"), ("U2", "38")],
    "BANK4": [("U1", "18"), ("U2", "37")],
    "BANK5": [("U1", "19"), ("U2", "36")],
    "BANK6": [("U1", "20"), ("U2", "35")],
    # Flash control assignment decided 2026-08-21 (SUPER_CART_R01.PLD updated
    # to match). /ROML drives Flash /CE directly, bypassing the GAL entirely.
    "ROML_N": [("J1", "11"), ("U2", "43")],
    "FLASH_OE_N": [("U1", "21"), ("U2", "29")],
    "FLASH_WE_N": [("U1", "22"), ("U2", "30"), ("R1", "2"), ("R3", "1")],  # + 10k pull-up to VCC (R1), + WRITE LED gate resistor (R3)
    # RY/BY# (was TBD_FLASH_RYBY_N -- now real, 2026-08-23): open-drain per
    # the datasheet ("dedicated, OPEN-DRAIN output pin"), R2 is its required
    # pull-up -- nothing pulled this net up before, since it was unused.
    "FLASH_RYBY_N": [("U2", "28"), ("R2", "2"), ("R4", "1")],
    "TBD_ROMH_N": [("J1", "B")],
    # --- Status LEDs (PWR/WRITE/BUSY), added 2026-08-23 per user spec.
    # See gen_schematic.py's own comment for the full circuit reasoning
    # (2N7002s wired as shunts across each LED, not series switches --
    # a series low-side switch driven directly by an active-low signal
    # lights the LED when IDLE, backwards; verified against the truth
    # table both ways before wiring). ---
    "Q1_GATE": [("R3", "2"), ("Q1", "1")],
    "WRITE_LED_A": [("R6", "2"), ("LED2", "2"), ("Q1", "3")],
    "Q2_GATE": [("R4", "2"), ("Q2", "1")],
    "BUSY_LED_A": [("R7", "2"), ("LED3", "2"), ("Q2", "3")],
    "PWR_LED_A": [("R5", "2"), ("LED1", "2")],
}

# net number 0 is reserved by KiCad for "no net"
net_objs = {"": BoardNet(0, "")}
board.nets = [net_objs[""]]
for i, name in enumerate(sorted(nets.keys()), start=1):
    n = BoardNet(i, name)
    net_objs[name] = n
    board.nets.append(n)

pin_to_net = {}  # (ref, pinnum) -> net name
for name, members in nets.items():
    for ref, num in members:
        pin_to_net[(ref, num)] = name


FOOTPRINT_DIR = "/Applications/KiCad/KiCad.app/Contents/SharedSupport/footprints"
FP_FILES = {
    "Package_SO:SOIC-24W_7.5x15.4mm_P1.27mm":
        f"{FOOTPRINT_DIR}/Package_SO.pretty/SOIC-24W_7.5x15.4mm_P1.27mm.kicad_mod",
    "Package_SO:SOP-44_13.3x28.2mm_P1.27mm":
        f"{FOOTPRINT_DIR}/Package_SO.pretty/SOP-44_13.3x28.2mm_P1.27mm.kicad_mod",
    "supercart:C64_EDGE_CONNECTOR_44":
        f"{PROJECT_DIR}/supercart.pretty/C64_EDGE_CONNECTOR_44.kicad_mod",
    "supercart:SOP-44_28.2x13.3mm_P1.27mm_HORIZ":
        f"{PROJECT_DIR}/supercart.pretty/SOP-44_28.2x13.3mm_P1.27mm_HORIZ.kicad_mod",
    "supercart:SHACKMATE_LOGO":
        f"{PROJECT_DIR}/supercart.pretty/SHACKMATE_LOGO.kicad_mod",
    "Capacitor_SMD:C_0805_2012Metric":
        f"{FOOTPRINT_DIR}/Capacitor_SMD.pretty/C_0805_2012Metric.kicad_mod",
    "Resistor_SMD:R_0805_2012Metric":
        f"{FOOTPRINT_DIR}/Resistor_SMD.pretty/R_0805_2012Metric.kicad_mod",
    "MountingHole:MountingHole_3.2mm_M3":
        f"{FOOTPRINT_DIR}/MountingHole.pretty/MountingHole_3.2mm_M3.kicad_mod",
    "Package_TO_SOT_SMD:SOT-23":
        f"{FOOTPRINT_DIR}/Package_TO_SOT_SMD.pretty/SOT-23.kicad_mod",
    "LED_SMD:LED_0805_2012Metric":
        f"{FOOTPRINT_DIR}/LED_SMD.pretty/LED_0805_2012Metric.kicad_mod",
}


def load_footprint(lib_id, ref, value, x, y, rot=0):
    """Load the REAL footprint file (verified system libraries or our own
    verified custom one) rather than reconstructing pad geometry by hand --
    avoids re-introducing exactly the kind of guessed-dimension risk already
    worked around for the datasheet pinouts."""
    fp = Footprint().from_file(FP_FILES[lib_id])
    fp.libId = lib_id
    fp.position = Position(x, y, rot)
    fp.tstamp = mkuuid()
    fp.properties["Reference"] = ref
    fp.properties["Value"] = value
    for pad in fp.pads:
        net_name = pin_to_net.get((ref, pad.number))
        if net_name:
            pad.net = net_objs[net_name]
    return fp


# ---------------------------------------------------------------------------
# Placement. Board outline width (57.66mm) matches the real, fab-verified
# EasyFlash connector-region width (see reference_supercart_pinouts.md) --
# this is a hard requirement (the connector must physically fit the C64
# slot), unlike length, which is a practical first-pass choice (socketed
# prototype per the project's Phase 1 hardware notes, not shell-matched).
#
# Layout below is side-by-side ICs above the connector (visual style modeled
# after a reference image the user provided -- NOT its pinout, which
# contradicted the real SUPER_CART_R01.PLD and was rejected; see conversation
# notes). U1/U2 kept at their natural (unrotated) orientation, which puts
# their pin rows on the left/right sides -- confirmed correct by rendering
# and visually checking pad placement earlier in this project.
# ---------------------------------------------------------------------------
# BOARD_W matches hardware/TestBoard/EpyxFastLoad.kicad_pcb's real width
# (58.0mm exactly) per user request 2026-08-21. Its height (37.9mm) is NOT
# matched -- physically unreachable with our parts at their natural
# orientation: the AM29F080B body alone is 28.2mm long (real, verified from
# its datasheet), already leaving no room for the connector + margins in
# 37.9mm total. TestBoard's own chips (DIL28-6, DIL-14 -- small DIP EPROM/
# logic parts) are far smaller than our 44-pin SO-44 flash. Height is instead
# tightened as far as our real components allow (~75mm -> ~60mm), keeping
# the ICs unrotated -- confirmed by user choice over rotating them, which
# would revisit the KiCad rotated-roundrect-pad DRC bug found earlier.
BOARD_W = 58.0
BOARD_L = 60.0
BOARD_X0, BOARD_Y0 = 0.0, 0.0  # top-left corner of the board outline

# J1: connector pads sit ON the board's bottom edge (matches real cartridges --
# insert bottom-first into the C64). Our footprint's pads are drawn at Y=0
# (see gen_footprints.py), centered horizontally; inset ~1mm from true edge
# matches the ~0.6-1.3mm the real EasyFlash Gerbers showed.
J1_X = BOARD_X0 + BOARD_W / 2
J1_Y = BOARD_Y0 + BOARD_L - 5.0

# U1 (ATF22V10C, 7.5w x 15.4h, unrotated) and U2 (AM29F080B) side by side,
# top-aligned, centered as a group within the board width. Each uses its OWN
# half-height/width for the offset so their top edges truly align (an
# earlier version of this script reused U1's half-height for both, which
# left U2 mis-aligned -- harmless at the old, generous 75mm board length but
# worth fixing now that height is tight).
#
# U2 rotation/footprint history (all 2026-08-21/22):
#   -90 (horizontal, stock footprint): user set this in the GUI (and later I
#     did too, twice), each time DID reproduce the rotated-roundrect-pad DRC
#     violations. Initially misdiagnosed as a KiCad DRC false positive
#     (checked only via a full-board render, which was too zoomed out to
#     catch it). CORRECTED 2026-08-22 after measuring real pcbnew pad
#     bounding boxes: it's a genuine 0.58mm pad-to-pad overlap, not a checker
#     bug. Cause: the stock SOP-44 footprint's pads are 1.85mm long x 0.6mm
#     wide, drawn with the long axis ACROSS the two rows and the narrow axis
#     ALONG the 1.27mm pitch -- correct only when unrotated/180. Rotating the
#     whole footprint 90 degrees swings the 1.85mm axis onto the same axis as
#     the 1.27mm pitch, which cannot avoid overlapping neighboring pads.
#   180 (flip, stock footprint): does NOT overlap (180 doesn't swap axes).
#     Routed successfully on that state earlier tonight.
#   0, custom transposed footprint (current): user wants horizontal placement
#     despite the above, so rather than rotating the stock footprint, U2 now
#     uses scripts/make_u2_horizontal_footprint.py's output -- a fresh
#     footprint with every pad's position AND size transposed (X/Y swapped)
#     from the real stock file, so the narrow 0.6mm pad dimension stays
#     aligned with the (now horizontal) 1.27mm pitch. Needs 0 rotation here;
#     the footprint is natively horizontal.
U2_ROT = 0
U2_W, U2_H = 28.2, 13.3

GAP = 8.0
GROUP_W = 7.5 + GAP + U2_W
LEFT_MARGIN = (BOARD_W - GROUP_W) / 2
TOP_Y = 11.0
U1_X, U1_Y = BOARD_X0 + LEFT_MARGIN + 7.5 / 2, BOARD_Y0 + TOP_Y + 15.4 / 2
U2_X, U2_Y = BOARD_X0 + LEFT_MARGIN + 7.5 + GAP + U2_W / 2, BOARD_Y0 + TOP_Y + U2_H / 2

# C1/C2: 0.1uF decoupling caps, placed close to each IC's power pins.
C1_X, C1_Y = U1_X, U1_Y + 15.4 / 2 + 6.0
C2_X, C2_Y = U2_X, U2_Y + U2_H / 2 + 6.0

j1 = load_footprint("supercart:C64_EDGE_CONNECTOR_44", "J1", "C64_EDGE_CONNECTOR_44", J1_X, J1_Y)
u1 = load_footprint("Package_SO:SOIC-24W_7.5x15.4mm_P1.27mm", "U1", "ATF22V10C_SUPERCART", U1_X, U1_Y)
# U2 uses the custom transposed-for-horizontal footprint (see history comment
# above, and scripts/make_u2_horizontal_footprint.py) -- NOT the stock
# Package_SO:SOP-44_13.3x28.2mm_P1.27mm, and NOT rotated.
u2 = load_footprint("supercart:SOP-44_28.2x13.3mm_P1.27mm_HORIZ", "U2", "AM29F080B_SO44", U2_X, U2_Y, U2_ROT)

# U1/U2 3D bodies, replaced 2026-08-23 with custom models carrying real
# laser-marking-style text (scripts/make_ic_body_with_marking.py) -- per
# user request for visible chip info in 3D renders. Real KiCad text/Text-
# node approaches don't work for this (verified, not assumed -- see that
# script's own header): 2D footprint text never wraps onto a 3D model's
# surface, and KiCad's VRML loader silently drops the VRML `Text` node.
# U1 trades its real, accurately-modeled stock SOIC-24W body for a plainer
# custom box to get the marking -- a real visual-fidelity tradeoff, made
# with the user's explicit sign-off. U2 was ALREADY a distorted PSOP-44
# substitute (no real SO-44 3D model exists anywhere in KiCad's library),
# so this is a strict improvement there: real, undistorted 13.3x28.2mm
# body instead of a non-uniformly-stretched approximation.
# Scale 1/2.54 on all axes: KiCad's VRML importer treats raw model units
# as 0.1in (2.54mm), a legacy convention confirmed empirically (a plain
# 10-unit box rendered at ~25.3mm on a known 100mm board) -- the .wrl
# files themselves are authored directly in real mm.
u1.models[0].path = f"{PROJECT_DIR}/supercart.pretty/U1_ATF22V10C_marked.wrl"
u1.models[0].scale.X = u1.models[0].scale.Y = u1.models[0].scale.Z = round(1 / 2.54, 6)
u1.models[0].rotate.X = u1.models[0].rotate.Y = u1.models[0].rotate.Z = 0
u1.models[0].pos.X = u1.models[0].pos.Y = u1.models[0].pos.Z = 0
if u2.models:
    u2.models[0].path = f"{PROJECT_DIR}/supercart.pretty/U2_AM29F080B_marked.wrl"
    u2.models[0].scale.X = u2.models[0].scale.Y = u2.models[0].scale.Z = round(1 / 2.54, 6)
    u2.models[0].rotate.X = u2.models[0].rotate.Y = u2.models[0].rotate.Z = 0
    u2.models[0].pos.X = u2.models[0].pos.Y = u2.models[0].pos.Z = 0
c1 = load_footprint("Capacitor_SMD:C_0805_2012Metric", "C1", "0.1uF", C1_X, C1_Y)
c2 = load_footprint("Capacitor_SMD:C_0805_2012Metric", "C2", "0.1uF", C2_X, C2_Y)

# R1: 10k pull-up, FLASH_WE_N to VCC, per user spec 2026-08-21
R1_X, R1_Y = C2_X + 10.0, C2_Y
r1 = load_footprint("Resistor_SMD:R_0805_2012Metric", "R1", "10k", R1_X, R1_Y)

# No mounting holes -- removed 2026-08-22 per user's real layout (their
# board doesn't have them). Previously MH1/MH2 sat at the top corners.

# --- Status LEDs (PWR/WRITE/BUSY), added 2026-08-23 per user spec. ---
# Placed in the one genuinely free strip of front copper on this board:
# Y=33-48mm, full 58mm width, between the ICs/passives (bottom edge
# ~Y=31mm) and J1's connector fingers (top edge ~Y=50.5mm) -- confirmed
# empty by rendering the board before adding anything here, not assumed.
# Real parts (verified against KiCad's own bundled libraries and, for
# RY/BY#, the AM29F080B datasheet directly -- see gen_schematic.py's
# header comment for the full circuit reasoning): 2N7002 N-channel
# MOSFETs (SOT-23) wired as shunts across the WRITE/BUSY LEDs so their
# gates never load FLASH_WE_N or RY/BY#; PWR is a plain always-on LED,
# no transistor needed.
Y_LED, Y_SUPPORT = 36.0, 42.0

led1 = load_footprint("LED_SMD:LED_0805_2012Metric", "LED1", "LED_Green", 12.0, Y_LED)
r5 = load_footprint("Resistor_SMD:R_0805_2012Metric", "R5", "2.2k", 12.0, Y_SUPPORT)

led2 = load_footprint("LED_SMD:LED_0805_2012Metric", "LED2", "LED_Red", 27.0, Y_LED)
q1 = load_footprint("Package_TO_SOT_SMD:SOT-23", "Q1", "2N7002", 27.0, Y_SUPPORT)
r3 = load_footprint("Resistor_SMD:R_0805_2012Metric", "R3", "100", 22.0, Y_SUPPORT)
r6 = load_footprint("Resistor_SMD:R_0805_2012Metric", "R6", "2.2k", 27.0, Y_SUPPORT + 5.0)

led3 = load_footprint("LED_SMD:LED_0805_2012Metric", "LED3", "LED_Amber", 42.0, Y_LED)
q2 = load_footprint("Package_TO_SOT_SMD:SOT-23", "Q2", "2N7002", 42.0, Y_SUPPORT)
r4 = load_footprint("Resistor_SMD:R_0805_2012Metric", "R4", "100", 37.0, Y_SUPPORT)
r7 = load_footprint("Resistor_SMD:R_0805_2012Metric", "R7", "2.2k", 42.0, Y_SUPPORT + 5.0)
r2 = load_footprint("Resistor_SMD:R_0805_2012Metric", "R2", "10k", 49.0, Y_SUPPORT)  # RY/BY# pull-up

# ShackMate logo on B.SilkS (back silkscreen), 2026-08-23. The front is
# already full (header text, both ICs, passives, connector) but the back
# is completely empty (verified: only the layer-stackup declaration for
# B.SilkS existed in supercart.kicad_pcb before this, zero content), so
# the logo goes there at full size (icon + wordmark + tagline, nothing
# cropped) instead of being squeezed/simplified to fit front leftovers.
# Built by scripts/make_shackmate_logo_footprint.py (potrace + shapely/
# earcut hole-aware triangulation, not KiCad's own bitmap2component --
# see that script's header for why: bitmap2component turned out to be
# GUI-only in this KiCad 10 build, no real headless batch mode found).
# The footprint's own polygon coordinates are pre-mirrored (X negated)
# to match KiCad's back-layer convention -- confirmed by rendering an
# un-mirrored first attempt with `kicad-cli pcb render --side bottom`
# and seeing the wordmark come out backwards before this fix.
# Centered horizontally; vertically centered in the free area above the
# connector fingers (J1 pads start around Y=50.5, logo bottom edge here
# lands around Y=40 -- comfortable clearance, not touching the connector
# region at all).
LOGO_X, LOGO_Y = BOARD_W / 2, 25.0
# Real "LOGO1" reference (not empty): an empty Reference silently breaks
# ExportSpecctraDSN for the WHOLE board (confirmed 2026-08-23 -- FreeRouting
# routing failed with no error beyond "returned False" until every
# footprint's GetReference() was checked and this one came back empty; see
# export_dsn.py's own header for the earlier, different footprint that hit
# the same failure mode). Kept invisible instead via scripts/fix_reference_
# positions.py's real pcbnew SetVisible(False) -- kiutils' Footprint.
# properties has no position/hide control (plain string dict only), so an
# empty string was the only way to avoid the text bleeding onto F.SilkS
# over U2 without that extra step; now that the DSN export needs a real
# reference anyway, hiding it properly is the correct fix either way.
logo = load_footprint("supercart:SHACKMATE_LOGO", "LOGO1", "ShackMate", LOGO_X, LOGO_Y)

board.footprints = [j1, u1, u2, c1, c2, r1, logo,
                     led1, led2, led3, q1, q2, r2, r3, r4, r5, r6, r7]

# Board outline: exact shape traced from hardware/TestBoard/EpyxFastLoad.kicad_pcb
# (real board, per user request 2026-08-21) -- NOT rounded corners (an earlier
# revision of this script guessed that from a mirrored screenshot and got it
# wrong). The real shape, computed from that file's actual Edge.Cuts geometry
# (top-level board outline + the EXPANSIO_SQ connector footprint's own
# Edge.Cuts contribution, which extends the board further down to the fingers
# -- easy to miss by only bounding-boxing the top-level outline, which is
# what gave a wrong 37.9mm height estimate before this was traced properly):
#   - Sharp (unrounded) top corners
#   - Two small semicircular notches (1mm radius) inward on each side edge --
#     purpose on the original board not confirmed (grip cutout? shell
#     alignment tab?), replicated here at proportionally similar positions
#   - 45-degree chamfered bottom corners (0.5mm) right at the connector,
#     bottom edge inset 0.5mm on each side -- this part IS functionally
#     meaningful (keys the connector's insertion orientation)
def rounded_notch_outline(x0, y0, x1, y1, notch_ys, notch_r=1.0, chamfer=0.5):
    items = []
    def line(p1, p2):
        items.append(GrLine(start=Position(*p1), end=Position(*p2), layer="Edge.Cuts",
                             width=0.15, tstamp=mkuuid()))
    def notch_arc(x_edge, ny, inward_x):
        # semicircle bulging from the edge at x_edge toward inward_x, centered on ny
        items.append(GrArc(
            start=Position(x_edge, ny - notch_r), mid=Position(inward_x, ny),
            end=Position(x_edge, ny + notch_r), layer="Edge.Cuts", width=0.15, tstamp=mkuuid(),
        ))

    line((x0, y0), (x1, y0))  # top, sharp corners

    # right edge: straight segments broken up by inward notches, ending in
    # the bottom-right 45-degree chamfer
    y = y0
    for ny in notch_ys:
        line((x1, y), (x1, ny - notch_r))
        notch_arc(x1, ny, x1 - notch_r)
        y = ny + notch_r
    line((x1, y), (x1, y1 - chamfer))
    line((x1, y1 - chamfer), (x1 - chamfer, y1))       # bottom-right chamfer

    line((x1 - chamfer, y1), (x0 + chamfer, y1))       # bottom edge

    line((x0 + chamfer, y1), (x0, y1 - chamfer))       # bottom-left chamfer
    y = y1 - chamfer
    for ny in reversed(notch_ys):
        line((x0, y), (x0, ny + notch_r))
        notch_arc(x0, ny, x0 + notch_r)
        y = ny - notch_r
    line((x0, y), (x0, y0))

    return items


x0, y0, x1, y1 = BOARD_X0, BOARD_Y0, BOARD_X0 + BOARD_W, BOARD_Y0 + BOARD_L
# reference notches sit at ~10.2% and ~59.9% of its 48.9mm total height
NOTCH_YS = [round(BOARD_L * 0.102, 1), round(BOARD_L * 0.599, 1)]
board.graphicItems.extend(rounded_notch_outline(x0, y0, x1, y1, NOTCH_YS))

# Silkscreen title block (F.SilkS, visible on the assembled board). Centered
# between the two mounting holes so it doesn't overlap either one.
board.graphicItems.append(GrText(
    text="SUPER CARTRIDGE", position=Position(BOARD_W / 2, BOARD_Y0 + 3.5, 0),
    layer="F.SilkS", tstamp=mkuuid(),
))
board.graphicItems.append(GrText(
    text="ATF22V10C + AM29F080B  rev 0.2",
    position=Position(BOARD_W / 2, BOARD_Y0 + 6.5, 0), layer="F.SilkS", tstamp=mkuuid(),
))

# Documentation-only note (Cmts.User layer, not silkscreen -- doesn't appear
# on the physical board). Split into short lines at a small font size so it
# stays legible/on-board now that the board is only 58mm wide -- a single
# long line at default text size ran off both edges. NOTE: this script only
# ever produces the UNROUTED board -- routing is a separate step (see
# export_dsn.py / import_ses.py) -- so don't claim a routing status here that
# would go stale the moment that step runs (an earlier "not yet routed" line
# did exactly that). Only note things that stay true regardless of routing.
NOTE_FONT = Effects(font=Font(height=1.0, width=1.0))
NOTE_LINES = [
    "TBD_* nets: Flash RY/BY# and J1 /ROMH",
    "not yet defined in PLD rev 0.2.",
    "J1 F.Cu/B.Cu face assignment NOT",
    "verified vs a real cartridge.",
]
for i, line in enumerate(NOTE_LINES):
    board.graphicItems.append(GrText(
        text=line,
        position=Position(BOARD_X0 + 2, BOARD_Y0 + BOARD_L - 17 + i * 2.2, 0),
        layer="Cmts.User", effects=NOTE_FONT, tstamp=mkuuid(),
    ))

out_path = f"{PROJECT_DIR}/supercart.kicad_pcb"
board.to_file(out_path)
with open(out_path) as f:
    patched = insert_embedded_fonts(f.read())
with open(out_path, "w") as f:
    f.write(patched)
print("wrote", out_path)
