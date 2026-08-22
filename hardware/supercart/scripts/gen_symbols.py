#!/usr/bin/env python3
"""
Generates the SUPER CARTRIDGE KiCad symbol library + schematic.
All pinouts below were verified against primary sources, not recalled from memory:
  - ATF22V10C: /Users/rts/Development/C64/EEPLD/SUPER_CART_R01.PLD (user's own compiled GAL source)
  - AM29F080B: AMD/Cypress/Infineon datasheet 21503G8 (Nov 11 2009), Connection Diagrams page,
               extracted via pdftotext -layout (not visual/OCR read).
  - C64 44-pin edge connector: c64-wiki.com "Expansion Port" page, parsed from the raw HTML <table>.
"""
"""
Requires: pip install kiutils (developed/tested against kiutils 1.4.8, KiCad 10.0.5).
Run from anywhere; paths below are absolute into the repo.
"""
import uuid

from kiutils.symbol import Symbol, SymbolLib, SymbolPin
from kiutils.items.common import Position, Property, Effects, Font, Justify
from kiutils.items.syitems import SyRect
from kiutils.items.common import Stroke, Fill
from kiutils.schematic import (
    Schematic, SchematicSymbol, SymbolInstance, LocalLabel, Junction,
    NoConnect, TitleBlock, PageSettings,
)
from kiutils.items.schitems import Connection

PIN_LEN = 2.54
PITCH = 2.54


def mkuuid():
    return str(uuid.uuid4())


def make_symbol(entry_name, left_pins, right_pins, ref_prefix, description, datasheet):
    """left_pins/right_pins: list of (number, name, electricalType), given top-to-bottom
    in the same order the real datasheet/connection-diagram draws them."""
    n_left = len(left_pins)
    n_right = len(right_pins)
    n_max = max(n_left, n_right)
    top_y = ((n_max - 1) / 2) * PITCH
    body_half_h = top_y + PITCH
    # width sized so the longest pin name doesn't overlap the body opposite side much; cosmetic only
    body_half_w = 12.7 if n_max > 30 else 7.62

    # KiCad requires a parent symbol holding only properties, plus a nested
    # child unit "<name>_1_1" holding the drawable graphics/pins -- a flat
    # symbol with pins directly on the parent silently fails to load in
    # KiCad 10 even though older kiutils versions can emit that shape.
    sym = Symbol(entryName=entry_name)
    sym.libId = entry_name
    sym.pinNumbers = True
    sym.pinNames = True
    sym.inBom = True
    sym.onBoard = True

    # NOTE: Position angle must be explicit (0), never None/omitted -- KiCad's
    # parser requires all three "(at X Y ANGLE)" values on property/symbol/
    # label placements and rejects the file outright if angle is missing.
    ref = Property(key="Reference", value=ref_prefix,
                    position=Position(-body_half_w, body_half_h + 2.54, 0),
                    effects=Effects(font=Font(height=1.27, width=1.27)))
    val = Property(key="Value", value=entry_name,
                    position=Position(-body_half_w, body_half_h + 1.27, 0),
                    effects=Effects(font=Font(height=1.27, width=1.27)))
    fp = Property(key="Footprint", value="",
                   position=Position(0, -(body_half_h + 2.54), 0),
                   effects=Effects(font=Font(height=1.27, width=1.27), hide=True))
    ds = Property(key="Datasheet", value=datasheet,
                   position=Position(0, -(body_half_h + 3.81), 0),
                   effects=Effects(font=Font(height=1.27, width=1.27), hide=True))
    desc = Property(key="Description", value=description,
                     position=Position(0, -(body_half_h + 5.08), 0),
                     effects=Effects(font=Font(height=1.27, width=1.27), hide=True))
    sym.properties = [ref, val, fp, ds, desc]

    child = Symbol(entryName=entry_name, unitId=1, styleId=1)

    body = SyRect(
        start=Position(-body_half_w, body_half_h),
        end=Position(body_half_w, -body_half_h),
        stroke=Stroke(width=0.254, type="default"),
        fill=Fill(type="background"),
    )
    child.graphicItems = [body]

    # Empirically verified against a real KiCad-authored symbol (the bundled
    # Edgeberry cartridge template): a pin whose electrical tip sits to the
    # LEFT of the body uses angle 0, and one to the RIGHT uses angle 180 --
    # the opposite of the naive "0=points right" reading of the angle field.
    pins = []
    for i, (num, name, etype) in enumerate(left_pins):
        y = top_y - i * PITCH
        style = "inverted" if name.endswith("_N") else "line"
        pins.append(SymbolPin(
            electricalType=etype, graphicalStyle=style,
            position=Position(-(body_half_w + PIN_LEN), y, 0),
            length=PIN_LEN, name=name, number=str(num),
            nameEffects=Effects(font=Font(height=1.27, width=1.27)),
            numberEffects=Effects(font=Font(height=1.27, width=1.27)),
        ))
    for i, (num, name, etype) in enumerate(right_pins):
        y = top_y - i * PITCH
        style = "inverted" if name.endswith("_N") else "line"
        pins.append(SymbolPin(
            electricalType=etype, graphicalStyle=style,
            position=Position(body_half_w + PIN_LEN, y, 180),
            length=PIN_LEN, name=name, number=str(num),
            nameEffects=Effects(font=Font(height=1.27, width=1.27)),
            numberEffects=Effects(font=Font(height=1.27, width=1.27)),
        ))
    child.pins = pins
    sym.units = [child]
    # stash geometry for placement math later
    sym._body_half_w = body_half_w
    sym._body_half_h = body_half_h
    return sym


# ---------------------------------------------------------------------------
# ATF22V10C - 24-pin SOIC. Pin map from EEPLD/SUPER_CART_R01.PLD (verbatim).
# ---------------------------------------------------------------------------
atf_left = [
    (1, "PHI2", "input"),
    (2, "D0", "bidirectional"),
    (3, "D1", "bidirectional"),
    (4, "D2", "bidirectional"),
    (5, "D3", "bidirectional"),
    (6, "D4", "bidirectional"),
    (7, "D5", "bidirectional"),
    (8, "D6", "bidirectional"),
    (9, "D7", "bidirectional"),
    (10, "IO1_N", "input"),
    (11, "RW", "input"),
    (12, "GND", "power_in"),
]
atf_right = [
    (24, "VCC", "power_in"),
    (23, "CTRL2", "output"),  # spare/unused; WRITE_ARM stays internal to the GAL
    (22, "FLASH_WE_N", "output"),  # was CTRL1, renamed 2026-08-21 (SUPER_CART_R01.PLD)
    (21, "FLASH_OE_N", "output"),  # was CTRL0, renamed 2026-08-21 (SUPER_CART_R01.PLD)
    (20, "BANK6", "output"),
    (19, "BANK5", "output"),
    (18, "BANK4", "output"),
    (17, "BANK3", "output"),
    (16, "BANK2", "output"),
    (15, "BANK1", "output"),
    (14, "BANK0", "output"),
    (13, "RESET_N", "input"),
]

# ---------------------------------------------------------------------------
# AM29F080B - 44-pin SO. Pin map from AMD/Cypress/Infineon datasheet 21503G8,
# "Connection Diagrams" page (SO-044), verified via pdftotext -layout extraction.
# ---------------------------------------------------------------------------
flash_left = [
    (1, "NC", "no_connect"),
    (2, "RESET_N", "input"),
    (3, "A11", "input"),
    (4, "A10", "input"),
    (5, "A9", "input"),
    (6, "A8", "input"),
    (7, "A7", "input"),
    (8, "A6", "input"),
    (9, "A5", "input"),
    (10, "A4", "input"),
    (11, "NC", "no_connect"),
    (12, "NC", "no_connect"),
    (13, "A3", "input"),
    (14, "A2", "input"),
    (15, "A1", "input"),
    (16, "A0", "input"),
    (17, "DQ0", "bidirectional"),
    (18, "DQ1", "bidirectional"),
    (19, "DQ2", "bidirectional"),
    (20, "DQ3", "bidirectional"),
    (21, "VSS", "power_in"),
    (22, "VSS", "power_in"),
]
flash_right = [
    (44, "VCC", "power_in"),
    (43, "CE_N", "input"),
    (42, "A12", "input"),
    (41, "A13", "input"),
    (40, "A14", "input"),
    (39, "A15", "input"),
    (38, "A16", "input"),
    (37, "A17", "input"),
    (36, "A18", "input"),
    (35, "A19", "input"),
    (34, "NC", "no_connect"),
    (33, "NC", "no_connect"),
    (32, "NC", "no_connect"),
    (31, "NC", "no_connect"),
    (30, "WE_N", "input"),
    (29, "OE_N", "input"),
    (28, "RY_BY_N", "open_collector"),
    (27, "DQ7", "bidirectional"),
    (26, "DQ6", "bidirectional"),
    (25, "DQ5", "bidirectional"),
    (24, "DQ4", "bidirectional"),
    (23, "VCC", "power_in"),
]

# ---------------------------------------------------------------------------
# C64 44-pin cartridge edge connector. Pin map from c64-wiki.com "Expansion Port"
# page, parsed directly from the article's HTML <table> (not the AI summary).
# Pins "3" and "A" are documented blank in that table (no assigned function),
# but a real, independently-found board (hardware/TestBoard/EpyxFastLoad.kicad_pcb,
# an actual Epyx FastLoad cartridge reproduction whose connector pinout was
# cross-checked pin-for-pin against this table and matched on every other
# pin) ties pin 3 to +5V and pin A to GND rather than leaving them floating --
# adopted here on that real precedent, per user confirmation 2026-08-21.
# ---------------------------------------------------------------------------
edge_left = [
    ("1", "GND", "passive"),
    ("2", "VCC", "passive"),
    ("3", "VCC", "passive"),
    ("4", "IRQ_N", "passive"),
    ("5", "RW", "passive"),
    ("6", "DOTCLK", "passive"),
    ("7", "IO1_N", "passive"),
    ("8", "GAME_N", "passive"),
    ("9", "EXROM_N", "passive"),
    ("10", "IO2_N", "passive"),
    ("11", "ROML_N", "passive"),
    ("12", "BA", "passive"),
    ("13", "DMA_N", "passive"),
    ("14", "D7", "passive"),
    ("15", "D6", "passive"),
    ("16", "D5", "passive"),
    ("17", "D4", "passive"),
    ("18", "D3", "passive"),
    ("19", "D2", "passive"),
    ("20", "D1", "passive"),
    ("21", "D0", "passive"),
    ("22", "GND", "passive"),
]
edge_right = [
    ("A", "GND", "passive"),
    ("B", "ROMH_N", "passive"),
    ("C", "RESET_N", "passive"),
    ("D", "NMI_N", "passive"),
    ("E", "PHI2", "passive"),
    ("F", "A15", "passive"),
    ("H", "A14", "passive"),
    ("J", "A13", "passive"),
    ("K", "A12", "passive"),
    ("L", "A11", "passive"),
    ("M", "A10", "passive"),
    ("N", "A9", "passive"),
    ("P", "A8", "passive"),
    ("R", "A7", "passive"),
    ("S", "A6", "passive"),
    ("T", "A5", "passive"),
    ("U", "A4", "passive"),
    ("V", "A3", "passive"),
    ("W", "A2", "passive"),
    ("X", "A1", "passive"),
    ("Y", "A0", "passive"),
    ("Z", "GND", "passive"),
]

sym_atf = make_symbol(
    "ATF22V10C_SUPERCART", atf_left, atf_right, "U",
    "ATF22V10C GAL, SUPER CARTRIDGE bank/control decoder (SUPER_CART_R01.PLD rev 0.2)",
    "ATF22V10C_datasheet_doc0735.pdf (Microchip doc0735)",
)
sym_flash = make_symbol(
    "AM29F080B_SO44", flash_left, flash_right, "U",
    "AMD/Cypress/Infineon Am29F080B 8Mbit (1Mx8) flash, 44-pin SO",
    "am29f080b_infineon.pdf (Publication 21503 Rev G8, 2009-11-11)",
)
sym_edge = make_symbol(
    "C64_EDGE_CONNECTOR_44", edge_left, edge_right, "J",
    "C64/C128 44-pin cartridge expansion port edge connector",
    "https://www.c64-wiki.com/wiki/Expansion_Port",
)

# PWR_FLAG: standard KiCad idiom for telling ERC a net is legitimately driven
# by an external source (here, the C64 itself, off-board) without marking
# every physical connector pin as a power output -- multiple power_out pins
# tied together on one net (e.g. the connector's 3 GND pins) trips ERC's
# "two power outputs connected" conflict check, which a single flag avoids.
pwr_flag = make_symbol("PWR_FLAG", [(1, "PWR", "power_out")], [], "#FLG",
                        "Power flag: marks a net as driven by an off-board source", "")

lib = SymbolLib(version="20211014", generator="supercart_gen")
lib.symbols = [sym_atf, sym_flash, sym_edge, pwr_flag]
lib_path = "/Users/rts/Development/C64/hardware/supercart/supercart.kicad_sym"
lib.to_file(lib_path)


import re


def insert_embedded_fonts(text):
    """kiutils 1.4.8 doesn't know about the `embedded_fonts` token that KiCad
    10 requires at the end of every TOP-LEVEL symbol definition (both in a
    standalone .kicad_sym and inside a schematic's embedded lib_symbols);
    without it KiCad silently refuses to load the file ("Unable to load
    library"/"Failed to load schematic" -- verified by bisecting against a
    real KiCad-authored .kicad_sym). A top-level symbol's name either carries
    a "nickname:" prefix or (bare .kicad_sym) does NOT end in "_<digit>_<digit>"
    (that suffix marks a nested child unit, which must NOT get this token).
    Located by counting paren depth from each match, not by indentation, so
    it's correct regardless of nesting context."""
    top_level_re = re.compile(r'\(symbol "([^"]+)"')
    out = []
    pos = 0
    for m in top_level_re.finditer(text):
        name = m.group(1)
        is_child = re.search(r'_\d+_\d+$', name) and ':' not in name
        if is_child:
            continue
        # walk forward from the opening paren of this (symbol ...) to find its match
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
        close_idx = i  # index of the matching ')'
        out.append(text[pos:close_idx])
        # match indentation of the line containing the closing paren
        line_start = text.rfind('\n', 0, close_idx) + 1
        indent = text[line_start:close_idx]
        out.append(f'{indent}  (embedded_fonts no)\n{indent}')
        pos = close_idx
    out.append(text[pos:])
    return ''.join(out)


with open(lib_path) as f:
    patched = insert_embedded_fonts(f.read())
with open(lib_path, "w") as f:
    f.write(patched)
print("wrote", lib_path)
