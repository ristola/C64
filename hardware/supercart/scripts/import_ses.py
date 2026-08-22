#!/usr/bin/env python3
"""
Imports a FreeRouting-produced supercart.ses back into supercart.kicad_pcb,
overwriting it in place with the routed result.

Run FreeRouting between export_dsn.py and this script:
  java -jar tools/freerouting-2.3.0.jar -de supercart.dsn -do supercart.ses -mp 10 -mt 1
(tools/freerouting-*.jar is gitignored -- download the platform-independent
.jar from https://github.com/freerouting/freerouting/releases into
hardware/supercart/tools/ if it's missing. Needs a JDK; this project used
`brew install openjdk`, called via its full keg-only path since it isn't
symlinked onto PATH: /opt/homebrew/opt/openjdk/bin/java)

-mt 1 (single-threaded optimization) matters: FreeRouting's own multi-threaded
optimizer prints "Multi-threaded route optimization is broken and it is known
to generate clearance violations" and recommends -mt 1 explicitly.

Note: FreeRouting's own end-of-run violation count (checked against a real
run: it reported 44) does NOT match what KiCad's own DRC finds afterward
(checked: only 1 was real, the rest are FreeRouting's own internal/stricter
bookkeeping that doesn't correspond to actual clearance problems in the
exported geometry) -- always re-check with `kicad-cli pcb drc` on the
imported result rather than trusting FreeRouting's own violation count.

Run with KiCad's bundled Python, not a system one (see export_dsn.py).
"""
import wx
app = wx.App()
import pcbnew

PROJECT_DIR = "/Users/rts/Development/C64/hardware/supercart"
board = pcbnew.LoadBoard(f"{PROJECT_DIR}/supercart.kicad_pcb")
ok = pcbnew.ImportSpecctraSES(board, f"{PROJECT_DIR}/supercart.ses")
if not ok:
    raise SystemExit(
        "ImportSpecctraSES returned False. Seen once already on a second "
        "FreeRouting run in the same session with no obvious cause -- if this "
        "happens, just re-run the export/route/import sequence from scratch."
    )
pcbnew.SaveBoard(f"{PROJECT_DIR}/supercart.kicad_pcb", board)
print(f"routed board saved to {PROJECT_DIR}/supercart.kicad_pcb")
