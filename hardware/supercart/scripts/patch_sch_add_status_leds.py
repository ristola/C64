#!/usr/bin/env python3
"""
Adds the PWR/WRITE/BUSY status-LED circuit to the LIVE supercart.kicad_sch
by loading it and appending new symbols/wires/labels, rather than
regenerating the whole file from gen_schematic.py -- the live file has
been opened and edited in the real KiCad GUI (full-file rewrite in
eeschema's own format, no longer byte-identical to what gen_schematic.py
would produce), so a full regeneration risks discarding whatever manual
state exists there. Same principle as never blindly re-running gen_pcb.py
against a routed board.

Circuit: see gen_schematic.py's own header comment above its status-LED
placement block for the full reasoning (2N7002 shunt topology, RY/BY#
pull-up, etc.) -- this script just adds the same design to the live file
instead of a fresh one.

Verified round-trip fidelity before relying on this approach: loading the
live (real eeschema-saved) file via kiutils and immediately re-saving it
produces only a few extra *cosmetic* `lib_symbol_issues` ERC warnings (a
known kicad-cli quirk, not a real data-loss issue) -- confirmed by diffing
ERC output before/after a bare load+save round-trip.

Requires: pip install kiutils.
"""
import uuid, re

from kiutils.symbol import SymbolLib
from kiutils.items.common import Position, Property, Effects, Font
from kiutils.schematic import Schematic, SchematicSymbol, LocalLabel, SymbolProjectInstance, SymbolProjectPath
from kiutils.items.schitems import Connection

PIN_LEN = 2.54
PITCH = 2.54
LIVE_PATH = "/Users/rts/Development/C64/hardware/supercart/supercart.kicad_sch"


def mkuuid():
    return str(uuid.uuid4())


sch = Schematic.from_file(LIVE_PATH)

device_lib = SymbolLib.from_file("/Applications/KiCad/KiCad.app/Contents/SharedSupport/symbols/Device.kicad_sym")
fet_lib = SymbolLib.from_file("/Applications/KiCad/KiCad.app/Contents/SharedSupport/symbols/Transistor_FET.kicad_sym")
led_sym = [s for s in device_lib.symbols if s.entryName == "LED"][0]
qfet_sym = [s for s in fet_lib.symbols if s.entryName == "Q_NMOS_GSD"][0]

import copy
existing_names = {s.entryName for s in sch.libSymbols}
for entry_name, s, nick in [("LED", led_sym, "Device"), ("Q_NMOS_GSD", qfet_sym, "Transistor_FET")]:
    if entry_name in existing_names:
        continue
    s2 = copy.deepcopy(s)
    s2.libraryNickname = nick
    s2.entryName = entry_name
    sch.libSymbols.append(s2)

lib_syms = {s.entryName: s for s in sch.libSymbols}
NICKNAMES = {"C": "Device", "R": "Device", "LED": "Device", "Q_NMOS_GSD": "Transistor_FET"}
LIB_NICK = "supercart"


def symbol_pins(entry_name):
    s = lib_syms[entry_name]
    if not s.units:
        return s.pins
    for u in s.units:
        if u.unitId == 1:
            return u.pins
    return s.units[0].pins


def geometry(entry_name):
    pins_list = symbol_pins(entry_name)
    xs = [abs(p.position.X) for p in pins_list]
    body_half_w = min(xs) - PIN_LEN if xs else 7.62
    ys = [p.position.Y for p in pins_list]
    body_half_h = max(ys) + PITCH if ys else 2.54
    pins = {}
    for p in pins_list:
        pins[p.number] = (p.position.X, p.position.Y, p.position.angle, p.name)
    return body_half_w, body_half_h, pins


def place_symbol(entry_name, ref, x, y):
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
        paths=[SymbolProjectPath(sheetInstancePath=f"/{sch.uuid}", reference=ref, unit=1)]
    )]
    sch.schematicSymbols.append(inst)
    return inst


# Placed well clear of the existing layout (far below/right of it) so
# there's no chance of colliding with whatever manual rearrangement exists
# in the live file -- these coordinates don't need to match gen_schematic.
# py's own placement, they just need to be internally consistent and
# collision-free (checked below before writing anything).
X0, Y0 = 50.8, 350.52
X_PULLUP, X_GATE_R, X_LED_R, X_FET, X_LED = (
    X0, X0 + 25.4, X0 + 50.8, X0 + 76.2, X0 + 101.6
)
Y_PWR, Y_WRITE, Y_BUSY = Y0, Y0 + 20.32, Y0 + 40.64

r2 = place_symbol("R", "R2", X_PULLUP, Y_BUSY)
r2.properties[1].value = "10k"; r2.properties[2].value = "Resistor_SMD:R_0805_2012Metric"
r3 = place_symbol("R", "R3", X_GATE_R, Y_WRITE)
r3.properties[1].value = "100"; r3.properties[2].value = "Resistor_SMD:R_0805_2012Metric"
r4 = place_symbol("R", "R4", X_GATE_R, Y_BUSY)
r4.properties[1].value = "100"; r4.properties[2].value = "Resistor_SMD:R_0805_2012Metric"
r5 = place_symbol("R", "R5", X_LED_R, Y_PWR)
r5.properties[1].value = "2.2k"; r5.properties[2].value = "Resistor_SMD:R_0805_2012Metric"
r6 = place_symbol("R", "R6", X_LED_R, Y_WRITE)
r6.properties[1].value = "2.2k"; r6.properties[2].value = "Resistor_SMD:R_0805_2012Metric"
r7 = place_symbol("R", "R7", X_LED_R, Y_BUSY)
r7.properties[1].value = "2.2k"; r7.properties[2].value = "Resistor_SMD:R_0805_2012Metric"
q1 = place_symbol("Q_NMOS_GSD", "Q1", X_FET, Y_WRITE)
q1.properties[1].value = "2N7002"; q1.properties[2].value = "Package_TO_SOT_SMD:SOT-23"
q2 = place_symbol("Q_NMOS_GSD", "Q2", X_FET, Y_BUSY)
q2.properties[1].value = "2N7002"; q2.properties[2].value = "Package_TO_SOT_SMD:SOT-23"
led1 = place_symbol("LED", "LED1", X_LED, Y_PWR)
led1.properties[1].value = "LED_Green"; led1.properties[2].value = "LED_SMD:LED_0805_2012Metric"
led2 = place_symbol("LED", "LED2", X_LED, Y_WRITE)
led2.properties[1].value = "LED_Red"; led2.properties[2].value = "LED_SMD:LED_0805_2012Metric"
led3 = place_symbol("LED", "LED3", X_LED, Y_BUSY)
led3.properties[1].value = "LED_Amber"; led3.properties[2].value = "LED_SMD:LED_0805_2012Metric"

geo = {
    "R2": (X_PULLUP, Y_BUSY) + geometry("R"),
    "R3": (X_GATE_R, Y_WRITE) + geometry("R"),
    "R4": (X_GATE_R, Y_BUSY) + geometry("R"),
    "R5": (X_LED_R, Y_PWR) + geometry("R"),
    "R6": (X_LED_R, Y_WRITE) + geometry("R"),
    "R7": (X_LED_R, Y_BUSY) + geometry("R"),
    "Q1": (X_FET, Y_WRITE) + geometry("Q_NMOS_GSD"),
    "Q2": (X_FET, Y_BUSY) + geometry("Q_NMOS_GSD"),
    "LED1": (X_LED, Y_PWR) + geometry("LED"),
    "LED2": (X_LED, Y_WRITE) + geometry("LED"),
    "LED3": (X_LED, Y_BUSY) + geometry("LED"),
}


def pin_tip(ref, number):
    symx, symy, half_w, half_h, pins = geo[ref]
    lx, ly, angle, name = pins[number]
    return symx + lx, symy - ly, angle, name


def add_stub_and_label(ref, number, label_text):
    x, y, angle, pin_name = pin_tip(ref, number)
    dx = -1.0 if angle == 0 else (1.0 if angle == 180 else 0.0)
    dy = -1.0 if angle == 270 else (1.0 if angle == 90 else 0.0)
    far_x, far_y = x + dx * PITCH, y + dy * PITCH
    sch.graphicalItems.append(Connection(
        type="wire", points=[Position(x, y), Position(far_x, far_y)], uuid=mkuuid()
    ))
    lab = LocalLabel(text=label_text, position=Position(far_x, far_y, 0),
                      effects=Effects(font=Font(height=1.27, width=1.27)), uuid=mkuuid())
    sch.labels.append(lab)
    return (far_x, far_y)


new_nets = {
    "VCC": [("R2", "1"), ("R5", "1"), ("R6", "1"), ("R7", "1")],
    "GND": [("LED1", "1"), ("LED2", "1"), ("LED3", "1"), ("Q1", "2"), ("Q2", "2")],
    "FLASH_WE_N": [("R3", "1")],
    "FLASH_RYBY_N": [("R2", "2"), ("R4", "1")],
    "Q1_GATE": [("R3", "2"), ("Q1", "1")],
    "WRITE_LED_A": [("R6", "2"), ("LED2", "2"), ("Q1", "3")],
    "Q2_GATE": [("R4", "2"), ("Q2", "1")],
    "BUSY_LED_A": [("R7", "2"), ("LED3", "2"), ("Q2", "3")],
    "PWR_LED_A": [("R5", "2"), ("LED1", "2")],
}

# Collision check before writing anything -- same check that caught a real
# bug (R2/R3 sharing an X offset) during gen_schematic.py development.
from collections import defaultdict
coord_to_labels = defaultdict(set)
for label, members in new_nets.items():
    for ref, num in members:
        x, y, angle, _ = pin_tip(ref, num)
        dx = -1.0 if angle == 0 else (1.0 if angle == 180 else 0.0)
        dy = -1.0 if angle == 270 else (1.0 if angle == 90 else 0.0)
        coord_to_labels[(round(x + dx * PITCH, 3), round(y + dy * PITCH, 3))].add(label)
collisions = {c: labs for c, labs in coord_to_labels.items() if len(labs) > 1}
if collisions:
    raise SystemExit(f"coordinate collision(s) between different nets: {collisions}")

for label, members in new_nets.items():
    for ref, num in members:
        add_stub_and_label(ref, num, label)

# Rename the one existing TBD_FLASH_RYBY_N label (U2 pin 28) to the real
# net name now that it's actually used -- same net, just no longer TBD.
renamed = 0
for lab in sch.labels:
    if lab.text == "TBD_FLASH_RYBY_N":
        lab.text = "FLASH_RYBY_N"
        renamed += 1
if renamed != 1:
    raise SystemExit(f"expected exactly 1 TBD_FLASH_RYBY_N label, found {renamed}")

sch.to_file(LIVE_PATH)
print(f"patched {LIVE_PATH}")
print(f"added {len(new_nets)} nets, renamed {renamed} label")
