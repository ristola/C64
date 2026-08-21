#!/usr/bin/env python3
"""
Custom footprint for the C64 44-pin cartridge edge connector ("goldfingers").
Geometry verified 2026-08-21 from a real, independently-found board
(hardware/TestBoard/EpyxFastLoad.kicad_pcb, an actual Epyx FastLoad cartridge
reproduction; footprint "EXPANSIO_SQ"): 22 pads/side, pitch 2.54mm, pads
RECTANGULAR 1.5mm x 9mm, long axis perpendicular to the board edge, top/bottom
pads at identical X. (An earlier revision used 1.524x6.35mm oval pads sourced
from the real skoe EasyFlash 2 Gerbers -- also a real, working design; the
Epyx board's rectangular pads were adopted per user choice 2026-08-21 since
it's the more recently and more thoroughly cross-verified of the two sources.)

Two independent pads exist at each of the 22 X positions -- one on F.Cu (the
"lettered" A-Z side) and one on B.Cu (the "numbered" 1-22 side) -- these are
DIFFERENT signals on the real connector, not two pads of the same net; see
reference_supercart_pinouts.md. Which physical face is F.Cu vs B.Cu is NOT
verified against a real cartridge yet -- flagged in the board notes.

Requires: pip install kiutils.
"""
from kiutils.footprint import Footprint, Pad
from kiutils.items.common import Position

PITCH = 2.54
PAD_W = 1.5   # matches EpyxFastLoad's EXPANSIO_SQ footprint exactly
PAD_L = 9.0
N = 22

# Same left/right pin lists as the schematic symbol (gen_symbols.py) -- keep in sync.
edge_left = ["GND", "VCC", "VCC", "IRQ_N", "RW", "DOTCLK", "IO1_N", "GAME_N",
             "EXROM_N", "IO2_N", "ROML_N", "BA", "DMA_N", "D7", "D6", "D5", "D4", "D3",
             "D2", "D1", "D0", "GND"]
edge_right = ["GND", "ROMH_N", "RESET_N", "NMI_N", "PHI2", "A15", "A14", "A13",
              "A12", "A11", "A10", "A9", "A8", "A7", "A6", "A5", "A4", "A3", "A2", "A1",
              "A0", "GND"]
edge_left_num = [str(i) for i in range(1, 23)]
edge_right_num = ["A", "B", "C", "D", "E", "F", "H", "J", "K", "L", "M", "N", "P", "R",
                   "S", "T", "U", "V", "W", "X", "Y", "Z"]

fp = Footprint(entryName="C64_EDGE_CONNECTOR_44")
fp.libId = "supercart:C64_EDGE_CONNECTOR_44"
fp.layer = "F.Cu"
fp.description = "C64 44-pin cartridge edge connector goldfingers; geometry verified against real skoe EasyFlash 2 Gerbers"
fp.attributes.type = "other"
fp.attributes.boardOnly = True
fp.attributes.excludeFromPosFiles = True
fp.attributes.excludeFromBom = False

x0 = -((N - 1) / 2) * PITCH
pads = []
for i in range(N):
    x = x0 + i * PITCH
    # B.Cu pad = "numbered" side (schematic pin numbers "1".."22"). Mask layer
    # included (no soldermask over the goldfingers) but no paste -- these are
    # bare plated contacts, never soldered.
    pads.append(Pad(
        number=edge_left_num[i], type="smd", shape="rect",
        position=Position(x, 0, 0), size=Position(PAD_W, PAD_L),
        layers=["B.Cu", "B.Mask"],
    ))
    # F.Cu pad = "lettered" side (schematic pin numbers "A".."Z", skipping G/I/O/Q)
    pads.append(Pad(
        number=edge_right_num[i], type="smd", shape="rect",
        position=Position(x, 0, 0), size=Position(PAD_W, PAD_L),
        layers=["F.Cu", "F.Mask"],
    ))
fp.pads = pads

import kiutils.footprint as footprint_mod
lib = footprint_mod.__dict__  # not used; footprints save individually below

import os
os.makedirs("/Users/rts/Development/C64/hardware/supercart/supercart.pretty", exist_ok=True)
fp.to_file("/Users/rts/Development/C64/hardware/supercart/supercart.pretty/C64_EDGE_CONNECTOR_44.kicad_mod")
print("wrote C64_EDGE_CONNECTOR_44.kicad_mod")
