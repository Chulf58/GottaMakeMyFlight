"""Build and export the 2-cell industrial Roll-Up Bay Door piece (game/assets/interior/baggage_bay_door.glb).

Footprint: 2x1 cells along wall X (x in [-1.0, +1.0]), centered on the wall edge (y = 0.0),
height WALL_H = 2.50 m matching wall.glb and wall_post.glb.
Orientation: Blender -y (Godot +Z) is inside the Bag Room; Blender +y (Godot -Z) is the
apron exterior (with the roll-up drum hood, safety bumper bollards, and flush threshold stripes).

Run headless:
  "/mnt/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" \\
    --background --factory-startup --python-exit-code 1 \\
    --python tools/blender/interior/build_baggage_bay_door.py < /dev/null
"""

import os
import sys

import bmesh
import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import build_interior_kit as kit  # noqa: E402

REPO = kit.REPO
OUT_DIR = kit.OUT_DIR
BLEND_OUT = os.path.join(REPO, "tools", "blender", "out", "baggage-bay-door", "baggage_bay_door.blend")
PIECE = "baggage_bay_door"

WALL_H = kit.WALL_H
WALL_T = kit.WALL_T
TRIM_T = kit.TRIM_T
HALF_W = 1.0
OPEN_HALF_W = 0.75
SHUTTER_CLEAR_H = 1.815

# Tight opening box a 0.90 m wide, 1.62 m tall cart / 1.76 m ramp agent passes through.
CLEARANCE_LO = Vector((-0.72, -0.25, 0.02))
CLEARANCE_HI = Vector((0.72, 0.40, 1.80))


def _box_hits_clearance(bm):
    for v in bm.verts:
        p = v.co
        if (
            CLEARANCE_LO.x < p.x < CLEARANCE_HI.x
            and CLEARANCE_LO.y < p.y < CLEARANCE_HI.y
            and CLEARANCE_LO.z < p.z < CLEARANCE_HI.z
        ):
            return True
    return False


def build_baggage_bay_door(root, c):
    # Outer wall jambs & seamless cap/skirting matching neighboring build_wall panels ([-1.0, +1.0]).
    for side, x0, x1 in (("L", -HALF_W, -0.80), ("R", 0.80, HALF_W)):
        kit.box("Bay_Jamb_" + side, (x0, -WALL_T / 2, 0.12), (x1, WALL_T / 2, WALL_H - 0.06), "wall", root, c)
        kit.box("Bay_Skirting_" + side, (x0, -TRIM_T / 2, 0.0), (x1, TRIM_T / 2, 0.12), "trim", root, c)
    kit.box("Bay_Lintel_Wall", (-0.80, -WALL_T / 2, 2.34), (0.80, WALL_T / 2, WALL_H - 0.06), "wall", root, c)
    kit.box("Bay_Top_Cap", (-HALF_W, -TRIM_T / 2, WALL_H - 0.06), (HALF_W, TRIM_T / 2, WALL_H), "trim", root, c)

    # Heavy steel door jamb frames & recessed side guide tracks.
    for side, s in (("L", -1.0), ("R", 1.0)):
        jx0, jx1 = sorted((s * 0.75, s * 0.82))
        kit.box("Bay_Frame_" + side, (jx0, -0.095, 0.0), (jx1, 0.095, WALL_H - 0.06), "frame", root, c)
        tx0, tx1 = sorted((s * 0.725, s * 0.755))
        kit.box("Bay_Track_" + side, (tx0, -0.045, 0.01), (tx1, 0.045, 2.12), "dark", root, c)
    kit.box("Bay_Frame_Lintel", (-0.82, -0.095, 2.09), (0.82, 0.095, 2.15), "frame", root, c)

    # Exterior-facing (+y) industrial roll-up drum hood & drive end-caps (compact 0.18 m overhang
    # so horizontal shutter slats stay cleanly visible beneath the drum at tycoon camera pitch).
    kit.box("Bay_Hood_Body", (-0.84, -0.105, 2.11), (0.84, 0.180, 2.41), "frame", root, c, bevel=0.018)
    for side, s in (("L", -1.0), ("R", 1.0)):
        cx0, cx1 = sorted((s * 0.82, s * 0.88))
        kit.box("Bay_Hood_EndCap_" + side, (cx0, -0.065, 2.13), (cx1, 0.170, 2.39), "dark", root, c, bevel=0.012)
    kit.box("Bay_Hood_Fascia_Stripe", (-0.80, 0.170, 2.14), (0.80, 0.192, 2.19), "yellow", root, c)
    kit.box("Bay_Hood_Plate", (-0.38, 0.170, 2.23), (0.38, 0.192, 2.35), "dark", root, c)
    for idx, xc in enumerate((-0.24, 0.0, 0.24)):
        kit.box("Bay_Hood_PlateMark_%d" % idx, (xc - 0.07, 0.185, 2.26), (xc + 0.07, 0.198, 2.32), "yellow", root, c)
    # Interior header safety stripe (-y) so the door opening also reads from inside the Bag Room.
    kit.box("Bay_Hood_InteriorStripe", (-0.75, -0.118, 2.11), (0.75, -0.098, 2.16), "yellow", root, c)

    # Partially rolled-up horizontal corrugated shutter slats ([1.815, 2.11], clearing 1.62 m carts).
    slats = (
        (2.045, 2.110, 0.055, "white"),
        (1.980, 2.045, 0.042, "metal"),
        (1.915, 1.980, 0.058, "white"),
        (1.850, 1.915, 0.042, "metal"),
    )
    for idx, (z0, z1, hy, pal) in enumerate(slats):
        kit.box("Bay_Shutter_Slat_%d" % idx, (-0.735, -hy, z0), (0.735, hy, z1), pal, root, c)
    kit.box("Bay_Shutter_BottomBar", (-0.735, -0.056, SHUTTER_CLEAR_H), (0.735, 0.064, 1.850), "dark", root, c)
    kit.box("Bay_Shutter_BottomHazardOut", (-0.72, 0.058, 1.820), (0.72, 0.072, 1.844), "yellow", root, c)
    kit.box("Bay_Shutter_BottomHazardIn", (-0.72, -0.064, 1.820), (0.72, -0.050, 1.844), "yellow", root, c)

    # Yellow & dark steel bumper bollards bolted to exterior apron jambs (+y).
    for side, s in (("L", -1.0), ("R", 1.0)):
        bx = s * 0.86
        by = 0.23
        px0, px1 = sorted((bx - 0.095, bx + 0.095))
        kit.box("Bay_Bollard_Plate_" + side, (px0, 0.09, 0.0), (px1, 0.34, 0.025), "dark", root, c)
        kit.cyl("Bay_Bollard_Collar_" + side, bx, by, 0.025, 0.13, 0.072, "dark", root, c, segs=10)
        kit.cyl("Bay_Bollard_Post_" + side, bx, by, 0.13, 0.65, 0.060, "yellow", root, c, segs=10)
        kit.cyl("Bay_Bollard_Band_" + side, bx, by, 0.65, 0.73, 0.062, "dark", root, c, segs=10)
        kit.cyl("Bay_Bollard_Top_" + side, bx, by, 0.73, 0.85, 0.060, "yellow", root, c, segs=10)
        kit.cyl("Bay_Bollard_Cap_" + side, bx, by, 0.85, 0.875, 0.044, "dark", root, c, segs=10)
        # Heavy strut connecting the post back to the frame jamb so it anchors structurally.
        sx0, sx1 = sorted((bx - 0.025, bx + 0.025))
        kit.box("Bay_Bollard_Strut_" + side, (sx0, 0.085, 0.48), (sx1, by, 0.54), "frame", root, c)

    # Flush threshold sill + <= 6 mm exterior safety threshold apron bars.
    kit.box("Bay_Threshold_Sill", (-0.75, -0.08, 0.0), (0.75, 0.08, 0.010), "dark", root, c)
    kit.box("Bay_Apron_Strip", (-0.77, 0.08, 0.0), (0.77, 0.26, 0.004), "dark", root, c)
    for idx, xc in enumerate((-0.54, -0.27, 0.0, 0.27, 0.54)):
        kit.box("Bay_Apron_Dash_%d" % idx, (xc - 0.08, 0.105, 0.004), (xc + 0.08, 0.235, 0.006), "yellow", root, c)


def register():
    kit.PIECES[PIECE] = (build_baggage_bay_door, "edge", (-HALF_W, -0.118, 0.0), (HALF_W, 0.340, WALL_H))


def verify_written(glb_path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=glb_path)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    assert meshes, "%s: no mesh objects after re-import" % glb_path
    assert len(bpy.data.images) == 0, "%s: expected 0 embedded images, found %d" % (
        glb_path, len(bpy.data.images)
    )
    mats = set()
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for ob in meshes:
        for slot in ob.material_slots:
            if slot.material:
                mats.add(slot.material.name)
        assert ob.data.uv_layers, "%s: mesh %s lacks UV layer" % (glb_path, ob.name)
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        bmesh.ops.transform(bm, matrix=ob.matrix_world, verts=bm.verts)
        assert not _box_hits_clearance(bm), "%s: geometry in %s enters cart/agent clearance box!" % (
            glb_path, ob.name
        )
        for v in bm.verts:
            for k in range(3):
                lo[k] = min(lo[k], v.co[k])
                hi[k] = max(hi[k], v.co[k])
        bm.free()
    # GLTF Y-up re-import into Blender transforms Godot (x, y, z) -> Blender (x, -z, y),
    # matching the original Blender coordinates of the authored piece.
    assert mats == {"TP_Atlas_1A_D"}, "%s: unexpected materials %s" % (glb_path, sorted(mats))
    assert abs(lo.x - (-HALF_W)) < 0.01 and abs(hi.x - HALF_W) < 0.01, "width mismatch: %.3f..%.3f" % (lo.x, hi.x)
    assert abs(lo.z - 0.0) < 0.01 and abs(hi.z - WALL_H) < 0.01, "height mismatch: %.3f..%.3f" % (lo.z, hi.z)
    assert abs(hi.y - 0.34) < 0.02 and lo.y >= -0.15, "depth mismatch: %.3f..%.3f" % (lo.y, hi.y)
    print(
        "VERIFIED %s meshes=%d images=%d materials=%s bounds=(%.3f..%.3f, %.3f..%.3f, %.3f..%.3f)"
        % (glb_path, len(meshes), len(bpy.data.images), sorted(mats), lo.x, hi.x, lo.y, hi.y, lo.z, hi.z),
        flush=True,
    )


def main():
    register()
    os.makedirs(os.path.dirname(BLEND_OUT), exist_ok=True)
    written = kit.main(default_pieces=[PIECE], blend_out=BLEND_OUT)
    for _p, out in written:
        verify_written(out)


if __name__ == "__main__":
    main()
