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
    "VCC": [("J1", "2"), ("J1", "3"), ("U1", "24"), ("U2", "44"), ("U2", "23"), ("C1", "1"), ("C2", "1")],
    "GND": [("J1", "1"), ("J1", "22"), ("J1", "A"), ("J1", "Z"), ("U1", "12"), ("U2", "21"), ("U2", "22"), ("C1", "2"), ("C2", "2")],
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
    "TBD_CTRL0": [("U1", "21")],
    "TBD_CTRL1_FLASH_WRITE_SAFETY": [("U1", "22")],
    "TBD_CTRL2": [("U1", "23")],
    "TBD_FLASH_CE_N": [("U2", "43")],
    "TBD_FLASH_OE_N": [("U2", "29")],
    "TBD_FLASH_WE_N": [("U2", "30")],
    "TBD_FLASH_RYBY_N": [("U2", "28")],
    "TBD_GAME_N": [("J1", "8")],
    "TBD_EXROM_N": [("J1", "9")],
    "TBD_ROML_N": [("J1", "11")],
    "TBD_ROMH_N": [("J1", "B")],
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
    "Capacitor_SMD:C_0805_2012Metric":
        f"{FOOTPRINT_DIR}/Capacitor_SMD.pretty/C_0805_2012Metric.kicad_mod",
    "MountingHole:MountingHole_3.2mm_M3":
        f"{FOOTPRINT_DIR}/MountingHole.pretty/MountingHole_3.2mm_M3.kicad_mod",
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

# U1 (ATF22V10C, 7.5w x 15.4h) and U2 (AM29F080B, 13.3w x 28.2h), side by
# side, top-aligned, centered as a group within the board width. Each uses
# its OWN half-height for the Y offset so their top edges truly align (an
# earlier version of this script reused U1's half-height for both, which
# left U2 mis-aligned -- harmless at the old, generous 75mm board length but
# worth fixing now that height is tight).
GAP = 8.0
GROUP_W = 7.5 + GAP + 13.3
LEFT_MARGIN = (BOARD_W - GROUP_W) / 2
TOP_Y = 11.0
U1_X, U1_Y = BOARD_X0 + LEFT_MARGIN + 7.5 / 2, BOARD_Y0 + TOP_Y + 15.4 / 2
U2_X, U2_Y = BOARD_X0 + LEFT_MARGIN + 7.5 + GAP + 13.3 / 2, BOARD_Y0 + TOP_Y + 28.2 / 2

# C1/C2: 0.1uF decoupling caps, placed close to each IC's power pins.
C1_X, C1_Y = U1_X, U1_Y + 15.4 / 2 + 6.0
C2_X, C2_Y = U2_X, U2_Y + 28.2 / 2 + 6.0

j1 = load_footprint("supercart:C64_EDGE_CONNECTOR_44", "J1", "C64_EDGE_CONNECTOR_44", J1_X, J1_Y)
u1 = load_footprint("Package_SO:SOIC-24W_7.5x15.4mm_P1.27mm", "U1", "ATF22V10C_SUPERCART", U1_X, U1_Y)
u2 = load_footprint("Package_SO:SOP-44_13.3x28.2mm_P1.27mm", "U2", "AM29F080B_SO44", U2_X, U2_Y)
# KiCad's own library ships this exact footprint's 2D pads/silkscreen (used
# above -- correct, verified against the real datasheet) but never shipped a
# matching 3D model for it (checked: no SOP-44_13.3x28.2mm_P1.27mm.step
# exists anywhere in the install). Substituting the PSOP-44 model purely for
# a nicer 3D preview, per user choice 2026-08-21 -- cosmetic only, doesn't
# touch pads/copper/Gerbers. Its native body (16.9 x 27.17mm) is scaled down
# to approximate our real body (13.3 x 28.2mm); still an approximation, not
# a real AM29F080B model.
if u2.models:
    u2.models[0].path = "${KICAD10_3DMODEL_DIR}/Package_SO.3dshapes/PSOP-44_16.9x27.17mm_P1.27mm.step"
    u2.models[0].scale.X = round(13.3 / 16.9, 3)
    u2.models[0].scale.Y = round(28.2 / 27.17, 3)
c1 = load_footprint("Capacitor_SMD:C_0805_2012Metric", "C1", "0.1uF", C1_X, C1_Y)
c2 = load_footprint("Capacitor_SMD:C_0805_2012Metric", "C2", "0.1uF", C2_X, C2_Y)

# Mounting holes: purely mechanical (no copper, no net), top corners only --
# the connector occupies the bottom edge. Position not verified against any
# specific shell; a reasonable prototype default, not a fit-checked spec.
mh1 = load_footprint("MountingHole:MountingHole_3.2mm_M3", "MH1", "MountingHole_3.2mm_M3", 6.0, 6.0)
mh2 = load_footprint("MountingHole:MountingHole_3.2mm_M3", "MH2", "MountingHole_3.2mm_M3", BOARD_W - 6.0, 6.0)

board.footprints = [j1, u1, u2, c1, c2, mh1, mh2]

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
    text="ATF22V10C + AM29F080B  rev 0.1",
    position=Position(BOARD_W / 2, BOARD_Y0 + 6.5, 0), layer="F.SilkS", tstamp=mkuuid(),
))

# Documentation-only note (Cmts.User layer, not silkscreen -- doesn't appear
# on the physical board). Split into short lines at a small font size so it
# stays legible/on-board now that the board is only 58mm wide -- a single
# long line at default text size ran off both edges.
NOTE_FONT = Effects(font=Font(height=1.0, width=1.0))
board.graphicItems.append(GrText(
    text="PLACEMENT NOT FINAL - not yet routed.",
    position=Position(BOARD_X0 + 2, BOARD_Y0 + BOARD_L - 15, 0), layer="Cmts.User",
    effects=NOTE_FONT, tstamp=mkuuid(),
))
board.graphicItems.append(GrText(
    text="J1 F.Cu/B.Cu face assignment NOT",
    position=Position(BOARD_X0 + 2, BOARD_Y0 + BOARD_L - 12.5, 0), layer="Cmts.User",
    effects=NOTE_FONT, tstamp=mkuuid(),
))
board.graphicItems.append(GrText(
    text="verified vs a real cartridge.",
    position=Position(BOARD_X0 + 2, BOARD_Y0 + BOARD_L - 10, 0), layer="Cmts.User",
    effects=NOTE_FONT, tstamp=mkuuid(),
))

out_path = f"{PROJECT_DIR}/supercart.kicad_pcb"
board.to_file(out_path)
with open(out_path) as f:
    patched = insert_embedded_fonts(f.read())
with open(out_path, "w") as f:
    f.write(patched)
print("wrote", out_path)
