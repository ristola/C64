#!/usr/bin/env python3
"""
Converts the ShackMate logo (branding/shackmate_logo_raw.png) into a real,
fabricatable KiCad silkscreen footprint - every element (the "SM" circuit
icon, the "ShackMate" wordmark, and the "Over 1 Million Projects
un-finished!" tagline) kept, nothing cropped.

Pipeline (documented here since none of this is a single KiCad command):
1. ImageMagick thresholds the source PNG to pure black/white, inverted so
   the logo's ink (white text + green circuit lines - both far brighter
   than the near-black background) becomes potrace's "foreground" convention
   (black-on-white). A single luminance threshold works because the source
   background is very dark (~#000516) and every logo element, both the
   white and the green paint, is far brighter -- confirmed by histogram
   before picking the threshold, not guessed.
2. potrace traces that bitmap into an SVG (branding/shackmate_logo.svg) -
   Bezier-curve paths, one <path> per connected ink region (52 of them:
   9 wordmark letters + tagline characters/dashes + the icon's pieces).
   Letters/shapes with a hole (the "a" counter, the icon's three ring
   dots) get that hole as a second subpath within the SAME <path>,
   opposite winding direction, per SVG's default nonzero fill rule.
3. This script parses each <path>'s subpaths (svg.path, flattening Bezier
   curves to line segments), classifies the largest-area subpath in each
   <path> element as the exterior and any others as holes (valid here
   since every shape in this logo is a single exterior with at most
   simple holes, no deeper nesting), and builds a shapely Polygon(exterior,
   holes) per connected component.
4. A polygon with holes has no direct KiCad equivalent (fp_poly is one
   plain point list, no holes) -- earcut triangulates each hole-having
   polygon into simple triangles, each emitted as its own fp_poly. Holeless
   shapes (most letters) are emitted directly as one fp_poly, no
   triangulation needed.
5. Coordinates: potrace's own SVG transform (translate + negative-Y scale)
   is applied first, landing everything in the same 0..1254 pixel-equivalent
   space as the source PNG; from there a single LOGO_WIDTH_MM/1254 scale
   maps to real board millimeters, keeping aspect ratio.

Requires: pip install kiutils svg.path shapely mapbox_earcut numpy
(installed into /tmp/kiutils_venv for this project - see other scripts'
own header comments for why kiutils needs its own venv here).
"""
import re
import xml.etree.ElementTree as ET

import numpy as np
import mapbox_earcut as earcut
from shapely.geometry import Polygon
from svg.path import parse_path
from svg.path.path import CubicBezier, Line, Move, Close, QuadraticBezier

from kiutils.footprint import Footprint, Pad
from kiutils.items.common import Position

SVG_PATH = "/Users/rts/Development/C64/hardware/supercart/branding/shackmate_logo.svg"
OUT_PATH = "/Users/rts/Development/C64/hardware/supercart/supercart.pretty/SHACKMATE_LOGO.kicad_mod"

# Overall logo width on the board, mm (source PNG is square, so height is
# the same). See the script's own stdout for what this implies for the
# smallest features (tagline text, icon ring width) - the board-integration
# step (gen_pcb.py) is a separate, deliberate decision, not baked in here.
LOGO_WIDTH_MM = 45.0
SRC_PX = 1254.0
# B.SilkS, not F.SilkS: the front silkscreen is already full (header text,
# both ICs, passives, connector) on this 58x60mm board; the back is
# completely empty (verified: only the layer-stackup declaration for
# B.SilkS exists in supercart.kicad_pcb, zero actual content), so that's
# where a 45mm logo can sit without touching anything else.
LAYER = "B.SilkS"

BEZIER_SAMPLES = 10  # points per curve segment - fine enough at this scale


def flatten_subpath(segments):
    """A list of svg.path segments (all belonging to one M..Z subpath) ->
    a flat list of (x, y) points in raw SVG-path units (pre-transform)."""
    pts = []
    for seg in segments:
        if isinstance(seg, Move):
            pts.append((seg.start.real, seg.start.imag))
        elif isinstance(seg, Line):
            pts.append((seg.end.real, seg.end.imag))
        elif isinstance(seg, Close):
            pass  # closing edge back to the subpath's start; polygon is implicitly closed
        elif isinstance(seg, (CubicBezier, QuadraticBezier)):
            for i in range(1, BEZIER_SAMPLES + 1):
                p = seg.point(i / BEZIER_SAMPLES)
                pts.append((p.real, p.imag))
        else:
            raise SystemExit(f"unhandled segment type: {type(seg)}")
    return pts


def split_subpaths(path_d):
    """svg.path's parse_path() returns one flat Path for the whole 'd'
    attribute; split it back into individual M..Z subpaths ourselves."""
    parsed = parse_path(path_d)
    subpaths = []
    current = []
    for seg in parsed:
        if isinstance(seg, Move) and current:
            subpaths.append(current)
            current = [seg]
        else:
            current.append(seg)
    if current:
        subpaths.append(current)
    return [flatten_subpath(s) for s in subpaths]


def shoelace_area(pts):
    s = 0.0
    n = len(pts)
    for i in range(n):
        x1, y1 = pts[i]
        x2, y2 = pts[(i + 1) % n]
        s += x1 * y2 - x2 * y1
    return s / 2


def transform_points(pts, translate_y, scale):
    # potrace's own <g transform="translate(0,H) scale(0.1,-0.1)">, applied
    # by hand since we bypassed any SVG-transform-aware renderer.
    return [(x * scale, translate_y + y * (-scale)) for (x, y) in pts]


tree = ET.parse(SVG_PATH)
root = tree.getroot()
ns = {"svg": "http://www.w3.org/2000/svg"}

g = root.find("svg:g", ns)
transform = g.attrib["transform"]
m = re.match(
    r"translate\(([-\d.]+),([-\d.]+)\)\s*scale\(([-\d.]+),([-\d.]+)\)", transform
)
tx, ty, sx, sy = (float(v) for v in m.groups())
assert sx == -sy and tx == 0, f"unexpected transform: {transform}"
scale = sx

paths = g.findall("svg:path", ns)
print(f"found {len(paths)} <path> elements")

polygons_simple = []  # list of point-lists (no holes)
polygons_holed = []  # list of (exterior, [holes])

for path_el in paths:
    d = path_el.attrib["d"]
    subpaths_raw = split_subpaths(d)
    subpaths = [transform_points(sp, ty, scale) for sp in subpaths_raw]
    if len(subpaths) == 1:
        polygons_simple.append(subpaths[0])
        continue
    # Multiple subpaths in one <path> = exterior + hole(s): the largest
    # |area| ring is the exterior (see module docstring).
    subpaths.sort(key=lambda pts: abs(shoelace_area(pts)), reverse=True)
    exterior, holes = subpaths[0], subpaths[1:]
    polygons_holed.append((exterior, holes))

print(f"simple shapes: {len(polygons_simple)}, holed shapes: {len(polygons_holed)}")

fp_polys = []  # list of point-lists to emit as fp_poly, in mm, board-local

def to_mm(pts):
    s = LOGO_WIDTH_MM / SRC_PX
    return [(x * s, y * s) for (x, y) in pts]

for pts in polygons_simple:
    fp_polys.append(to_mm(pts))

triangle_count = 0
for exterior, holes in polygons_holed:
    poly = Polygon(exterior, holes)
    if not poly.is_valid:
        poly = poly.buffer(0)
    # earcut wants one flat coordinate array + hole start-indices
    rings = [list(poly.exterior.coords)] if poly.geom_type == "Polygon" else []
    if poly.geom_type != "Polygon":
        raise SystemExit(f"buffer(0) repair produced non-Polygon: {poly.geom_type}")
    rings += [list(interior.coords) for interior in poly.interiors]
    flat = []
    ring_end_indices = []  # mapbox_earcut wants CUMULATIVE end index per ring
    for ring in rings:
        pts = ring[:-1] if ring[0] == ring[-1] else ring  # earcut wants open rings
        flat.extend(pts)
        ring_end_indices.append(len(flat))
    coords = np.array(flat, dtype=np.float64)
    tris = earcut.triangulate_float64(coords, np.array(ring_end_indices, dtype=np.uint32))
    tris = tris.reshape(-1, 3)
    for tri in tris:
        tri_pts = [tuple(coords[i]) for i in tri]
        fp_polys.append(to_mm(tri_pts))
        triangle_count += 1

print(f"triangles emitted for holed shapes: {triangle_count}")
print(f"total fp_poly items: {len(fp_polys)}")

fp = Footprint(entryName="SHACKMATE_LOGO")
fp.libId = "supercart:SHACKMATE_LOGO"
fp.layer = "B.Cu"  # nominal anchor layer for a back-side graphic-only footprint
fp.description = (
    "ShackMate logo (icon + wordmark + tagline), traced from branding/"
    "shackmate_logo_raw.png via potrace - see make_shackmate_logo_footprint.py"
)
fp.attributes.type = "other"
fp.attributes.boardOnly = True
fp.attributes.excludeFromPosFiles = True
fp.attributes.excludeFromBom = True

# Center the logo on its own footprint origin (board placement picks the
# real position later, in gen_pcb.py).
all_pts = [p for poly in fp_polys for p in poly]
cx = (min(p[0] for p in all_pts) + max(p[0] for p in all_pts)) / 2
cy = (min(p[1] for p in all_pts) + max(p[1] for p in all_pts)) / 2

for poly in fp_polys:
    # X mirrored around the shape's own center: KiCad stores back-layer
    # graphics pre-mirrored, so the artwork reads correctly once you
    # physically flip the board over to look at the true back face -
    # confirmed by rendering un-mirrored data with `kicad-cli pcb render
    # --side bottom` first and seeing the wordmark come out backwards.
    centered = [Position(-(x - cx), y - cy) for (x, y) in poly]
    fp.graphicItems.append(
        __import__("kiutils.items.fpitems", fromlist=["FpPoly"]).FpPoly(
            coordinates=centered,
            layer=LAYER,
            width=0,
            fill="solid",
        )
    )

fp.to_file(OUT_PATH)
print(f"wrote {OUT_PATH}")
print(f"logo bounding box: {LOGO_WIDTH_MM:.1f} x {LOGO_WIDTH_MM * (max(p[1] for p in all_pts)-min(p[1] for p in all_pts))/(max(p[0] for p in all_pts)-min(p[0] for p in all_pts)):.1f} mm")
