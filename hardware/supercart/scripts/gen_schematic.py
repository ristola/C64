#!/usr/bin/env python3
"""Places U1 (ATF22V10C), U2 (AM29F080B), J1 (edge connector) on a sheet and
terminates every used pin with a short wire stub + net label. Two pins with
the same label text are the same net in KiCad, regardless of physical
distance -- this avoids inventing crossing-wire routing for a first-pass
logical schematic; a human can rearrange this freely later without touching
connectivity.

Genuine NC pins (per datasheet / c64-wiki) get an explicit no-connect flag.
Pins whose function is still not decided in SUPER_CART_R01.PLD rev 0.2 get a
TBD_-prefixed label instead of a real net name, per explicit user decision.
"""
"""Run after gen_symbols.py (needs supercart.kicad_sym to already exist).
Requires: pip install kiutils.
"""
import copy, uuid, re

from kiutils.symbol import SymbolLib
from kiutils.items.common import Position, Property, Effects, Font
from kiutils.schematic import (
    Schematic, SchematicSymbol, SymbolInstance, LocalLabel, NoConnect,
    TitleBlock, PageSettings, SymbolProjectInstance, SymbolProjectPath,
    HierarchicalSheetInstance,
)
from kiutils.items.schitems import Connection

PIN_LEN = 2.54
PITCH = 2.54
LIB_NICK = "supercart"


def mkuuid():
    return str(uuid.uuid4())


def insert_embedded_fonts(text):
    """See gen_schematic.py's identical helper: KiCad 10 requires an
    `embedded_fonts` token at the end of every top-level (not child-unit)
    symbol definition, which kiutils 1.4.8 doesn't emit. Located by paren
    depth so it's correct regardless of nesting/indentation."""
    top_level_re = re.compile(r'\(symbol "([^"]+)"')
    out = []
    pos = 0
    for m in top_level_re.finditer(text):
        name = m.group(1)
        is_child = re.search(r'_\d+_\d+$', name) and ':' not in name
        if is_child:
            continue
        start = m.start()
        depth = 0
        i = start
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


lib = SymbolLib().from_file("/Users/rts/Development/C64/hardware/supercart/supercart.kicad_sym")
lib_syms = {s.entryName: s for s in lib.symbols}

# C1/C2: 0.1uF decoupling capacitors near U1/U2 -- standard practice for any
# digital IC, not previously in the design. R1: 10k pull-up from FLASH_WE_N
# to VCC per user spec 2026-08-21, so the flash defaults write-protected any
# time the GAL isn't actively driving the pin low (e.g. power-up sequencing).
# Reuse KiCad's own real "Device:C"/"Device:R" symbols rather than hand-
# building them, same principle as the footprints.
device_lib = SymbolLib().from_file("/Applications/KiCad/KiCad.app/Contents/SharedSupport/symbols/Device.kicad_sym")
lib_syms["C"] = [s for s in device_lib.symbols if s.entryName == "C"][0]
lib_syms["R"] = [s for s in device_lib.symbols if s.entryName == "R"][0]
NICKNAMES = {"C": "Device", "R": "Device"}  # everything else defaults to "supercart"


def symbol_pins(entry_name):
    """Pins live on a nested '<name>_N_1' unit, not the parent symbol -- KiCad
    requires that nesting even for single-unit parts (see gen_symbols.py). Real
    KiCad library parts (e.g. Device:C) can carry a unitId=0 "common to all
    units" placeholder with NO pins ahead of the real unitId=1 -- must match on
    unitId, not just take units[0], or the pins list comes back empty."""
    s = lib_syms[entry_name]
    if not s.units:
        return s.pins
    for u in s.units:
        if u.unitId == 1:
            return u.pins
    return s.units[0].pins


def geometry(entry_name):
    """Recompute body_half_w/h and per-pin (number->(x_local,y_local,angle)) from
    the saved symbol so schematic placement math matches the library exactly."""
    pins_list = symbol_pins(entry_name)
    xs = [abs(p.position.X) for p in pins_list]
    body_half_w = min(xs) - PIN_LEN if xs else 7.62
    ys = [p.position.Y for p in pins_list]
    body_half_h = max(ys) + PITCH if ys else 2.54
    pins = {}
    for p in pins_list:
        pins[p.number] = (p.position.X, p.position.Y, p.position.angle, p.name)
    return body_half_w, body_half_h, pins


schematic = Schematic(version="20211014", generator="supercart_gen")
schematic.uuid = mkuuid()
schematic.paper = PageSettings(paperSize="A2")
schematic.titleBlock = TitleBlock(title="SUPER CARTRIDGE", date="", revision="0.1",
                                   company="N4LDR")
schematic.sheetInstances = [HierarchicalSheetInstance(instancePath="/", page="1")]

# --- embed library symbol copies with the project-nickname-qualified lib id ---
for entry_name, s in lib_syms.items():
    s2 = copy.deepcopy(s)
    s2.libraryNickname = NICKNAMES.get(entry_name, LIB_NICK)
    s2.entryName = entry_name
    schematic.libSymbols.append(s2)


def place_symbol(entry_name, ref, x, y, extra_props=None):
    inst = SchematicSymbol(libName=None)
    inst.libraryNickname = NICKNAMES.get(entry_name, LIB_NICK)
    inst.entryName = entry_name
    inst.position = Position(x, y, 0)
    inst.uuid = mkuuid()
    inst.unit = 1
    inst.inBom = True
    inst.onBoard = True
    inst.pins = {p.number: mkuuid() for p in symbol_pins(entry_name)}
    ref_prop = Property(key="Reference", value=ref, position=Position(x, y - 5, 0),
                         effects=Effects(font=Font(height=1.27, width=1.27)))
    val_prop = Property(key="Value", value=entry_name, position=Position(x, y - 3.5, 0),
                         effects=Effects(font=Font(height=1.27, width=1.27)))
    fp_prop = Property(key="Footprint", value="", position=Position(x, y + 3, 0),
                        effects=Effects(font=Font(height=1.27, width=1.27), hide=True))
    inst.properties = [ref_prop, val_prop, fp_prop]
    inst.instances = [SymbolProjectInstance(
        name="supercart",
        paths=[SymbolProjectPath(sheetInstancePath=f"/{schematic.uuid}", reference=ref, unit=1)]
    )]
    schematic.schematicSymbols.append(inst)
    return inst


# Layout: J1 (edge connector) left, U1 (ATF22V10C) middle, U2 (flash) right.
# All base coordinates are multiples of 2.54mm so every pin/wire endpoint
# (already spaced in 1.27/2.54mm steps) lands on KiCad's connection grid.
X_J1, X_U1, X_U2 = 50.8, 213.36, 355.6
Y0 = 152.4

j1 = place_symbol("C64_EDGE_CONNECTOR_44", "J1", X_J1, Y0)
u1 = place_symbol("ATF22V10C_SUPERCART", "U1", X_U1, Y0)
u2 = place_symbol("AM29F080B_SO44", "U2", X_U2, Y0)
# One PWR_FLAG per power net: tells ERC the net is legitimately driven by the
# C64 itself (off-board) without marking every connector GND/VCC pin as a
# power output, which would trip ERC's "two power outputs connected" check.
X_PF = X_J1 - 25.4
pf_vcc = place_symbol("PWR_FLAG", "#FLG1", X_PF, Y0 - 12.7)
pf_gnd = place_symbol("PWR_FLAG", "#FLG2", X_PF, Y0 + 12.7)

# C1/C2: decoupling caps, drawn near their respective ICs on the diagram.
# Offsets kept as multiples of 1.27mm so pins land on the connection grid.
X_C1, Y_C1 = X_U1 - 20.32, Y0 - 30.48
X_C2, Y_C2 = X_U2 - 20.32, Y0 - 30.48
c1 = place_symbol("C", "C1", X_C1, Y_C1)
c2 = place_symbol("C", "C2", X_C2, Y_C2)
for c in (c1, c2):
    c.properties[1].value = "0.1uF"  # Value
    c.properties[2].value = "Capacitor_SMD:C_0805_2012Metric"  # Footprint

# R1: 10k pull-up, FLASH_WE_N to VCC
X_R1, Y_R1 = X_U2 + 20.32, Y0 - 30.48
r1 = place_symbol("R", "R1", X_R1, Y_R1)
r1.properties[1].value = "10k"
r1.properties[2].value = "Resistor_SMD:R_0805_2012Metric"

geo = {
    "J1": (X_J1, Y0) + geometry("C64_EDGE_CONNECTOR_44"),
    "U1": (X_U1, Y0) + geometry("ATF22V10C_SUPERCART"),
    "U2": (X_U2, Y0) + geometry("AM29F080B_SO44"),
    "#FLG1": (X_PF, Y0 - 12.7) + geometry("PWR_FLAG"),
    "#FLG2": (X_PF, Y0 + 12.7) + geometry("PWR_FLAG"),
    "C1": (X_C1, Y_C1) + geometry("C"),
    "C2": (X_C2, Y_C2) + geometry("C"),
    "R1": (X_R1, Y_R1) + geometry("R"),
}


def pin_tip(ref, number):
    symx, symy, half_w, half_h, pins = geo[ref]
    lx, ly, angle, name = pins[number]
    return symx + lx, symy - ly, angle, name  # schematic Y grows downward vs symbol-local Y


def add_stub_and_label(ref, number, label_text, is_tbd=False):
    x, y, angle, pin_name = pin_tip(ref, number)
    # angle 0 = pin tip is on the LEFT of its body (stub continues further left);
    # angle 180 = tip is on the RIGHT (stub continues further right). Verified
    # against a real KiCad-authored symbol; see gen_schematic.py's note. Same
    # logic applies vertically for angle 90/270 (e.g. Device:C's pins).
    dx = -1.0 if angle == 0 else (1.0 if angle == 180 else 0.0)
    dy = -1.0 if angle == 270 else (1.0 if angle == 90 else 0.0)
    far_x = x + dx * PITCH
    far_y = y + dy * PITCH
    schematic.graphicalItems.append(Connection(
        type="wire", points=[Position(x, y), Position(far_x, far_y)], uuid=mkuuid()
    ))
    lab = LocalLabel(text=label_text, position=Position(far_x, far_y, 0),
                      effects=Effects(font=Font(height=1.27, width=1.27)), uuid=mkuuid())
    schematic.labels.append(lab)


def add_noconnect(ref, number):
    x, y, angle, pin_name = pin_tip(ref, number)
    schematic.noConnects.append(NoConnect(position=Position(x, y, 0), uuid=mkuuid()))


# ---------------------------------------------------------------------------
# Net map. Each entry: net_label -> list of (ref, pin_number).
# Confirmed nets come straight from SUPER_CART_R01.PLD's own pin comments
# cross-checked against the verified AM29F080B and edge-connector pinouts.
# TBD_ nets are exactly the signals the user chose to label-but-not-decide.
# ---------------------------------------------------------------------------
nets = {
    # power (C1/C2: 0.1uF decoupling caps across VCC/GND at U1/U2)
    # Pins 3 and A: c64-wiki documents both as blank/undefined, but a real,
    # independently-found board (hardware/TestBoard/EpyxFastLoad.kicad_pcb)
    # ties pin 3 to +5V and pin A to GND rather than leaving them floating --
    # adopted here on that real precedent, per user choice 2026-08-21.
    # J1 GAME_N/EXROM_N also join these two nets (see below) -- static 8K
    # cartridge mode, decided 2026-08-21, no Ultimax/mode-switching bootloader.
    "VCC": [("J1", "2"), ("J1", "3"), ("J1", "8"), ("U1", "24"), ("U2", "44"), ("U2", "23"), ("#FLG1", "1"), ("C1", "1"), ("C2", "1"), ("R1", "1")],
    "GND": [("J1", "1"), ("J1", "22"), ("J1", "9"), ("J1", "A"), ("J1", "Z"), ("U1", "12"), ("U2", "21"), ("U2", "22"), ("#FLG2", "1"), ("C1", "2"), ("C2", "2")],
    # C64 bus control -> GAL
    "PHI2": [("J1", "E"), ("U1", "1")],
    "IO1_N": [("J1", "7"), ("U1", "10")],
    "RW": [("J1", "5"), ("U1", "11")],
    "RESET_N": [("J1", "C"), ("U1", "13"), ("U2", "2")],
    # data bus: C64 <-> GAL (control/unlock decode) <-> flash DQ
    "D0": [("J1", "21"), ("U1", "2"), ("U2", "17")],
    "D1": [("J1", "20"), ("U1", "3"), ("U2", "18")],
    "D2": [("J1", "19"), ("U1", "4"), ("U2", "19")],
    "D3": [("J1", "18"), ("U1", "5"), ("U2", "20")],
    "D4": [("J1", "17"), ("U1", "6"), ("U2", "24")],
    "D5": [("J1", "16"), ("U1", "7"), ("U2", "25")],
    "D6": [("J1", "15"), ("U1", "8"), ("U2", "26")],
    "D7": [("J1", "14"), ("U1", "9"), ("U2", "27")],
    # address bus: C64 A0-A12 straight through to flash A0-A12 (8KB granularity,
    # matches "64 x 8KB banks" / "128 x 8KB banks" in the PLD header comment)
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
    # bank select: GAL BANK0-6 -> flash A13-A19 (per PLD comments, verbatim)
    "BANK0": [("U1", "14"), ("U2", "41")],
    "BANK1": [("U1", "15"), ("U2", "40")],
    "BANK2": [("U1", "16"), ("U2", "39")],
    "BANK3": [("U1", "17"), ("U2", "38")],
    "BANK4": [("U1", "18"), ("U2", "37")],
    "BANK5": [("U1", "19"), ("U2", "36")],
    "BANK6": [("U1", "20"), ("U2", "35")],
    # --- Flash control assignment, decided/implemented 2026-08-21
    # (SUPER_CART_R01.PLD rev 0.2: FLASH_OE_N=!RW, FLASH_WE_N gated by
    # WRITE_ARM+RW+PHI2). /ROML drives Flash /CE directly, bypassing the
    # GAL entirely -- no ROML pin exists on U1.
    "ROML_N": [("J1", "11"), ("U2", "43")],
    "FLASH_OE_N": [("U1", "21"), ("U2", "29")],
    "FLASH_WE_N": [("U1", "22"), ("U2", "30"), ("R1", "2")],  # + 10k pull-up to VCC (R1)
    # --- TBD: still undefined in SUPER_CART_R01.PLD rev 0.2 ---
    "TBD_FLASH_RYBY_N": [("U2", "28")],
    "TBD_ROMH_N": [("J1", "B")],
}

# Pins deliberately left unconnected (out of current design scope; not asked
# for and not implemented anywhere in SUPER_CART_R01.PLD or the roadmap docs).
# U1 pin 23 (CTRL2): no longer planned as an external control output --
# WRITE_ARM write-safety interlock is meant to live as an internal registered
# term feeding FLASH_WE_N, not its own pin (see SUPER_CART_R01.PLD comments).
no_connects = [
    ("U1", "23"),
    ("U2", "1"), ("U2", "11"), ("U2", "12"), ("U2", "31"), ("U2", "32"), ("U2", "33"), ("U2", "34"),
    ("J1", "4"), ("J1", "6"), ("J1", "10"), ("J1", "12"), ("J1", "13"), ("J1", "D"),
    # A13-A15: real C64 address lines this design doesn't need directly -- the
    # flash's A13-A19 come from the GAL's BANK0-6 outputs instead (see PLD comments)
    ("J1", "F"), ("J1", "H"), ("J1", "J"),
]

for label, members in nets.items():
    for ref, num in members:
        add_stub_and_label(ref, num, label)

for ref, num in no_connects:
    add_noconnect(ref, num)

out_path = "/Users/rts/Development/C64/hardware/supercart/supercart.kicad_sch"
schematic.to_file(out_path)
with open(out_path) as f:
    patched = insert_embedded_fonts(f.read())
with open(out_path, "w") as f:
    f.write(patched)
print("wrote", out_path)
print("nets:", len(nets), "no_connects:", len(no_connects))
