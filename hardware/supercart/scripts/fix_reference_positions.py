#!/usr/bin/env python3
"""
Nudges reference-designator label positions away from each footprint's own
origin, where they default to and land on top of pads/silkscreen outlines
(kiutils doesn't expose per-property text position, only the string value --
see reference_supercart_pinouts.md for why gen_pcb.py can't set this itself).
Edits the live board file in place -- safe to run before or after routing,
doesn't touch copper/tracks/vias.

IMPORTANT: this is NOT baked into gen_pcb.py and does NOT survive a
regeneration -- re-run this (and re-check DRC) any time gen_pcb.py runs.
Two things have already been silently lost this way once each this project
(a GUI-set footprint rotation, and this exact reference-position fix) --
don't assume the live board matches gen_pcb.py's output without checking.

Run with KiCad's bundled Python, not a system one (see export_dsn.py):
  /Applications/KiCad/KiCad.app/Contents/Frameworks/Python.framework/Versions/3.9/bin/python3.9 fix_reference_positions.py
"""
import wx
app = wx.App()
import pcbnew

PROJECT_DIR = "/Users/rts/Development/C64/hardware/supercart"
board = pcbnew.LoadBoard(f"{PROJECT_DIR}/supercart.kicad_pcb")

# (dx, dy) in nm, absolute-board-frame (not local/rotated) -- chosen by
# inspecting each part's real position on this specific layout, not a
# generic per-footprint-type rule.
OFFSETS = {
    "C1": (0, -2_000_000),
    "C2": (0, 2_500_000),
    "R1": (0, 2_500_000),
    "J1": (0, -8_000_000),
}

nudged = 0
for fp in board.GetFootprints():
    r = fp.GetReference()
    if r in OFFSETS:
        dx, dy = OFFSETS[r]
        ref = fp.Reference()
        p = ref.GetPosition()
        ref.SetPosition(pcbnew.VECTOR2I(p.x + dx, p.y + dy))
        nudged += 1

pcbnew.SaveBoard(f"{PROJECT_DIR}/supercart.kicad_pcb", board)
print(f"nudged {nudged} reference labels, saved {PROJECT_DIR}/supercart.kicad_pcb")
