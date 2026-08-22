#!/usr/bin/env python3
"""
Exports supercart.kicad_pcb to a Specctra .dsn file for FreeRouting.

kicad-cli has no DSN export at all (checked: not in `pcb export`'s
subcommand list) -- this has to go through pcbnew's own Python scripting API
(bundled inside KiCad.app, NOT the same Python/kiutils used by the other
gen_*.py scripts in this folder). ExportSpecctraDSN needs a wx.App to exist
first or it segfaults/asserts; that's the only non-obvious part here.

Run with KiCad's bundled Python, not a system one:
  /Applications/KiCad/KiCad.app/Contents/Frameworks/Python.framework/Versions/3.9/bin/python3.9 export_dsn.py
"""
import wx
app = wx.App()
import pcbnew

PROJECT_DIR = "/Users/rts/Development/C64/hardware/supercart"
board = pcbnew.LoadBoard(f"{PROJECT_DIR}/supercart.kicad_pcb")
ok = pcbnew.ExportSpecctraDSN(board, f"{PROJECT_DIR}/supercart.dsn")
if not ok:
    raise SystemExit(
        "ExportSpecctraDSN returned False. Known cause hit once already: any "
        "footprint with an empty/invalid Reference silently breaks this -- "
        "check `f.GetReference()` for every footprint first. Also known to be "
        "generally flaky in some KiCad builds independent of board content."
    )
print(f"wrote {PROJECT_DIR}/supercart.dsn")
