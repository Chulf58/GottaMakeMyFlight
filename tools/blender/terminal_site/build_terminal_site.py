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
- Road: kept whole and unchanged (same mesh, same transform). The written file's Road is
  compared with the shell file's Road (vertex and index counts, bounds, transform, and
  every position) and the build fails on any difference.
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
  It keeps the paving pads at y 0.2 and the outer skirts at z -100 and -60.
  fill_plot() then paves the strips x -43..-40 and 40..43 that
  the Toon paving stops short of and the two dips (with the airside dip's flared mouth),
  each top face on the UV of the nearest existing pad corner, and closes the new edges
  with skirts down to y 0. The re-read proves the plot flat (up-facing heights only 0.2)
  and covered (a 0.25 m sample grid over the plot, every sample on paving), so the pads
  run on unbroken under the dropped accents.
- Poles: dropped. Every Poles island stands under the landside canopy between x -25.85 and
  25.85 and is part of its supports and lamps; the canopy goes, so they go.
- Upper, Canopy, Facade, Porch_1..8, Door_1..8, Doorway_1..8, Lights (all of it): dropped.

The node tree written: TP_Airport_Site_ROOT > Road, Lot.
The build fails unless the written file holds exactly those, with the shell's two atlases
(TP_Atlas_Simple_1A_D on Road, TP_Atlas_1A_D on Lot, both on the one image tp_atlas_1a_d, as in the
shell and the Toon source) bound, and no geometry above y 0.35
or inside the old slab box above y 0.25.
"""

import hashlib
import json
import math
import os
import struct
import sys

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
PLOT = (-43.0, 43.0, -100.0, -60.0)  # x0, x1, z0, z1 of the player's build plot
PAVE_Y = 0.2  # the Toon paving pads' top; the plot is paved flat at this height
PAVE_MAX_Y = 0.21  # above this an island is a raised paving block (tops 0.219, 0.238, 0.257)
ACCENT_MIN_LIFT = 0.001  # a flat island wholly this far over PAVE_Y is a tile accent (y 0.2031)
DIP_MAX_Y = 0.15  # below this an island is part of a dip (pads 0.10, markings 0.1065)
DIP_HALF_X = 12.0  # the dips run x -12..12
LOT_HALF_X = 40.0  # the Toon paving stops at x -40 and 40
BACK_FLARE = ((14.0, -100.0), (13.0, -99.73), (12.27, -99.0), (12.0, -98.0))  # east half; west mirrors
KEEP = ("Road", "Lot")
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
    want = ["dip", "dip kerb", "inner skirt", "raised block", "sign", "slab", "tile accent"]
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


def fill_plot(lot, pad_loops, skirt_uv):
    """Pave the rest of the plot flat at PAVE_Y: the strips x -43..-40 and 40..43 that the
    Toon paving stops short of, and the two dips (x -12..12 at z -64..-60 and -100..-96).
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
    # Skirts: the plot's outer sides at x -43 and 43, and its north and south edges along
    # every new top face (the Toon paving keeps its own skirts elsewhere on those edges).
    quad([(px0, 0.0, pz0), (px0, 0.0, pz1), (px0, y, pz1), (px0, y, pz0)], (-1, 0, 0), skirt_uv)
    quad([(px1, 0.0, pz0), (px1, 0.0, pz1), (px1, y, pz1), (px1, y, pz0)], (1, 0, 0), skirt_uv)
    flare_x = BACK_FLARE[0][0]
    for xa, xb in tops:
        quad([(xa, 0.0, pz0), (xb, 0.0, pz0), (xb, y, pz0), (xa, y, pz0)], (0, 0, -1), skirt_uv)
        quad([(xa, 0.0, pz1), (xb, 0.0, pz1), (xb, y, pz1), (xa, y, pz1)], (0, 0, 1), skirt_uv)
    quad([(-flare_x, 0.0, pz0), (flare_x, 0.0, pz0), (flare_x, y, pz0), (-flare_x, y, pz0)], (0, 0, -1), skirt_uv)
    quad([(-DIP_HALF_X, 0.0, pz1), (DIP_HALF_X, 0.0, pz1), (DIP_HALF_X, y, pz1), (-DIP_HALF_X, y, pz1)],
         (0, 0, 1), skirt_uv)
    bm.to_mesh(lot.data)
    bm.free()
    lot.data.update()
    rep("Lot plot fill: %d faces added (tops at y %.2f and skirts down to 0); skirt uv %s; top uvs from the nearest pad corner"
        % (len(added), y, tuple(round(c, 4) for c in skirt_uv)))
    return added


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
    pad_loops, skirt_uv = filter_lot(objs["Lot"])
    added = fill_plot(objs["Lot"], pad_loops, skirt_uv)
    for o in list(bpy.context.scene.objects):
        if o.name not in KEEP and o is not root:
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
    verify(site, shell, expected, added)
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
            tri_idx = []
            idx_count = 0
            for prim in js["meshes"][nd["mesh"]]["primitives"]:
                idx_count += js["accessors"][prim["indices"]]["count"]
                rec["mats"].append(mats[prim["material"]] if "material" in prim else None)
                pos_all += read_accessor(js, binc, prim["attributes"]["POSITION"])
                nrm_all += read_accessor(js, binc, prim["attributes"]["NORMAL"])
                base = len(pos_all) - js["accessors"][prim["attributes"]["POSITION"]]["count"]
                idx = [i[0] + base for i in read_accessor(js, binc, prim["indices"])]
                tri_idx += [idx[k:k + 3] for k in range(0, len(idx), 3)]
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
    """Samples on a 0.25 m grid over the plot (0.125 m in from its edges) not covered, seen
    from straight above, by an up-facing Lot triangle at PAVE_Y or higher. Uses the written
    triangles (positions in Godot world)."""
    tris = lot["tris_world"]
    px0, px1, pz0, pz1 = PLOT
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


def verify(site, shell, expected, added):
    names = set(site["nodes"])
    if names != {ROOT, *KEEP}:
        die("written site nodes %s, want %s" % (sorted(names), sorted({ROOT, *KEEP})))
    bad = [n for n, (p, t) in expected.items() if (site["nodes"][n]["parent"], site["nodes"][n]["tris"]) != (p, t)]
    if bad:
        die("re-read differs from the scene for %s" % bad)
    if set(site["materials"]) != {"TP_Atlas_1A_D", "TP_Atlas_Simple_1A_D"} or site["images"] != ["tp_atlas_1a_d"]:
        die("written site has materials %s images %s" % (site["materials"], site["images"]))
    if any(b.endswith("->None") for b in site["binding"]):
        die("material without an atlas image: %s" % site["binding"])
    if site["nodes"]["Road"]["mats"] != ["TP_Atlas_Simple_1A_D"] or site["nodes"]["Lot"]["mats"] != ["TP_Atlas_1A_D"]:
        die("node materials changed: Road %s Lot %s" % (site["nodes"]["Road"]["mats"], site["nodes"]["Lot"]["mats"]))
    a, b = site["nodes"]["Road"], shell["nodes"]["Road"]
    same = (a["verts"] == b["verts"] and a["tris"] == b["tris"] and a["pos_hash"] == b["pos_hash"]
            and (a["lo"] - b["lo"]).length < 1e-5 and (a["hi"] - b["hi"]).length < 1e-5
            and all(abs(a["world"][r][c] - b["world"][r][c]) < 1e-6 for r in range(4) for c in range(4)))
    rep("")
    rep("ROAD site  verts %d tris %d positions %s %s" % (a["verts"], a["tris"], a["pos_hash"], fmt(a["lo"], a["hi"])))
    rep("ROAD shell verts %d tris %d positions %s %s" % (b["verts"], b["tris"], b["pos_hash"], fmt(b["lo"], b["hi"])))
    rep("ROAD world transform site %s shell %s" % ([round(v, 6) for row in a["world"] for v in row],
                                                   [round(v, 6) for row in b["world"] for v in row]))
    if not same:
        die("the site's Road differs from the shell's Road")
    rep("ROAD identical: vertex and triangle counts, bounds, world transform and every position")
    x0, x1, z0, z1 = SLAB_BOX
    lot = site["nodes"]["Lot"]
    high = [p for p in lot["pts"] if p.y > SIGN_MIN_Y]
    in_slab_high = [p for p in lot["pts"] if x0 < p.x < x1 and z0 < p.z < z1 and p.y > 0.25]
    px0, px1, pz0, pz1 = PLOT
    on_plot = sum(1 for p in lot["pts"] if px0 <= p.x <= px1 and pz0 <= p.z <= pz1)
    rep("LOT written: points above y %.2f: %d; points inside the old slab box above y 0.25: %d; "
        "highest point %.3f; points on the plot %d of %d" % (
            SIGN_MIN_Y, len(high), len(in_slab_high), lot["hi"].y, on_plot, len(lot["pts"])))
    if high or in_slab_high:
        die("written Lot still holds building geometry")
    # The plot is flat paving: every up-facing Lot vertex inside it (5 cm in from its edges)
    # sits at PAVE_Y (the tile accents 3 mm above it are dropped), and nothing is higher.
    inner = [(p, n) for p, n in zip(lot["pts"], lot["nrm"])
             if px0 + 0.05 < p.x < px1 - 0.05 and pz0 + 0.05 < p.z < pz1 - 0.05]
    up_y = sorted({round(p.y, 4) for p, n in inner if n.y > 0.9})
    top = max(p.y for p, _n in inner)
    rep("LOT plot surface: up-facing heights inside the plot %s; highest point inside %.4f" % (up_y, top))
    if up_y != [PAVE_Y] or top > PAVE_Y + 1e-4:
        die("the plot is not flat paving at y %.2f" % PAVE_Y)
    # Coverage: a grid of 0.5 m samples over the plot; each must lie on an up-facing Lot
    # triangle at PAVE_Y or above (no hole, no dip, no bare strip).
    holes, n_samples = plot_holes(lot)
    rep("LOT plot coverage: %d of %d samples (0.25 m grid, 0.125 m in from the edges) without paving at y >= %.2f%s"
        % (len(holes), n_samples, PAVE_Y, (": first " + str(holes[:5])) if holes else ""))
    if holes:
        die("the plot has unpaved spots")
    # Every added face carries its intended normal in the written file.
    for corners, normal in added:
        for c in corners:
            if not any((p - c).length < 1e-4 and n.dot(normal) > 0.99 for p, n in zip(lot["pts"], lot["nrm"])):
                die("added face corner %s has no written vertex with normal %s" % (tuple(c), tuple(normal)))
    rep("LOT added faces: all %d carry their intended normal at every corner in the written file" % len(added))


main()
