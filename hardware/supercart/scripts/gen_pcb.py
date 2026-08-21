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

from kiutils.board import Board, GeneralSettings, LayerToken, SetupData, GrLine, GrText
from kiutils.footprint import Footprint
from kiutils.items.common import Position, Net as CommonNet
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
    "VCC": [("J1", "2"), ("U1", "24"), ("U2", "44"), ("U2", "23")],
    "GND": [("J1", "1"), ("J1", "22"), ("J1", "Z"), ("U1", "12"), ("U2", "21"), ("U2", "22")],
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


FP_FILES = {
    "Package_SO:SOIC-24W_7.5x15.4mm_P1.27mm":
        "/Applications/KiCad/KiCad.app/Contents/SharedSupport/footprints/Package_SO.pretty/SOIC-24W_7.5x15.4mm_P1.27mm.kicad_mod",
    "Package_SO:SOP-44_13.3x28.2mm_P1.27mm":
        "/Applications/KiCad/KiCad.app/Contents/SharedSupport/footprints/Package_SO.pretty/SOP-44_13.3x28.2mm_P1.27mm.kicad_mod",
    "supercart:C64_EDGE_CONNECTOR_44":
        f"{PROJECT_DIR}/supercart.pretty/C64_EDGE_CONNECTOR_44.kicad_mod",
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
# EasyFlash connector-region width (see reference_supercart_pinouts.md).
# Length (90mm) is a practical first-pass choice, not shell-matched -- this
# is a socketed prototype per the project's own Phase 1 hardware notes.
# ---------------------------------------------------------------------------
BOARD_W = 57.66
BOARD_L = 90.0
BOARD_X0, BOARD_Y0 = 0.0, 0.0  # top-left corner of the board outline

# J1: connector pads sit ON the board's bottom edge (matches real cartridges --
# insert bottom-first into the C64). Our footprint's pads are drawn at Y=0
# (see gen_footprints.py), centered horizontally; inset ~1mm from true edge
# matches the ~0.6-1.3mm the real EasyFlash Gerbers showed.
J1_X = BOARD_X0 + BOARD_W / 2
J1_Y = BOARD_Y0 + BOARD_L - 5.0

# U1 (ATF22V10C, 15.4 x 7.5mm) and U2 (AM29F080B, 28.2 x 13.3mm): placed with
# generous clearance in the body of the board, above the connector. This is a
# reasonable first-pass placement (DRC-checked for overlaps), not a routing-
# optimized final layout -- expect to rearrange after seeing the ratsnest.
U1_X, U1_Y = BOARD_X0 + BOARD_W / 2, BOARD_Y0 + 25.0
U2_X, U2_Y = BOARD_X0 + BOARD_W / 2, BOARD_Y0 + 55.0

j1 = load_footprint("supercart:C64_EDGE_CONNECTOR_44", "J1", "C64_EDGE_CONNECTOR_44", J1_X, J1_Y)
u1 = load_footprint("Package_SO:SOIC-24W_7.5x15.4mm_P1.27mm", "U1", "ATF22V10C_SUPERCART", U1_X, U1_Y, 90)
u2 = load_footprint("Package_SO:SOP-44_13.3x28.2mm_P1.27mm", "U2", "AM29F080B_SO44", U2_X, U2_Y, 90)
board.footprints = [j1, u1, u2]

# Board outline (Edge.Cuts rectangle)
corners = [
    (BOARD_X0, BOARD_Y0), (BOARD_X0 + BOARD_W, BOARD_Y0),
    (BOARD_X0 + BOARD_W, BOARD_Y0 + BOARD_L), (BOARD_X0, BOARD_Y0 + BOARD_L),
]
for i in range(4):
    x1, y1 = corners[i]
    x2, y2 = corners[(i + 1) % 4]
    board.graphicItems.append(GrLine(
        start=Position(x1, y1), end=Position(x2, y2), layer="Edge.Cuts",
        width=0.15, tstamp=mkuuid(),
    ))

board.graphicItems.append(GrText(
    text="SUPER CARTRIDGE rev 0.1 - PLACEMENT NOT FINAL - connector F.Cu/B.Cu face assignment NOT verified vs a real cartridge, see project notes",
    position=Position(BOARD_X0 + 2, BOARD_Y0 + 5, 0), layer="Cmts.User", tstamp=mkuuid(),
))

out_path = f"{PROJECT_DIR}/supercart.kicad_pcb"
board.to_file(out_path)
with open(out_path) as f:
    patched = insert_embedded_fonts(f.read())
with open(out_path, "w") as f:
    f.write(patched)
print("wrote", out_path)
