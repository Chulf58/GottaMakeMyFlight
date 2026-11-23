"""Build the airport site (road and forecourt paving, no terminal) from the terminal shell.

Run from WSL (Blender is a Windows program, so it sees Windows paths):

    "/mnt/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background \
        --factory-startup --python \
        'C:\\Users\\chulf\\Gotta-make-my-flight\\tools\\blender\\terminal_site\\build_terminal_site.py'

Reads game/assets/buildings/tp_airport_shell.glb (written by
tools/blender/terminal_shell/build_terminal_shell.py, only read here) and writes
game/assets/buildings/tp_airport_site.glb and its .import.

Decision player-built-terminal-technical-design-site-plot-indoor-mask-passenger-eligibility,
point 1: the player builds the terminal on a plot (x -43..43, z -100..-60), so the site
keeps the shell's Road and the outer Lot paving and drops the building. All numbers are
Godot world coordinates with the asset at (0, 0, -80), as main.tscn places the shell
(Godot x = Blender x, Godot y = Blender z, Godot z = -Blender y - 80).

What it keeps and drops (measured on the shell, see the census this script prints):
- Road: kept as it is (same transform, every triangle at the same position) except the
  sidewalk tile accents, the flat islands 3 mm over the sidewalk (y 0.2031) beside the plot,
  which read as dark checker patches (user ruling buildable-outline-keeps-a-constant-on-
  screen-width-at-every-zoom, point 2, which relaxes 'Road identical' for this change only).
  The written file's Road is compared with the shell file's Road: same world transform, and
  its triangles are exactly the shell's minus the accent triangles; the build fails otherwise.
- Lot: split into islands and filtered by geometry, because the shell exporter put the
  building's ground slab and two letter signs in Lot:
    slab:  an island inside the old slab box (x -34.2..33.2, z -95.5..-64.1, 5 cm
           tolerance) that reaches y 0.29 or higher (the slab top is at 0.30);
    sign:  any island reaching above y 0.35 (the paving's highest part is 0.26; the two
           signs over Porch_2 and Porch_6 sit at y 4.08..5.01).
  The plot itself is paved flat at y 0.2 (PAVE_Y), so the player's floor can sit 2 cm
  above it anywhere on the plot (grid y 0.22) with no gap under it and nothing poking
  through it. So the filter also drops, from Lot (all of which lies on the plot):
    raised block: an island reaching above y 0.21 (the 1-2 m paving blocks, tops 0.219,
           0.238, 0.257);
    dip:   an island lying wholly below y 0.15 (the two dips at x -12..12 by the old
           entrances, landside z -64..-60 and airside z -100..-96, and their markings);
    dip kerb: an upright island within x -12.35..12.35 (the dips' kerbs);
    inner skirt: the paving's upright edge faces at x -40 and 40, which the fill buries;
    tile accent: a flat island lying 3 mm above the pads (y 0.2031), the dark checker
           tile patches, which read as a glitch on the empty plot (decision
           buildable-land-shows-as-an-outline-only-in-build-mode-the-da).
    north skirt: the Toon paving's upright edge faces along z -100 and round the back
           dip's flared mouth (z -100..-98), which now lie inside the grown site.
    south skirt: the Toon paving's upright edge faces along z -60 behind Road's sidewalk.
  It keeps the paving pads at y 0.2 and drops those south skirts so owned plots do not
  collide coplanarly with Road's sidewalk at z -60; fill_plot() closes only the uncovered
  south spans (x -128..-40, -12..12, 40..128).
  fill_plot() then paves the strips x -43..-40 and 40..43 that
  the Toon paving stops short of and the two dips (with the airside dip's flared mouth),
  each top face on the UV of the nearest existing pad corner, and closes the new edges
  with skirts down to y 0.
- Grown site: the terminal site's grid runs 86 x 150 m from z -210 (terminal_site.tres), so
  the plane parks north of the first plot. fill_plot() also paves x -43..43, z -210..-100
  flat at PAVE_Y in the pads' swatch (user ruling plane-guard-area-shows-only-in-build-mode-
  the-site-paving-ex, point 2: "the site's grey paving extends north to the grown site edge
  at z -210"). The re-read proves the whole grown site flat (up-facing heights only 0.2) and
  covered (a 0.25 m sample grid over it, every sample on paving), so the pads run on
  unbroken under the dropped accents and into the north paving.
- Side land: the grid is 256 m wide, x -128..128 (terminal_site.tres; decision land-west-and-
  east-of-the-site-becomes-buyable-that-side-s-t), so fill_plot() also paves the side land
  x -128..-43 and 43..128, z -210..-60, flat at PAVE_Y, and the grown site's outer skirts
  move out to x -128 and 128.
- Land plots: the paving is cut into one object per land plot, Lot_<column>_<row>, on the
  plot lines LandPlots draws (game/build/land_plots.gd, SiteDefinition.plot_columns: four
  side columns of 22, 21, 21 and 21 m from x -128, the first site's 22, 22, 21 and 21 m from
  x -43, four side columns of 22, 21, 21 and 21 m from x 43, six rows of 25 m from z -210;
  ruling land-plots-are-near-even-columns-of-22-22-21-and-21-m-by-25), so the game shows the paving only on the plots the player owns
  (OwnedPaving; user ruling site-paving-covers-only-the-owned-land-plots-and-grows-as-ea,
  which replaces point 2 above). split_plots() gives every side a plot shares with another
  plot a kerb object of its own, Lot_<column>_<row>_<N, E, S or W>, a skirt from PAVE_Y down to
  SKIRT_FOOT_Y, under the grass (main.tscn's Ground, y -0.1). The game shows a kerb only where
  its plot is owned and the plot across is not, so an owned plot next to grass reads as a kerbed
  slab and touching owned plots pave as one surface (user ruling touching-owned-land-plots-pave-
  as-one-seamless-surface-no-lin). The re-read proves
  every plot's top lies inside its own plot and reaches all four of its edges.
- Poles: dropped. Every Poles island stands under the landside canopy between x -25.85 and
  25.85 and is part of its supports and lamps; the canopy goes, so they go.
- Upper, Canopy, Facade, Porch_1..8, Door_1..8, Doorway_1..8, Lights (all of it): dropped.

The node tree written: TP_Airport_Site_ROOT > Road, Lot_0_0 .. Lot_11_5 and their kerbs Lot_<c>_<r>_<N|E|S|W>.
The build fails unless the written file holds exactly those, with the shell's two atlases
(TP_Atlas_Simple_1A_D on Road, TP_Atlas_1A_D on each Lot_, both on the one image tp_atlas_1a_d, as in the
shell and the Toon source) bound, and no geometry above y 0.35
or inside the old slab box above y 0.25.
"""

import hashlib
import json
import math
import os
import struct
import sys
from collections import Counter

import bmesh
import bpy
from mathutils import Matrix, Quaternion, Vector

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
SHELL = os.path.join(REPO, "game", "assets", "buildings", "tp_airport_shell.glb")
OUT = os.path.join(REPO, "game", "assets", "buildings", "tp_airport_site.glb")
REPORT_DIR = os.path.join(REPO, "tools", "blender", "out", "terminal-site")
OFFSET_Z = -80.0
SLAB_BOX = (-34.2, 33.2, -95.5, -64.1)  # x0, x1, z0, z1 of the old ground slab
SLAB_TOL = 0.05
SLAB_MIN_Y = 0.29  # an island in the slab box reaching this high is the slab
SIGN_MIN_Y = 0.35  # any island reaching above this is a sign or facade remnant
PLOT = (-43.0, 43.0, -100.0, -60.0)  # x0, x1, z0, z1 of the first plot (the Toon paving)
GROWN = (-128.0, 128.0, -210.0, -60.0)  # x0, x1, z0, z1 of the grown site (terminal_site.tres grid)
CENTRE_X = (-43.0, 43.0)  # x0, x1 of the first site; side land lies west and east of it
PAVE_Y = 0.2  # the Toon paving pads' top; the plot is paved flat at this height
ROAD_Y = 0.10  # unified carriageway asphalt top across site road, extensions, and aprons
ROAD_ASPHALT_UV = (0.5047, 0.9385)
ROAD_SIDEWALK_UV = (0.5337, 0.9825)
ROAD_FLAT_MAT = "TP_Atlas_Simple_Road_Flat"
PAVE_MAX_Y = 0.21  # above this an island is a raised paving block (tops 0.219, 0.238, 0.257)
ACCENT_MIN_LIFT = 0.001  # a flat island wholly this far over PAVE_Y is a tile accent (y 0.2031)
DIP_MAX_Y = 0.15  # below this an island is part of a dip (pads 0.10, markings 0.1065)
DIP_HALF_X = 12.0  # the dips run x -12..12
LOT_HALF_X = 40.0  # the Toon paving stops at x -40 and 40
BACK_FLARE = ((14.0, -100.0), (13.0, -99.73), (12.27, -99.0), (12.0, -98.0))  # east half; west mirrors
KEEP = ("Road", "Lot")
# LandPlots' plot lines on the 256 x 150 site grid (game/build/land_plots.gd).
COLUMN_X = (-128.0, -106.0, -85.0, -64.0, -43.0, -21.0, 1.0, 22.0, 43.0, 65.0, 86.0, 107.0, 128.0)
ROW_Z = (-210.0, -185.0, -160.0, -135.0, -110.0, -85.0, -60.0)
SKIRT_FOOT_Y = -0.12  # a plot-edge skirt reaches 2 cm under the grass (y -0.1)
PLOT_NAMES = tuple("Lot_%d_%d" % (c, r) for r in range(len(ROW_Z) - 1) for c in range(len(COLUMN_X) - 1))
SHORT_ROWS = ("raised block", "dip", "tile accent")  # census lists only the first 3 of these
ROOT = "TP_Airport_Site_ROOT"

report = []


def log(*a):
    print("SITE", *a, flush=True)


def rep(line):
    report.append(line)


def die(msg):
    for line in report:
        print("CENSUS", line, flush=True)
    print("SITE_FAILED", msg, flush=True)
    sys.exit(1)


def g(v):
    """Blender world -> Godot world with the (0, 0, -80) placement."""
    return Vector((v.x, v.z, -v.y + OFFSET_Z))


def bbox(points):
    lo = Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points)))
    hi = Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points)))
    return lo, hi


def fmt(lo, hi):
    return "x %.2f..%.2f y %.2f..%.2f z %.2f..%.2f" % (lo.x, hi.x, lo.y, hi.y, lo.z, hi.z)


def census(title):
    rep(title)
    for o in sorted(bpy.context.scene.objects, key=lambda o: o.name):
        parent = o.parent.name if o.parent else None
        if o.type != "MESH":
            rep("  %-24s (empty) parent %s" % (o.name, parent))
            continue
        lo, hi = bbox([g(o.matrix_world @ v.co) for v in o.data.vertices])
        tris = sum(len(p.vertices) - 2 for p in o.data.polygons)
        rep("  %-24s verts %5d tris %5d parent %-22s %s" % (o.name, len(o.data.vertices), tris, parent, fmt(lo, hi)))


def islands(bm):
    seen = set()
    out = []
    for f in bm.faces:
        if f.index in seen:
            continue
        seen.add(f.index)
        stack, comp = [f], []
        while stack:
            c = stack.pop()
            comp.append(c)
            for e in c.edges:
                for n in e.link_faces:
                    if n.index not in seen:
                        seen.add(n.index)
                        stack.append(n)
        out.append(comp)
    return out


def classify(lo, hi):
    """One class per Lot island, by first match, from its Godot world bounds."""
    x0, x1, z0, z1 = SLAB_BOX
    in_slab = (lo.x >= x0 - SLAB_TOL and hi.x <= x1 + SLAB_TOL and lo.z >= z0 - SLAB_TOL and hi.z <= z1 + SLAB_TOL)
    upright = hi.y - lo.y > 0.05
    if hi.y > SIGN_MIN_Y:
        return "sign"
    if in_slab and hi.y >= SLAB_MIN_Y:
        return "slab"
    if hi.y > PAVE_MAX_Y:
        return "raised block"
    if hi.y < DIP_MAX_Y:
        return "dip"
    if upright and lo.x >= -DIP_HALF_X - 0.35 and hi.x <= DIP_HALF_X + 0.35:
        return "dip kerb"
    if upright and hi.x - lo.x < 0.01 and abs(abs(lo.x) - LOT_HALF_X) < 0.01:
        return "inner skirt"
    if upright and abs(lo.z - PLOT[2]) < 0.01 and hi.z <= BACK_FLARE[-1][1] + 0.01:
        return "north skirt"
    if upright and abs(lo.z - PLOT[3]) < 0.01 and abs(hi.z - PLOT[3]) < 0.01:
        return "south skirt"
    if not upright and lo.y > PAVE_Y + ACCENT_MIN_LIFT:
        return "tile accent"
    return "keep"


def keep_kind(lo, hi, area):
    """A coarse name for a kept island, for the census only."""
    if area >= 100.0:
        return "pad y %.2f" % hi.y
    if hi.y - lo.y > 0.05:
        return "outer skirt z %.0f" % (lo.z if lo.z < -80 else hi.z)
    return "flat accent y %.4f" % hi.y


def filter_lot(lot):
    """Drop the building, and every Lot island that keeps the plot from being flat paving
    at PAVE_Y. Returns the measured UVs the new faces take: the pad loops (Godot position,
    uv) and the UV of the paving's edge skirt at x -40."""
    mw = lot.matrix_world
    bm = bmesh.new()
    bm.from_mesh(lot.data)
    bm.faces.ensure_lookup_table()
    uvl = bm.loops.layers.uv.active
    comps = islands(bm)
    drop = set()
    kinds = {}
    dropped = {}
    skirt_uv = None
    pad_loops = []
    for k, comp in enumerate(comps):
        lo, hi = bbox([g(mw @ v.co) for f in comp for v in f.verts])
        c = classify(lo, hi)
        tris = sum(len(f.verts) - 2 for f in comp)
        if c == "keep":
            kind = keep_kind(lo, hi, sum(f.calc_area() for f in comp))
            kinds.setdefault(kind, [0, 0])
            kinds[kind][0] += 1
            kinds[kind][1] += tris
            if kind.startswith("pad"):
                pad_loops += [(g(mw @ lp.vert.co), tuple(lp[uvl].uv)) for f in comp for lp in f.loops]
            continue
        if c == "inner skirt" and lo.x < 0:
            skirt_uv = tuple(comp[0].loops[0][uvl].uv)
        drop.update(f.index for f in comp)
        dropped.setdefault(c, []).append((k, len(comp), tris, fmt(lo, hi)))
    n_drop = sum(len(v) for v in dropped.values())
    rep("Lot islands %d: kept %d, dropped %d" % (len(comps), len(comps) - n_drop, n_drop))
    for c in sorted(dropped):
        rows = dropped[c]
        rep("  dropped %-12s islands %4d tris %5d" % (c, len(rows), sum(r[2] for r in rows)))
        for k, nf, nt, box in rows if c not in SHORT_ROWS else rows[:3]:
            rep("    island %4d faces %3d tris %3d %s" % (k, nf, nt, box))
        if c in SHORT_ROWS and len(rows) > 3:
            rep("    ... and %d more like these" % (len(rows) - 3))
    for kind in sorted(kinds):
        rep("  kept    %-24s islands %4d tris %5d" % (kind, kinds[kind][0], kinds[kind][1]))
    want = ["dip", "dip kerb", "inner skirt", "north skirt", "raised block", "sign", "slab", "south skirt", "tile accent"]
    if sorted(dropped) != want:
        die("expected the filter to drop %s, got %s" % (want, sorted(dropped)))
    if skirt_uv is None or not pad_loops:
        die("no paving pad or edge skirt to sample a UV from")
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.index in drop], context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bm.to_mesh(lot.data)
    bm.free()
    lot.data.update()
    return pad_loops, skirt_uv


def is_accent_tri(tri):
    """A flat triangle wholly at tile-accent height (y 0.2031): over PAVE_Y by
    ACCENT_MIN_LIFT and under PAVE_MAX_Y. Road markings lie at 0.1065..0.1344 and the
    sidewalk tops at 0.2, so only the accents match."""
    return all(PAVE_Y + ACCENT_MIN_LIFT < p.y <= PAVE_MAX_Y for p in tri)


def in_tri_xz(px, pz, a, b, c):
    """Whether (px, pz) lies in triangle abc seen from straight above."""
    d1 = (px - b.x) * (a.z - b.z) - (a.x - b.x) * (pz - b.z)
    d2 = (px - c.x) * (b.z - c.z) - (b.x - c.x) * (pz - c.z)
    d3 = (px - a.x) * (c.z - a.z) - (c.x - a.x) * (pz - a.z)
    neg = d1 < -1e-9 or d2 < -1e-9 or d3 < -1e-9
    pos = d1 > 1e-9 or d2 > 1e-9 or d3 > 1e-9
    return not (neg and pos)


def tri_key(tri):
    return tuple(sorted(tuple(round(c, 4) for c in p) for p in tri))


def filter_road(road):
    """Drop the Road's sidewalk tile accents (the dark checker patches beside the plot),
    every island all of whose triangles are accent triangles, and keep the rest of the Road
    as it is. Returns the number of triangles dropped."""
    mw = road.matrix_world
    bm = bmesh.new()
    bm.from_mesh(road.data)
    bm.faces.ensure_lookup_table()
    drop, rows = [], []
    for comp in islands(bm):
        tris = [tuple(g(mw @ v.co) for v in f.verts) for f in comp]
        if all(is_accent_tri(t) for t in tris):
            lo, hi = bbox([p for t in tris for p in t])
            drop += comp
            rows.append((len(comp), sum(len(f.verts) - 2 for f in comp), fmt(lo, hi)))
    n_tris = sum(r[1] for r in rows)
    rep("Road islands dropped as sidewalk tile accents: %d (tris %d)" % (len(rows), n_tris))
    for nf, nt, box in rows:
        rep("    accent faces %d tris %d %s" % (nf, nt, box))
    if not rows:
        die("expected sidewalk tile accents on the Road, found none")
    bmesh.ops.delete(bm, geom=drop, context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bm.to_mesh(road.data)
    bm.free()
    road.data.update()
    return n_tris


def _gn_of(mw, face):
    wn = (mw.to_3x3() @ face.normal).normalized()
    return Vector((wn.x, wn.z, -wn.y))


def seamless_road(road):
    """Make Road's carriageway seamless with Road_Ext and parking aprons:
    1. Delete x = +-43.0 end-cap faces where Road meets Road_Ext.
    2. Bisect y = 0.0..0.20 outer sidewalk skirts at y = ROAD_Y so lower buried skirts
       (y = 0.0..0.10) use outline-free TP_Atlas_Simple_Road_Flat under aprons.
    3. Assign TP_Atlas_Simple_Road_Flat to carriageway asphalt, road paint/crosswalk
       markings (y <= 0.15), flat y = PAVE_Y sidewalk tops, and lower skirts; keep
       TP_Atlas_Simple_1A_D on raised kerbs, outer upper edges, and 3D fixtures.
    4. Flatten asphalt vertex normals to strict world (0, 1, 0), unify asphalt UV to
       ROAD_ASPHALT_UV, and unify south sidewalk top UV to ROAD_SIDEWALK_UV."""
    mw = road.matrix_world
    mwi = mw.inverted()
    base_mat = road.data.materials[0]
    flat_mat = bpy.data.materials.get(ROAD_FLAT_MAT)
    if flat_mat is None:
        flat_mat = base_mat.copy()
        flat_mat.name = ROAD_FLAT_MAT
    if len(road.data.materials) < 2:
        road.data.materials.append(flat_mat)
    else:
        road.data.materials[1] = flat_mat

    if hasattr(road.data, "has_custom_normals") and road.data.has_custom_normals:
        bpy.context.view_layer.objects.active = road
        bpy.ops.mesh.customdata_custom_splitnormals_clear()

    bm = bmesh.new()
    bm.from_mesh(road.data)
    bm.faces.ensure_lookup_table()
    uvl = bm.loops.layers.uv.active

    caps = [
        f for f in bm.faces
        if (
            all(abs(g(mw @ v.co).x - PLOT[1]) < 1e-3 for v in f.verts)
            or all(abs(g(mw @ v.co).x - PLOT[0]) < 1e-3 for v in f.verts)
        )
    ]
    if not caps:
        die("expected x=+-43 end-cap faces on Road, found none")
    n_caps = len(caps)
    bmesh.ops.delete(bm, geom=caps, context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bm.normal_update()

    skirt_faces = [
        f for f in bm.faces
        if min(g(mw @ v.co).y for v in f.verts) < ROAD_Y - 1e-3
        and 0.15 < max(g(mw @ v.co).y for v in f.verts) <= PAVE_Y + 1e-3
        and abs(_gn_of(mw, f).y) < 0.2
    ]
    if skirt_faces:
        skirt_geom = list(
            {v for f in skirt_faces for v in f.verts}
            | {e for f in skirt_faces for e in f.edges}
            | set(skirt_faces)
        )
        plane_co = mwi @ Vector((0.0, -OFFSET_Z, ROAD_Y))
        plane_no = (mwi.to_3x3() @ Vector((0.0, 0.0, 1.0))).normalized()
        bmesh.ops.bisect_plane(bm, geom=skirt_geom, dist=1e-5, plane_co=plane_co, plane_no=plane_no)
    bm.normal_update()

    # Extend outer sidewalk skirts (z = -40, -52) down to SKIRT_FOOT_Y = -0.12 to match Road_Ext.
    lowered_verts = set()
    for f in bm.faces:
        pts = [g(mw @ v.co) for v in f.verts]
        if (
            abs(_gn_of(mw, f).y) < 0.2
            and min(p.y for p in pts) < 0.02
            and max(p.y for p in pts) <= ROAD_Y + 1e-3
            and all(p.z > -59.5 for p in pts)
        ):
            for v in f.verts:
                gp = g(mw @ v.co)
                if abs(gp.y) < 1e-3 and v not in lowered_verts:
                    v.co = mwi @ Vector((gp.x, -(gp.z - OFFSET_Z), SKIRT_FOOT_Y))
                    lowered_verts.add(v)
    bm.normal_update()

    asphalt_faces = 0
    flat_faces = 0
    for f in bm.faces:
        pts = [g(mw @ v.co) for v in f.verts]
        ys = [p.y for p in pts]
        gn = _gn_of(mw, f)
        if gn.y > 0.99 and all(abs(y - ROAD_Y) < 1e-3 for y in ys):
            f.material_index = 1
            f.smooth = False
            for lp in f.loops:
                lp[uvl].uv = ROAD_ASPHALT_UV
            asphalt_faces += 1
            flat_faces += 1
        elif gn.y > 0.99 and all(abs(y - PAVE_Y) < 1e-3 for y in ys):
            f.material_index = 1
            f.smooth = False
            if all(p.z >= -41.5 for p in pts):
                for lp in f.loops:
                    lp[uvl].uv = ROAD_SIDEWALK_UV
            flat_faces += 1
        elif min(ys) >= SKIRT_FOOT_Y - 0.01 and max(ys) <= 0.15:
            f.material_index = 1
            f.smooth = False
            flat_faces += 1
        else:
            f.material_index = 0

    asphalt_edges = {
        e for f in bm.faces
        if f.material_index == 1 and _gn_of(mw, f).y > 0.99
        for e in f.edges
        if len(e.link_faces) > 1
        and any(lf.material_index == 0 or _gn_of(mw, lf).y < 0.99 for lf in e.link_faces)
    }
    if asphalt_edges:
        bmesh.ops.split_edges(bm, edges=list(asphalt_edges))
    bm.normal_update()
    bm.to_mesh(road.data)
    bm.free()
    road.data.update()
    rep("Road seamless pass: deleted %d x=+-43 caps, bisected %d outer skirts, assigned %d flat faces (%d asphalt)" % (
        n_caps, len(skirt_faces), flat_faces, asphalt_faces))
    return n_caps


def fill_plot(lot, pad_loops, skirt_uv):
    """Pave the rest of the plot flat at PAVE_Y: the strips x -43..-40 and 40..43 that the
    Toon paving stops short of, the two dips (x -12..12 at z -64..-60 and -100..-96), and the
    grown site north of the plot (x -128..128, z -210..-100), and the side land beside the plot
    (x -128..-43 and 43..128, z -100..-60).
    Each new top face takes the UV of the nearest existing pad corner (the paving's own
    swatch), each new skirt the paving edge skirt's UV. Skirts close the new edges down to
    y 0, as the Toon paving's own skirts do. Returns [(corners, normal)] in Godot world for
    the re-read's normal check."""
    mwi = lot.matrix_world.inverted()
    bm = bmesh.new()
    bm.from_mesh(lot.data)
    uvl = bm.loops.layers.uv.active
    added = []

    def bw(x, y, z):  # Godot world -> Lot local
        return mwi @ Vector((x, -(z - OFFSET_Z), y))

    def quad(pts, normal, uv):
        f = bm.faces.new([bm.verts.new(bw(*p)) for p in pts])
        f.normal_update()
        world_n = lot.matrix_world.to_3x3() @ f.normal
        if world_n.dot(Vector((normal[0], -normal[2], normal[1]))) < 0:
            bmesh.ops.reverse_faces(bm, faces=[f])
            f.normal_update()
        for lp in f.loops:
            lp[uvl].uv = uv
        added.append(([Vector(p) for p in pts], Vector(normal)))

    def pad_uv(cx, cz):
        best = min(pad_loops, key=lambda r: (r[0].x - cx) ** 2 + (r[0].z - cz) ** 2)
        return best[1]

    y = PAVE_Y
    px0, px1, pz0, pz1 = PLOT
    tops = [(px0, -LOT_HALF_X), (LOT_HALF_X, px1)]  # strips, full depth
    for xa, xb in tops:
        quad([(xa, y, pz0), (xb, y, pz0), (xb, y, pz1), (xa, y, pz1)], (0, 1, 0),
             pad_uv((xa + xb) / 2, (pz0 + pz1) / 2))
    for za, zb in ((pz1 - 4.0, pz1), (pz0, pz0 + 4.0)):  # the two dips
        quad([(-DIP_HALF_X, y, za), (DIP_HALF_X, y, za), (DIP_HALF_X, y, zb), (-DIP_HALF_X, y, zb)], (0, 1, 0),
             pad_uv(0.0, (za + zb) / 2))
    # The back dip's mouth flares: the pads round off from (+-12, -98) to (+-14, -100)
    # through BACK_FLARE (measured on the shell's Lot). Fill each flare as a fan from the
    # dip corner (+-12, -100); the pads' sloped kerb faces there end up under it.
    for sx in (-1.0, 1.0):
        corner = (sx * DIP_HALF_X, y, pz0)
        curve = [(sx * cx, y, cz) for cx, cz in BACK_FLARE]
        for p, q in zip(curve, curve[1:]):
            quad([corner, p, q], (0, 1, 0), pad_uv(sx * 13.0, pz0 + 0.5))
    # The grown site north of the first plot, one flat top in the pads' swatch, meeting the
    # plot's north edge at z -100 (whose Toon skirts filter_lot() dropped).
    gx0, gx1, gz0, _gz1 = GROWN
    quad([(gx0, y, gz0), (gx1, y, gz0), (gx1, y, pz0), (gx0, y, pz0)], (0, 1, 0), pad_uv(0.0, pz0))
    # The side land west and east of the first plot, down to the plot's south edge.
    cx0, cx1 = CENTRE_X
    sides = [(gx0, cx0), (cx1, gx1)]
    for xa, xb in sides:
        quad([(xa, y, pz0), (xb, y, pz0), (xb, y, pz1), (xa, y, pz1)], (0, 1, 0),
             pad_uv((cx0 if xb == cx0 else cx1), (pz0 + pz1) / 2))
    tops = tops + sides
    # Skirts: the grown site's outer sides at x -128 and 128 and its north edge at z -210, and
    # the south edge along every new top face (the Toon paving keeps its own skirts elsewhere
    # on that edge).
    quad([(gx0, 0.0, gz0), (gx0, 0.0, pz1), (gx0, y, pz1), (gx0, y, gz0)], (-1, 0, 0), skirt_uv)
    quad([(gx1, 0.0, gz0), (gx1, 0.0, pz1), (gx1, y, pz1), (gx1, y, gz0)], (1, 0, 0), skirt_uv)
    quad([(gx0, 0.0, gz0), (gx1, 0.0, gz0), (gx1, y, gz0), (gx0, y, gz0)], (0, 0, -1), skirt_uv)
    for xa, xb in tops:
        quad([(xa, SKIRT_FOOT_Y, pz1), (xb, SKIRT_FOOT_Y, pz1), (xb, y, pz1), (xa, y, pz1)],
             (0, 0, 1), skirt_uv)
    quad([(-DIP_HALF_X, 0.0, pz1), (DIP_HALF_X, 0.0, pz1), (DIP_HALF_X, y, pz1), (-DIP_HALF_X, y, pz1)],
         (0, 0, 1), skirt_uv)
    bm.to_mesh(lot.data)
    bm.free()
    lot.data.update()
    rep("Lot plot fill: %d faces added (tops at y %.2f and skirts down to 0); skirt uv %s; top uvs from the nearest pad corner"
        % (len(added), y, tuple(round(c, 4) for c in skirt_uv)))
    return added


def plot_index(gx, gz):
    """The land plot (column, row) whose inside holds Godot world point (gx, gz), or None on a
    plot line."""
    for lines, v in ((COLUMN_X, gx), (ROW_Z, gz)):
        if any(abs(v - line) < 1e-3 for line in lines[1:-1]):
            return None
    return (sum(1 for x in COLUMN_X[1:-1] if gx > x), sum(1 for z in ROW_Z[1:-1] if gz > z))


def split_plots(lot, root, skirt_uv):
    """Cut the paved Lot on COLUMN_X and ROW_Z into one object per land plot, Lot_<column>_<row>,
    parented to root with an identity transform (vertices in world), with the Lot's material;
    close every edge a plot shares with another plot with a skirt from PAVE_Y down to
    SKIRT_FOOT_Y in the paving edge skirt's UV; remove the Lot. Returns the skirts as
    [(corners, normal)] in Godot world for the re-read's normal check."""
    bm = bmesh.new()
    bm.from_mesh(lot.data)
    bm.transform(lot.matrix_world)
    welded = weld_t_junctions(bm)
    for x in COLUMN_X[1:-1]:
        bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], dist=1e-5,
                               plane_co=Vector((x, 0.0, 0.0)), plane_no=Vector((1.0, 0.0, 0.0)))
    for z in ROW_Z[1:-1]:
        bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], dist=1e-5,
                               plane_co=Vector((0.0, -(z - OFFSET_Z), 0.0)), plane_no=Vector((0.0, 1.0, 0.0)))

    def face_plot(f):
        c = f.calc_center_median()
        return plot_index(c.x, -c.y + OFFSET_Z)

    on_line = [tuple(round(v, 2) for v in g(f.calc_center_median())) for f in bm.faces if face_plot(f) is None]
    if on_line:
        die("Lot faces lie on a plot line after the cut: %s" % on_line[:5])
    skirts = []
    counts = Counter(face_plot(f) for f in bm.faces)

    def keep(name, mesh_bm):
        me = bpy.data.meshes.new(name)
        mesh_bm.to_mesh(me)
        mesh_bm.free()
        for m in lot.data.materials:
            me.materials.append(m)
        ob = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(ob)
        ob.parent = root
        ob.matrix_world = Matrix.Identity(4)

    for name in PLOT_NAMES:
        col, row = (int(v) for v in name.split("_")[1:])
        part = bm.copy()
        bmesh.ops.delete(part, geom=[f for f in part.faces if face_plot(f) != (col, row)], context="FACES")
        keep(name, part)
        x0, x1, z0, z1 = COLUMN_X[col], COLUMN_X[col + 1], ROW_Z[row], ROW_Z[row + 1]
        lo, hi = SKIRT_FOOT_Y, PAVE_Y
        for side, pts, normal in kerb_sides(col, row, x0, x1, z0, z1, lo, hi):
            kb = bmesh.new()
            uvl = kb.loops.layers.uv.new("UVMap")
            f = kb.faces.new([kb.verts.new(Vector((x, -(z - OFFSET_Z), y))) for x, y, z in pts])
            f.normal_update()
            if f.normal.dot(Vector((normal[0], -normal[2], normal[1]))) < 0:
                bmesh.ops.reverse_faces(kb, faces=[f])
                f.normal_update()
            for lp in f.loops:
                lp[uvl].uv = skirt_uv
            skirts.append(([Vector(p) for p in pts], Vector(normal)))
            keep("%s_%s" % (name, side), kb)
    bm.free()
    bpy.data.objects.remove(lot, do_unlink=True)
    rep("Lot T-junctions welded before the cut: %d" % welded)
    rep("Lot split into %d plot objects on x %s and z %s; Lot faces per plot after the cut %s; "
        "%d kerb objects (one per plot side facing another plot) from y %.2f down to %.2f" % (
            len(PLOT_NAMES), COLUMN_X, ROW_Z, sorted(counts.items()), len(skirts), PAVE_Y, SKIRT_FOOT_Y))
    return skirts


def t_junctions(verts, edges):
    """(vertex index, edge) pairs where a vertex lies strictly inside an edge it is not an end of:
    a T-junction, where the GPU leaves a hairline crack between the faces that meet there."""
    out = []
    for i, j in edges:
        a, b = verts[i], verts[j]
        d = b - a
        length2 = d.length_squared
        if length2 < 1e-10:
            continue
        for k, v in enumerate(verts):
            if k in (i, j):
                continue
            t = (v - a).dot(d) / length2
            if 1e-6 < t < 1.0 - 1e-6 and (a + d * t - v).length < 1e-4:
                out.append((k, (i, j)))
    return out


def weld_t_junctions(bm):
    """Split every edge of bm that has another vertex lying inside it at that vertex and merge the
    two, so faces that meet share their vertices. A T-junction's crack shows what lies under the
    paving (the dark stand pad) as a dotted line. The faces are triangulated first, and each
    triangle a split turns into a quad is cut from the new vertex to its far corner, so the exporter
    never triangulates it into a sliver along the old edge, which would leave the T-junction in
    place. Returns the number of splits."""
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    count = 0
    for _ in range(64):
        bm.verts.index_update()
        bm.verts.ensure_lookup_table()
        bm.edges.ensure_lookup_table()
        refs = list(bm.verts)
        verts = [v.co.copy() for v in refs]
        found = t_junctions(verts, [(e.verts[0].index, e.verts[1].index) for e in bm.edges])
        if not found:
            return count
        done = set()
        for k, (i, j) in found:
            if (i, j) in done:
                continue
            done.add((i, j))
            edge = bm.edges.get((refs[i], refs[j]))
            if edge is None:
                continue
            a, b = verts[i], verts[j]
            t = (verts[k] - a).dot(b - a) / (b - a).length_squared
            _new_edge, new_vert = bmesh.utils.edge_split(edge, refs[i], t)
            new_vert.co = verts[k]
            for face in list(new_vert.link_faces):
                ring = [lp.vert for lp in face.loops]
                if len(ring) == 4:
                    far = ring[(ring.index(new_vert) + 2) % 4]
                    bmesh.ops.connect_verts(bm, verts=[new_vert, far])
            count += 1
        bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-5)
    die("T-junctions left after 64 welding passes")


def kerb_names():
    """Every kerb object's name, Lot_<column>_<row>_<N, E, S or W>."""
    return tuple("Lot_%d_%d_%s" % (c, r, side) for r in range(len(ROW_Z) - 1) for c in range(len(COLUMN_X) - 1)
                 for side, _pts, _normal in kerb_sides(c, r, 0, 0, 0, 0, 0, 0))


def kerb_sides(col, row, x0, x1, z0, z1, lo, hi):
    """The sides of plot (col, row) that face another plot, as (N/E/S/W, Godot world corners, outward
    normal). The game shows a side's kerb only while this plot is owned and the plot across that side
    is not (OwnedPaving), so touching owned plots pave as one surface (user ruling touching-owned-
    land-plots-pave-as-one-seamless-surface-no-lin)."""
    out = []
    if row > 0:
        out.append(("N", [(x0, lo, z0), (x1, lo, z0), (x1, hi, z0), (x0, hi, z0)], (0, 0, -1)))
    if col < len(COLUMN_X) - 2:
        out.append(("E", [(x1, lo, z0), (x1, lo, z1), (x1, hi, z1), (x1, hi, z0)], (1, 0, 0)))
    if row < len(ROW_Z) - 2:
        out.append(("S", [(x0, lo, z1), (x1, lo, z1), (x1, hi, z1), (x0, hi, z1)], (0, 0, 1)))
    if col > 0:
        out.append(("W", [(x0, lo, z0), (x0, lo, z1), (x0, hi, z1), (x0, hi, z0)], (-1, 0, 0)))
    return out


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=SHELL)
    bpy.context.view_layer.update()
    objs = {o.name: o for o in bpy.context.scene.objects}
    for need in ("TP_Airport_Shell_ROOT", "Road", "Lot", "Poles", "Canopy", "Upper"):
        if need not in objs:
            die("shell node missing: %s" % need)
    rep("SOURCE %s" % SHELL)
    rep("materials %s images %s" % (sorted(m.name for m in bpy.data.materials), sorted(i.name for i in bpy.data.images)))
    census("shell census (Blender scene after import; Godot world AABB):")

    root = bpy.data.objects.new(ROOT, None)
    bpy.context.scene.collection.objects.link(root)
    road_before = objs["Road"].matrix_world.copy()
    for name in KEEP:
        o = objs[name]
        mw = o.matrix_world.copy()
        o.parent = root
        o.matrix_world = mw
    road_dropped = filter_road(objs["Road"])
    seamless_road(objs["Road"])
    pad_loops, skirt_uv = filter_lot(objs["Lot"])
    added = fill_plot(objs["Lot"], pad_loops, skirt_uv)
    added += split_plots(objs["Lot"], root, skirt_uv)
    for o in list(bpy.context.scene.objects):
        if o.name not in ("Road",) + PLOT_NAMES + kerb_names() and o is not root:
            bpy.data.objects.remove(o, do_unlink=True)
    bpy.ops.outliner.orphans_purge(do_recursive=True)
    bpy.context.view_layer.update()
    if objs["Road"].matrix_world != road_before:
        die("Road moved while reparenting")
    census("site census (Blender scene before export):")

    bpy.ops.object.select_all(action="SELECT")
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    os.makedirs(REPORT_DIR, exist_ok=True)
    write_import()
    bpy.ops.export_scene.gltf(
        filepath=OUT,
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=False,
        export_materials="EXPORT",
        export_image_format="AUTO",
        export_cameras=False,
        export_lights=False,
        export_vertex_color="NONE",
        export_all_vertex_colors=False,
        export_active_vertex_color_when_no_material=False,
        export_morph=False,
        export_skins=False,
        export_animations=False,
        export_extras=True,
    )
    expected = {}
    for o in bpy.context.scene.objects:
        tris = sum(len(p.vertices) - 2 for p in o.data.polygons) if o.type == "MESH" else 0
        expected[o.name] = (o.parent.name if o.parent else None, tris)
    site = reread(OUT, "site")
    shell = reread(SHELL, "shell")
    verify(site, shell, expected, added, road_dropped)
    path = os.path.join(REPORT_DIR, "census.txt")
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(report) + "\n")
    for line in report:
        print("CENSUS", line, flush=True)
    log("WROTE %s" % OUT)
    log("REPORT %s" % path)


def write_import():
    """The shell's Godot import settings (toon_post_import.gd binds the shared toon materials,
    embedded_image_handling=0 extracts no PNGs), written BEFORE the .glb so an open editor
    that reimports it binds them. An existing .import keeps its [remap] and [deps] (its uid)."""
    with open(SHELL + ".import", encoding="utf-8") as fh:
        src = fh.read()
    params = src[src.index("[params]"):]
    for need in ('import_script/path="res://assets/toon_post_import.gd"', "gltf/embedded_image_handling=0"):
        if need not in params:
            die("shell import settings lack %s" % need)
    imp = OUT + ".import"
    if os.path.exists(imp):
        with open(imp, encoding="utf-8") as fh:
            text = fh.read()
        text = text[:text.index("[params]")] + params
        how = "patched [params], uid kept"
    else:
        text = '[remap]\n\nimporter="scene"\nimporter_version=1\ntype="PackedScene"\n\n' + params
        how = "written new; Godot adds the uid on import"
    with open(imp, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)
    rep("import settings: %s (%s)" % (imp, how))


def node_matrix(nd):
    if "matrix" in nd:
        m = nd["matrix"]
        return Matrix([[m[c * 4 + r] for c in range(4)] for r in range(4)])
    t = nd.get("translation", [0, 0, 0])
    r = nd.get("rotation", [0, 0, 0, 1])
    s = nd.get("scale", [1, 1, 1])
    q = Quaternion((r[3], r[0], r[1], r[2]))
    return Matrix.Translation(Vector(t)) @ q.to_matrix().to_4x4() @ Matrix.Diagonal(Vector((s[0], s[1], s[2], 1.0)))


def read_accessor(js, binc, idx):
    acc = js["accessors"][idx]
    view = js["bufferViews"][acc["bufferView"]]
    comps = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[acc["type"]]
    fmt_c = {5126: "f", 5125: "I", 5123: "H", 5121: "B"}[acc["componentType"]]
    size = struct.calcsize("<" + fmt_c)
    stride = view.get("byteStride", size * comps)
    start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    out = []
    for i in range(acc["count"]):
        out.append(struct.unpack_from("<" + fmt_c * comps, binc, start + i * stride))
    return out


def reread(path, tag):
    """Every number here comes from the written file."""
    with open(path, "rb") as fh:
        data = fh.read()
    magic, _v, length = struct.unpack_from("<III", data, 0)
    if magic != 0x46546C67 or length != len(data):
        die("not a GLB: %s" % path)
    jlen = struct.unpack_from("<I", data, 12)[0]
    js = json.loads(data[20:20 + jlen])
    boff = 20 + jlen
    blen = struct.unpack_from("<I", data, boff)[0]
    binc = data[boff + 8:boff + 8 + blen]
    nodes = js["nodes"]
    mats = [m["name"] for m in js.get("materials", [])]
    imgs = [im.get("name", "?") for im in js.get("images", [])]
    binding = []
    for m in js.get("materials", []):
        t = m.get("pbrMetallicRoughness", {}).get("baseColorTexture")
        img = imgs[js["textures"][t["index"]]["source"]] if t else None
        binding.append("%s->%s" % (m["name"], img))
    out = {"path": path, "bytes": len(data), "materials": mats, "images": imgs, "binding": binding, "nodes": {}}

    def walk(i, parent, pname):
        nd = nodes[i]
        world = parent @ node_matrix(nd)
        name = nd.get("name", "?")
        rec = {"parent": pname, "world": world, "tris": 0, "verts": 0, "mats": [], "lo": None, "hi": None}
        if "mesh" in nd:
            pos_all = []
            nrm_all = []
            uv_all = []
            tri_idx = []
            tri_mats = []
            idx_count = 0
            for prim in js["meshes"][nd["mesh"]]["primitives"]:
                idx_count += js["accessors"][prim["indices"]]["count"]
                pmat = mats[prim["material"]] if "material" in prim else None
                rec["mats"].append(pmat)
                pos_p = read_accessor(js, binc, prim["attributes"]["POSITION"])
                nrm_p = read_accessor(js, binc, prim["attributes"]["NORMAL"])
                uv_p = read_accessor(js, binc, prim["attributes"]["TEXCOORD_0"]) if "TEXCOORD_0" in prim["attributes"] else [(0.0, 0.0)] * len(pos_p)
                base = len(pos_all)
                pos_all += pos_p
                nrm_all += nrm_p
                uv_all += uv_p
                idx = [i[0] + base for i in read_accessor(js, binc, prim["indices"])]
                for k in range(0, len(idx), 3):
                    tri_idx.append(idx[k:k + 3])
                    tri_mats.append(pmat)
            rec["tris"] = idx_count // 3
            rec["verts"] = len(pos_all)
            pts = [world @ Vector(p) for p in pos_all]
            # glTF is y-up: Godot local = glTF; add the placement.
            pts = [Vector((p.x, p.y, p.z + OFFSET_Z)) for p in pts]
            rec["lo"], rec["hi"] = bbox(pts)
            rec["pos_hash"] = hashlib.sha256(json.dumps(sorted(
                [round(c, 5) for c in p] for p in pos_all)).encode()).hexdigest()[:16]
            rec["pts"] = pts
            rec["tris_world"] = [tuple(pts[i] for i in t) for t in tri_idx]
            rec["tri_idx"] = tri_idx
            rec["tri_mats"] = tri_mats
            rec["uvs"] = uv_all
            rec["nrm"] = [(world.to_3x3() @ Vector(n)).normalized() for n in nrm_all]
        out["nodes"][name] = rec
        for c in nd.get("children", []):
            walk(c, world, name)

    for r in js["scenes"][js.get("scene", 0)]["nodes"]:
        walk(r, Matrix.Identity(4), None)
    rep("")
    rep("RE-READ %s (%s) bytes %d nodes %d materials %s images %s" % (path, tag, len(data), len(nodes), mats, imgs))
    rep("  material binding: %s" % binding)
    total = 0
    for name, rec in out["nodes"].items():
        total += rec["tris"]
        if rec["lo"] is None:
            p = rec["world"].to_translation()
            rep("  %-24s (empty) parent %-22s at %.3f %.3f %.3f" % (name, rec["parent"], p.x, p.y, p.z + OFFSET_Z))
        else:
            rep("  %-24s verts %5d tris %5d parent %-22s %s %s" % (
                name, rec["verts"], rec["tris"], rec["parent"], ",".join(m or "-" for m in rec["mats"]),
                fmt(rec["lo"], rec["hi"])))
    rep("  total triangles %d" % total)
    return out



def plot_holes(lot):
    """Samples on a 0.25 m grid over the grown site (0.125 m in from its edges) not covered, seen
    from straight above, by an up-facing Lot triangle at PAVE_Y or higher. Uses the written
    triangles (positions in Godot world)."""
    tris = lot["tris_world"]
    px0, px1, pz0, pz1 = GROWN
    cells = {}
    for a, b, c in tris:
        n = (b - a).cross(c - a)
        if n.length < 1e-9 or n.normalized().y < 0.9 or min(a.y, b.y, c.y) < PAVE_Y - 1e-4:
            continue
        for gx in range(int(math.floor(min(a.x, b.x, c.x))), int(math.floor(max(a.x, b.x, c.x))) + 1):
            for gz in range(int(math.floor(min(a.z, b.z, c.z))), int(math.floor(max(a.z, b.z, c.z))) + 1):
                cells.setdefault((gx, gz), []).append((a, b, c))

    def inside(px, pz, a, b, c):
        d1 = (px - b.x) * (a.z - b.z) - (a.x - b.x) * (pz - b.z)
        d2 = (px - c.x) * (b.z - c.z) - (b.x - c.x) * (pz - c.z)
        d3 = (px - a.x) * (c.z - a.z) - (c.x - a.x) * (pz - a.z)
        neg = d1 < -1e-9 or d2 < -1e-9 or d3 < -1e-9
        pos = d1 > 1e-9 or d2 > 1e-9 or d3 > 1e-9
        return not (neg and pos)

    holes = []
    count = 0
    x = px0 + 0.125
    while x < px1:
        z = pz0 + 0.125
        while z < pz1:
            count += 1
            cand = cells.get((int(math.floor(x)), int(math.floor(z))), [])
            if not any(inside(x, z, *t) for t in cand):
                holes.append((round(x, 2), round(z, 2)))
            z += 0.25
        x += 0.25
    return holes, count


def verify(site, shell, expected, added, road_dropped):
    names = set(site["nodes"])
    want = {ROOT, "Road", *PLOT_NAMES, *kerb_names()}
    if names != want:
        die("written site nodes %s, want %s" % (sorted(names), sorted(want)))
    bad = [n for n, (p, t) in expected.items() if (site["nodes"][n]["parent"], site["nodes"][n]["tris"]) != (p, t)]
    if bad:
        die("re-read differs from the scene for %s" % bad)
    if set(site["materials"]) != {"TP_Atlas_1A_D", "TP_Atlas_Simple_1A_D", ROAD_FLAT_MAT} or site["images"] != ["tp_atlas_1a_d"]:
        die("written site has materials %s images %s" % (site["materials"], site["images"]))
    if any(b.endswith("->None") for b in site["binding"]):
        die("material without an atlas image: %s" % site["binding"])
    plot_mats = sorted({tuple(site["nodes"][n]["mats"]) for n in PLOT_NAMES + kerb_names()})
    if sorted(site["nodes"]["Road"]["mats"]) != ["TP_Atlas_Simple_1A_D", ROAD_FLAT_MAT] or plot_mats != [("TP_Atlas_1A_D",)]:
        die("node materials changed: Road %s plots %s" % (site["nodes"]["Road"]["mats"], plot_mats))
    a, b = site["nodes"]["Road"], shell["nodes"]["Road"]
    # The Road keeps every shell up-facing road/sidewalk triangle except the dropped sidewalk
    # tile accents, with x = +-43.0 end-caps removed and asphalt normalized/UV-aligned.
    shell_accent = [t for t in b["tris_world"] if is_accent_tri(t)]
    shell_up = Counter(
        tri_key(t) for t in b["tris_world"]
        if not is_accent_tri(t) and (t[1] - t[0]).cross(t[2] - t[0]).length > 1e-9
        and (t[1] - t[0]).cross(t[2] - t[0]).normalized().y > 0.9
    )
    site_up = Counter(
        tri_key(t) for t in a["tris_world"]
        if (t[1] - t[0]).cross(t[2] - t[0]).length > 1e-9
        and (t[1] - t[0]).cross(t[2] - t[0]).normalized().y > 0.9
    )
    same_frame = all(abs(a["world"][r][c] - b["world"][r][c]) < 1e-6 for r in range(4) for c in range(4))
    caps_left = [
        t for t in a["tris_world"]
        if all(abs(p.x - PLOT[1]) < 1e-3 for p in t) or all(abs(p.x - PLOT[0]) < 1e-3 for p in t)
    ]
    want_uv = (ROAD_ASPHALT_UV[0], 1.0 - ROAD_ASPHALT_UV[1])
    bad_asphalt = 0
    asphalt_tris = 0
    for tri_v, tri_pts, tmat in zip(a["tri_idx"], a["tris_world"], a["tri_mats"]):
        gn = (tri_pts[1] - tri_pts[0]).cross(tri_pts[2] - tri_pts[0])
        if gn.length > 1e-9 and gn.normalized().y > 0.99 and all(abs(p.y - ROAD_Y) < 1e-3 for p in tri_pts):
            asphalt_tris += 1
            if tmat != ROAD_FLAT_MAT:
                bad_asphalt += 1
            for vi in tri_v:
                if (a["nrm"][vi] - Vector((0.0, 1.0, 0.0))).length > 1e-4:
                    bad_asphalt += 1
                if abs(a["uvs"][vi][0] - want_uv[0]) > 1e-4 or abs(a["uvs"][vi][1] - want_uv[1]) > 1e-4:
                    bad_asphalt += 1
    rep("")
    rep("ROAD site  verts %d tris %d positions %s %s" % (a["verts"], a["tris"], a["pos_hash"], fmt(a["lo"], a["hi"])))
    rep("ROAD shell verts %d tris %d positions %s %s" % (b["verts"], b["tris"], b["pos_hash"], fmt(b["lo"], b["hi"])))
    rep("ROAD world transform site %s shell %s" % ([round(v, 6) for row in a["world"] for v in row],
                                                   [round(v, 6) for row in b["world"] for v in row]))
    rep("ROAD shell accent triangles %d (filter dropped %d); up-facing site vs shell diff %d/%d; "
        "x=+-43 caps left %d; asphalt tris %d bad %d" % (
            len(shell_accent), road_dropped, sum((site_up - shell_up).values()),
            sum((shell_up - site_up).values()), len(caps_left), asphalt_tris, bad_asphalt))
    if not same_frame or site_up != shell_up or len(shell_accent) != road_dropped or caps_left or bad_asphalt or asphalt_tris == 0:
        die("the site's Road failed seamless road checks")
    # Under every dropped accent the sidewalk runs on: its centre lies on an up-facing site
    # Road triangle at PAVE_Y.
    walk = [t for t in a["tris_world"] if all(abs(p.y - PAVE_Y) < 1e-4 for p in t)]
    bare = []
    for t in shell_accent:
        cx, cz = sum(p.x for p in t) / 3.0, sum(p.z for p in t) / 3.0
        if not any(in_tri_xz(cx, cz, *w) for w in walk):
            bare.append((round(cx, 2), round(cz, 2)))
    rep("ROAD sidewalk under the dropped accents: %d of %d accent centres without sidewalk at y %.2f%s"
        % (len(bare), len(shell_accent), PAVE_Y, (": " + str(bare[:5])) if bare else ""))
    if bare:
        die("dropping the Road accents left holes in the sidewalk")
    rep("ROAD unchanged but for the dropped accents: same world transform and every other triangle "
        "at the same positions")
    # Each plot's top lies inside its own plot and reaches all four of its edges; the checks
    # below then run on all the plots together as the one paving they were cut from.
    for name in PLOT_NAMES:
        col, row = (int(v) for v in name.split("_")[1:])
        x0, x1, z0, z1 = COLUMN_X[col], COLUMN_X[col + 1], ROW_Z[row], ROW_Z[row + 1]
        rec = site["nodes"][name]
        tops = [p for t in rec["tris_world"] if (t[1] - t[0]).cross(t[2] - t[0]).length > 1e-9
                and abs((t[1] - t[0]).cross(t[2] - t[0]).normalized().y) > 0.9 for p in t]
        lo, hi = bbox(tops)
        off = max(x0 - lo.x, lo.x - x0, hi.x - x1, x1 - hi.x, z0 - lo.z, lo.z - z0, hi.z - z1, z1 - hi.z)
        if off > 1e-3:
            die("%s top %s is not its plot x %.0f..%.0f z %.0f..%.0f" % (name, fmt(lo, hi), x0, x1, z0, z1))
    tops = []
    for name in PLOT_NAMES:
        for t in site["nodes"][name]["tris_world"]:
            normal = (t[1] - t[0]).cross(t[2] - t[0])
            if normal.length > 1e-9 and abs(normal.normalized().y) > 0.9:
                tops.append(t)
    keyed = {}
    for t in tops:
        for q in t:
            keyed.setdefault(tuple(round(c, 4) for c in q), q)
    index = {key: i for i, key in enumerate(keyed)}
    verts = list(keyed.values())

    def at(q):
        return index[tuple(round(c, 4) for c in q)]

    edges = {tuple(sorted((at(t[m]), at(t[(m + 1) % 3])))) for t in tops for m in range(3)}
    found = t_junctions(verts, sorted(edges))
    rep("PLOTS: T-junctions on the written plot tops (all plots together): %d of %d vertices, %d edges"
        % (len(found), len(verts), len(edges)))
    if found:
        die("the written paving has T-junctions, which show as hairline cracks: %s"
            % [tuple(round(c, 2) for c in verts[k]) for k, _e in found[:5]])
    rep("PLOTS: each of the %d plot tops spans exactly its plot (x on %s, z on %s)" % (
        len(PLOT_NAMES), COLUMN_X, ROW_Z))
    lot = {"pts": [], "nrm": [], "tris_world": []}
    for name in PLOT_NAMES + kerb_names():
        for key in lot:
            lot[key] += site["nodes"][name][key]
    lot["lo"], lot["hi"] = bbox(lot["pts"])
    x0, x1, z0, z1 = SLAB_BOX
    high = [p for p in lot["pts"] if p.y > SIGN_MIN_Y]
    in_slab_high = [p for p in lot["pts"] if x0 < p.x < x1 and z0 < p.z < z1 and p.y > 0.25]
    px0, px1, pz0, pz1 = GROWN
    on_plot = sum(1 for p in lot["pts"] if px0 <= p.x <= px1 and pz0 <= p.z <= pz1)
    rep("LOT written: points above y %.2f: %d; points inside the old slab box above y 0.25: %d; "
        "highest point %.3f; points on the grown site %d of %d" % (
            SIGN_MIN_Y, len(high), len(in_slab_high), lot["hi"].y, on_plot, len(lot["pts"])))
    if high or in_slab_high:
        die("written Lot still holds building geometry")
    # The grown site is flat paving: every up-facing Lot vertex inside it (5 cm in from its
    # edges) sits at PAVE_Y (the tile accents 3 mm above it are dropped), and nothing is higher.
    inner = [(p, n) for p, n in zip(lot["pts"], lot["nrm"])
             if px0 + 0.05 < p.x < px1 - 0.05 and pz0 + 0.05 < p.z < pz1 - 0.05]
    up_y = sorted({round(p.y, 4) for p, n in inner if n.y > 0.9})
    top = max(p.y for p, _n in inner)
    rep("LOT grown site surface: up-facing heights inside the grown site %s; highest point inside %.4f"
        % (up_y, top))
    if up_y != [PAVE_Y] or top > PAVE_Y + 1e-4:
        die("the grown site is not flat paving at y %.2f" % PAVE_Y)
    # Coverage: a grid of 0.25 m samples over the grown site; each must lie on an up-facing
    # Lot triangle at PAVE_Y or above (no hole, no dip, no bare strip).
    holes, n_samples = plot_holes(lot)
    rep("LOT grown site coverage: %d of %d samples (0.25 m grid, 0.125 m in from the edges) without "
        "paving at y >= %.2f%s" % (len(holes), n_samples, PAVE_Y, (": first " + str(holes[:5])) if holes else ""))
    if holes:
        die("the grown site has unpaved spots")
    # Every added face carries its intended normal in the written file.
    for corners, normal in added:
        for c in corners:
            if not any((p - c).length < 1e-4 and n.dot(normal) > 0.99 for p, n in zip(lot["pts"], lot["nrm"])):
                die("added face corner %s has no written vertex with normal %s" % (tuple(c), tuple(normal)))
    rep("LOT added faces: all %d carry their intended normal at every corner in the written file" % len(added))


main()
