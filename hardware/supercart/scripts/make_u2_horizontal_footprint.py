#!/usr/bin/env python3
"""
Builds a custom "horizontal" SOP-44 footprint for U2 (AM29F080B) by rotating
every pad position+size and every graphic item in KiCad's real, stock
SOP-44_13.3x28.2mm_P1.27mm footprint 90 degrees CCW.

Why: that stock footprint's pads are real, verified-correct gull-wing pads
(1.85mm long x 0.6mm wide) drawn with the long axis running ACROSS the two
rows and the narrow (0.6mm) axis running ALONG the 1.27mm pitch -- correct
for a "vertical" placement (rows top/bottom, pitch along Y). Rotating that
whole footprint 90 degrees in KiCad (footprint-level Position.angle) swings
the pad's long 1.85mm axis onto the SAME axis as the 1.27mm pitch spacing,
which genuinely overlaps every adjacent pad by ~0.58mm -- confirmed via real
pcbnew pad bounding boxes 2026-08-21/22, not a DRC-checker false positive
(an earlier claim in this project that rotation-caused DRC violations here
were always false positives was WRONG for the 90/270-rotation case; it was
only verified against a full-board render, not real bounding-box math).

A plain footprint-level 90-degree rotation cannot fix this (it rotates
position AND pad shape together, which is exactly the problem). Instead
this script pre-bakes a real 90-degree CCW rotation, (x,y) -> (-y,x), into
pad positions, pad sizes, and every graphic item, producing a footprint
that is natively horizontal at 0 degrees -- narrow (0.6mm) pad dimension
stays aligned with the (now-horizontal) 1.27mm pitch, same as the stock
footprint's own vertical case.

FIXED 2026-08-22 (was a real, confirmed-with-the-datasheet bug, not just a
DRC nuisance): an earlier version of this script used a coordinate
TRANSPOSE (x,y) -> (y,x) instead of a rotation. A transpose is a
reflection (determinant -1), not a rotation (determinant +1) -- it swaps
pad width/height correctly (that part is orientation-independent) but
mirrors pad POSITIONS, which reverses the pin-1-to-pin-44 winding
direction around the package. Proven with the shoelace formula on the
stock footprint's four corner pads (1/22/23/44): the transpose flips the
signed area's sign; a true rotation (either direction) does not. The
practical effect: every pad number ended up on the physically-mirrored
opposite pad relative to where that real pin actually is on a chip
rotated in-plane (as opposed to flipped to view from the back) -- KiCad's
ratsnest/DRC don't catch this at all (they only see the pad numbers/nets
the schematic already assigned, which were correct), so the board would
have routed "cleanly" while wiring most of U2's real pins to the wrong
physical copper pad. Caught before Rev 0.2 routing, not after.
"""
from kiutils.footprint import Footprint

SRC = "/Applications/KiCad/KiCad.app/Contents/SharedSupport/footprints/Package_SO.pretty/SOP-44_13.3x28.2mm_P1.27mm.kicad_mod"
DST = "/Users/rts/Development/C64/hardware/supercart/supercart.pretty/SOP-44_28.2x13.3mm_P1.27mm_HORIZ.kicad_mod"


def rot_point(x, y):
    # 90 degrees CCW: (x,y) -> (-y,x). A true rotation (determinant +1),
    # unlike the old (x,y) -> (y,x) transpose (determinant -1) this
    # replaces -- see module docstring.
    return -y, x


fp = Footprint.from_file(SRC)
fp.entryName = "SOP-44_28.2x13.3mm_P1.27mm_HORIZ"
fp.description = (fp.description or "") + " -- rotated 90deg CCW for horizontal placement, see make_u2_horizontal_footprint.py"

for pad in fp.pads:
    pad.position.X, pad.position.Y = rot_point(pad.position.X, pad.position.Y)
    # Dimension swap is correct regardless of rotation direction (rotating
    # a rectangle 90 degrees swaps width/height either way).
    pad.size.X, pad.size.Y = pad.size.Y, pad.size.X

for g in fp.graphicItems:
    cls = type(g).__name__
    if cls == "FpLine":
        g.start.X, g.start.Y = rot_point(g.start.X, g.start.Y)
        g.end.X, g.end.Y = rot_point(g.end.X, g.end.Y)
    elif cls == "FpPoly":
        for pt in g.coordinates:
            pt.X, pt.Y = rot_point(pt.X, pt.Y)
    elif cls == "FpText":
        g.position.X, g.position.Y = rot_point(g.position.X, g.position.Y)
        if g.position.angle is not None:
            g.position.angle = (g.position.angle + 90) % 360
    elif cls == "FpCircle":
        g.center.X, g.center.Y = rot_point(g.center.X, g.center.Y)
        g.end.X, g.end.Y = rot_point(g.end.X, g.end.Y)
    elif cls == "FpArc":
        g.start.X, g.start.Y = rot_point(g.start.X, g.start.Y)
        g.mid.X, g.mid.Y = rot_point(g.mid.X, g.mid.Y)
        g.end.X, g.end.Y = rot_point(g.end.X, g.end.Y)
    else:
        raise SystemExit(f"unhandled graphic item type: {cls}")

fp.to_file(DST)
print(f"wrote {DST}")
print(f"pads: {len(fp.pads)}, graphic items: {len(fp.graphicItems)}")
