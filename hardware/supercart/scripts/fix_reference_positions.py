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
}

# Status-LED circuit (2026-08-23): 9 small (0805/SOT-23) parts packed into
# one 58x15mm strip -- individually repositioning each Reference field to
# dodge its neighbors' silkscreen (like OFFSETS above does for the original
# 4 parts) got fragile fast at this density. Hiding the Reference text
# instead is simpler, reliable, and standard practice at this component
# scale (0805/SOT-23 reference silkscreen is rarely legible on a real
# fabbed board anyway). LOGO1 is hidden for a different reason entirely --
# see gen_pcb.py's own comment: it needs a real, non-empty Reference for
# ExportSpecctraDSN to work at all, but was never meant to be visible.
HIDDEN_REFS = {"LOGO1", "LED1", "LED2", "LED3", "Q1", "Q2", "R2", "R3", "R4", "R5", "R6", "R7",
               # J1 was in OFFSETS (dy=-8mm) until the status-LED row filled
               # Y=36-47 (where that landed) and its own pads fill essentially
               # all of Y=50.5-59.5 -- no offset in the remaining ~3.5mm gap
               # cleared both. Hidden instead: it's the giant edge connector,
               # self-evident without a label.
               "J1"}

nudged = 0
hidden = 0
for fp in board.GetFootprints():
    r = fp.GetReference()
    if r in OFFSETS:
        dx, dy = OFFSETS[r]
        ref = fp.Reference()
        p = ref.GetPosition()
        ref.SetPosition(pcbnew.VECTOR2I(p.x + dx, p.y + dy))
        nudged += 1
    if r in HIDDEN_REFS:
        fp.Reference().SetVisible(False)
        hidden += 1

pcbnew.SaveBoard(f"{PROJECT_DIR}/supercart.kicad_pcb", board)
print(f"nudged {nudged} reference labels, hid {hidden}, saved {PROJECT_DIR}/supercart.kicad_pcb")
