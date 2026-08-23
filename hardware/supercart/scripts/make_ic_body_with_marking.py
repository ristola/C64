#!/usr/bin/env python3
"""
Builds a custom VRML (.wrl) 3D body for an IC footprint with real laser-
marking-style text raised above the surface -- used for U1 (ATF22V10C) and
U2 (AM29F080B) since neither is achievable any other way, verified before
building this:
  - KiCad's 3D renderer does NOT wrap 2D footprint text (F.SilkS/F.Fab)
    onto a 3D model's surface at all -- confirmed by rendering a footprint
    with F.Fab text and no 3D model: the text shows as a flat 2D overlay,
    not on any extruded body.
  - KiCad's VRML loader does NOT support the VRML97 `Text` geometry node --
    confirmed by rendering a hand-built .wrl with a Box + Text node: the
    box rendered, the text silently did not.
  - No real SO-44 (13.3x28.2mm) 3D model exists anywhere in KiCad's bundled
    library (checked the whole install) -- U2 was previously a PSOP-44
    substitute model non-uniformly scaled (0.787x/1.038x) to hit the right
    bounding box, which visibly distorts its rounded corners/bevel detail.
  - Real chip-marking text therefore has to be actual mesh geometry (like
    the ShackMate logo elsewhere in this project), not a 2D layer or a
    Text node.

Unit convention, verified empirically (not assumed): KiCad's VRML importer
treats raw model coordinates as 0.1in units (1 unit = 2.54mm), a legacy
convention -- confirmed by rendering a plain 10x10x2 unit box on a known
100x100mm board and measuring it at ~25.3mm (10 * 2.54 = 25.4, matching
within pixel-measurement error). This script authors geometry directly in
real mm and relies on the *footprint's* model scale (1/2.54 per axis,
set in gen_pcb.py) to convert back down -- NOT scaled in this file itself.

Pipeline for the text (reuses make_shackmate_logo_footprint.py's approach):
ImageMagick renders each line to a thresholded B/W bitmap -> potrace traces
to SVG -> svg.path parses/flattens Bezier curves -> shapely classifies
holes by largest-ring-per-<path>-element -> mapbox_earcut triangulates.
Output here is VRML IndexedFaceSet triangles instead of KiCad fp_poly,
raised flat at Z=body_height+RAISE_MM (a thin plate just above the body
surface, not a fully walled extrusion -- much simpler to build correctly,
and visually reads as printed/lasered marking at this render scale).

Requires: pip install kiutils svg.path shapely mapbox_earcut numpy;
ImageMagick (`magick`) and potrace on PATH.
"""
import os, re, subprocess, sys
import xml.etree.ElementTree as ET

import numpy as np
import mapbox_earcut as earcut
from shapely.geometry import Polygon
from svg.path import parse_path
from svg.path.path import CubicBezier, Line, Move, Close, QuadraticBezier

BEZIER_SAMPLES = 8
RAISE_MM = 0.06   # how far the text plate sits above the body surface
TEXT_THICKNESS_MM = 0.0  # flat plate, not a walled solid -- see header


def render_text_triangles(text, target_width_mm, workdir, tag):
    """Text string -> list of (x,y) mm triangles (2D, unplaced in Z),
    centered on (0,0), sized to target_width_mm wide."""
    png = f"{workdir}/{tag}.png"
    bw = f"{workdir}/{tag}_bw.pbm"
    svg = f"{workdir}/{tag}.svg"
    subprocess.run([
        "magick", "-background", "black", "-fill", "white",
        "-font", "Helvetica-Bold", "-pointsize", "200",
        f"label:{text}", png
    ], check=True)
    subprocess.run([
        "magick", png, "-colorspace", "Gray", "-threshold", "50%", bw
    ], check=True)
    subprocess.run(["potrace", bw, "-s", "-o", svg, "-a", "1", "-t", "3"], check=True)

    tree = ET.parse(svg)
    root = tree.getroot()
    ns = {"svg": "http://www.w3.org/2000/svg"}
    g = root.find("svg:g", ns)
    transform = g.attrib["transform"]
    m = re.match(r"translate\(([-\d.]+),([-\d.]+)\)\s*scale\(([-\d.]+),([-\d.]+)\)", transform)
    tx, ty, sx, sy = (float(v) for v in m.groups())
    assert sx == -sy and tx == 0
    scale = sx

    def flatten_subpath(segments):
        pts = []
        for seg in segments:
            if isinstance(seg, Move):
                pts.append((seg.start.real, seg.start.imag))
            elif isinstance(seg, Line):
                pts.append((seg.end.real, seg.end.imag))
            elif isinstance(seg, Close):
                pass
            elif isinstance(seg, (CubicBezier, QuadraticBezier)):
                for i in range(1, BEZIER_SAMPLES + 1):
                    p = seg.point(i / BEZIER_SAMPLES)
                    pts.append((p.real, p.imag))
        return pts

    def split_subpaths(path_d):
        parsed = parse_path(path_d)
        subpaths, current = [], []
        for seg in parsed:
            if isinstance(seg, Move) and current:
                subpaths.append(current)
                current = [seg]
            else:
                current.append(seg)
        if current:
            subpaths.append(current)
        return [flatten_subpath(s) for s in subpaths]

    def shoelace(pts):
        s = 0.0
        n = len(pts)
        for i in range(n):
            x1, y1 = pts[i]; x2, y2 = pts[(i + 1) % n]
            s += x1 * y2 - x2 * y1
        return s / 2

    def transform_pts(pts):
        return [(x * scale, ty + y * -scale) for x, y in pts]

    paths = g.findall("svg:path", ns)
    if not paths:
        return []  # e.g. blank line

    simple, holed = [], []
    for path_el in paths:
        subpaths = [transform_pts(sp) for sp in split_subpaths(path_el.attrib["d"])]
        if len(subpaths) == 1:
            simple.append(subpaths[0])
        else:
            subpaths.sort(key=lambda p: abs(shoelace(p)), reverse=True)
            holed.append((subpaths[0], subpaths[1:]))

    all_pts_raw = [p for poly in simple for p in poly] + [p for ext, holes in holed for p in ext]
    x0 = min(p[0] for p in all_pts_raw); x1 = max(p[0] for p in all_pts_raw)
    raw_w = x1 - x0
    s = target_width_mm / raw_w
    cx = (x0 + x1) / 2
    ys = [p[1] for p in all_pts_raw]
    cy = (min(ys) + max(ys)) / 2

    def to_mm(pts):
        return [((x - cx) * s, -(y - cy) * s) for x, y in pts]  # flip Y: image-down -> model-up

    triangles = []
    for poly in simple:
        pts = to_mm(poly)
        poly_geom = Polygon(pts)
        if not poly_geom.is_valid:
            poly_geom = poly_geom.buffer(0)
        if poly_geom.geom_type != "Polygon" or len(poly_geom.exterior.coords) < 4:
            continue
        ring = list(poly_geom.exterior.coords)[:-1]
        coords = np.array(ring, dtype=np.float64)
        tris = earcut.triangulate_float64(coords, np.array([len(ring)], dtype=np.uint32)).reshape(-1, 3)
        for tri in tris:
            triangles.append([tuple(coords[i]) for i in tri])

    for ext, holes in holed:
        ext_mm = to_mm(ext)
        holes_mm = [to_mm(h) for h in holes]
        poly_geom = Polygon(ext_mm, holes_mm)
        if not poly_geom.is_valid:
            poly_geom = poly_geom.buffer(0)
        if poly_geom.geom_type != "Polygon":
            continue
        rings = [list(poly_geom.exterior.coords)] + [list(i.coords) for i in poly_geom.interiors]
        flat, ring_end = [], []
        for ring in rings:
            pts = ring[:-1] if ring[0] == ring[-1] else ring
            flat.extend(pts)
            ring_end.append(len(flat))
        coords = np.array(flat, dtype=np.float64)
        tris = earcut.triangulate_float64(coords, np.array(ring_end, dtype=np.uint32)).reshape(-1, 3)
        for tri in tris:
            triangles.append([tuple(coords[i]) for i in tri])

    return triangles


def build_wrl(body_w, body_l, body_h, text_lines, text_width_mm, line_gap_mm, out_path, workdir):
    os.makedirs(workdir, exist_ok=True)
    all_tris_3d = []
    n = len(text_lines)
    total_h = n * line_gap_mm
    for i, line in enumerate(text_lines):
        y_center = (n - 1) / 2 * line_gap_mm - i * line_gap_mm
        tris = render_text_triangles(line, text_width_mm, workdir, f"line{i}")
        for tri in tris:
            all_tris_3d.append([(x, y + y_center, body_h + RAISE_MM) for x, y in tri])

    points, coord_index = [], []
    for tri in all_tris_3d:
        base = len(points)
        points.extend(tri)
        coord_index.extend([base, base + 1, base + 2, -1])

    def fmt_points(pts):
        return " ".join(f"{x:.4f} {y:.4f} {z:.4f}," for x, y, z in pts)

    def fmt_index(idx):
        return " ".join(f"{v}," for v in idx)

    wrl = f"""#VRML V2.0 utf8

Transform {{
  children [
    Shape {{
      appearance Appearance {{
        material Material {{ diffuseColor 0.13 0.13 0.13 specularColor 0.2 0.2 0.2 shininess 0.3 }}
      }}
      geometry Box {{ size {body_w:.3f} {body_l:.3f} {body_h:.3f} }}
    }}
    Transform {{
      translation 0 0 {-body_h/2:.4f}
      children Shape {{
        appearance Appearance {{
          material Material {{ diffuseColor 0.88 0.88 0.85 emissiveColor 0.35 0.35 0.33 }}
        }}
        geometry IndexedFaceSet {{
          solid FALSE
          coord Coordinate {{ point [ {fmt_points(points)} ] }}
          coordIndex [ {fmt_index(coord_index)} ]
        }}
      }}
    }}
  ]
}}
"""
    with open(out_path, "w") as f:
        f.write(wrl)
    print(f"wrote {out_path} ({len(all_tris_3d)} text triangles)")


if __name__ == "__main__":
    # U1 -- ATF22V10C-7SX, SOIC-24W real body (7.5 x 15.4mm, matches the
    # stock footprint exactly). Thickness: JEDEC MS-013 wide-body SOIC max
    # body thickness (2.65mm) -- a real, citable standard spec, not a guess,
    # since the stock STEP model's own exact figure isn't easily queryable
    # via pcbnew's Python API.
    build_wrl(
        body_w=7.5, body_l=15.4, body_h=2.65,
        text_lines=["ATF22V10C", "-7SX", "EEPLD"],
        text_width_mm=6.0, line_gap_mm=3.6,
        out_path="/Users/rts/Development/C64/hardware/supercart/supercart.pretty/U1_ATF22V10C_marked.wrl",
        workdir="/tmp/ic_marking_u1",
    )
    # U2 -- AM29F080B-90S (corrected from "-90PD", not a real ordering code
    # for this part -- see PINOUTS.md: only E=TSOP or S=SO exist), real
    # SO-44 body. body_w/body_l swapped vs the datasheet's own D/E1 naming
    # (28.2 x 13.3, not 13.3 x 28.2) to match U2's actual board orientation:
    # it uses the HORIZ footprint (scripts/make_u2_horizontal_footprint.py),
    # long axis (28.2mm) along X, not Y.
    # text_width_mm kept close to U1's (not scaled up proportional to the
    # much wider body): line HEIGHT scales with width (fixed aspect ratio
    # per rendered line), so a naively "proportional" 22mm width made each
    # line ~13mm tall -- more than U2's own 13.3mm body_l, causing all 3
    # lines to overlap into an unreadable mess. U2's text strings are
    # nearly the same character count as U1's ("AM29F080B"/"ATF22V10C" are
    # both 9 chars), so a similar width is what actually fits.
    build_wrl(
        body_w=28.2, body_l=13.3, body_h=2.65,
        text_lines=["AM29F080B", "-90S", "1MB FLASH"],
        text_width_mm=9.0, line_gap_mm=3.8,
        out_path="/Users/rts/Development/C64/hardware/supercart/supercart.pretty/U2_AM29F080B_marked.wrl",
        workdir="/tmp/ic_marking_u2",
    )
