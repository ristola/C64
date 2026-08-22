#!/usr/bin/env python3
"""
Strips all tracks and vias from supercart.kicad_pcb, leaving footprint
placement untouched. Overwrites the board in place.

Run with KiCad's bundled Python, not a system one (see export_dsn.py):
  /Applications/KiCad/KiCad.app/Contents/Frameworks/Python.framework/Versions/3.9/bin/python3.9 unroute_all.py
"""
import wx
app = wx.App()
import pcbnew

PROJECT_DIR = "/Users/rts/Development/C64/hardware/supercart"
board = pcbnew.LoadBoard(f"{PROJECT_DIR}/supercart.kicad_pcb")
tracks = list(board.GetTracks())
for t in tracks:
    board.Remove(t)
pcbnew.SaveBoard(f"{PROJECT_DIR}/supercart.kicad_pcb", board)
print(f"removed {len(tracks)} tracks/vias, saved {PROJECT_DIR}/supercart.kicad_pcb")
