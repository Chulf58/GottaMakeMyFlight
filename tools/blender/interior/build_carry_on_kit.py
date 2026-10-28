"""Build the carry-on bag kinds and export one .glb per kind.

Run (headless, reproducible):
  blender.exe --background --factory-startup --python-exit-code 1 --python \
    'C:\\Users\\chulf\\Gotta-make-my-flight\\tools\\blender\\interior\\build_carry_on_kit.py' [-- piece ...]

Ruling carry-on-bag-kinds-backpack-shoulder-or-tote-bag-small-rolle: carry-on comes in
several kinds, each carried its natural way. The hard hand case is carry_on_bag (built by
build_security_kit.py); this kit adds:
- carry_backpack: worn on the back. Its back panel (with two shoulder straps and the
  body side) is the bottom face, the front pocket faces up, the grab loop is at the top
  end (Godot +Z).
- carry_shoulder_bag: a tote hung from one shoulder. Lying flat its long side runs along
  Godot X, its top edge is at Godot +Z and its inner face (to the hip) is the bottom.
  The strap is two nodes: Strap_Reach (two strips, 0.02 long, that the game stretches
  along Godot +Z to reach the shoulder) and Strap_Top (the bar over the shoulder, moved
  to the strips' end).
- carry_roller: a small roller case. Lying flat its back panel (wheels, pull rods) is the
  bottom face and its top end is Godot +Z. The wheels' axle and the pull rods lie on one
  line, Godot (0, ROD_Y, z), so the game puts the axle on the floor and the grip in the
  hand on that line. The pull handle is Pull_Reach (two rods, 0.02 long, stretched along
  Godot +Z) and Pull_Top (the grip bar).
Every kind lies flat with its origin at the bottom centre, fits one security tray
(inner 0.41 x 0.57 m) at scale 1 and end to end at 0.55, like carry_on_bag.

The pieces use build_interior_kit.py's helpers and checks (every face on a measured Toon
atlas swatch, the written file re-read: nodes, materials, no images, bounds, UV
swatches). check_reach() re-reads each stretchable node's position from the written file.
"""

import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_activities_kit as act  # noqa: E402
import build_baggage_kit as bag  # noqa: E402
import build_cafe_kit as cafe  # noqa: E402
import build_interior_kit as kit  # noqa: E402
import build_security_kit as sec  # noqa: E402
import build_services_kit as svc  # noqa: E402

BLEND_OUT = os.path.join(kit.REPO, "tools", "blender", "out", "carry-on-kinds", "carry_on_kit.blend")

# Length of a stretchable strip or rod as built (Godot metres along +Z).
REACH_BUILT = 0.02
# Backpack (Blender x, y, z): width, length (top end at -y), thickness.
PACK = (0.30, 0.42, 0.15)
PACK_STRAP = 0.012
# Tote: long side, height (top edge at -y), thickness.
TOTE = (0.38, 0.28, 0.10)
# Strap strips run up from the top edge at x = +-TOTE_STRAP_X, mid-thickness.
TOTE_STRAP_X = 0.10
TOTE_STRAP_Z = TOTE[2] / 2.0
# Roller: width, length (top end at -y), thickness; wheels and rods on the back panel.
ROLLER = (0.32, 0.44, 0.20)
ROD_Y = 0.03  # Godot y (Blender z) of the axle and rod line
WHEEL_R = 0.03
ROD_X = 0.09


# piece -> {node name: Godot translation} of the stretchable nodes.
REACH_NODES = {
    "carry_backpack": {},
    "carry_shoulder_bag": {
        "Strap_Reach": (0.0, TOTE_STRAP_Z, TOTE[1] / 2.0),
        "Strap_Top": (0.0, TOTE_STRAP_Z, TOTE[1] / 2.0 + REACH_BUILT),
    },
    "carry_roller": {
        "Pull_Reach": (0.0, ROD_Y, ROLLER[1] / 2.0),
        "Pull_Top": (0.0, ROD_Y, ROLLER[1] / 2.0 + REACH_BUILT),
    },
}


def tbox(*a, **k):
    return cafe.tbox(*a, **k)


def reach_group(name, piece, root, c):
    """An empty at its Godot position (REACH_NODES) whose meshes join into <name>_Mesh;
    meshes under it are built in its own frame."""
    ob = cafe.group(name, root, c)
    gx, gy, gz = REACH_NODES[piece][name]
    ob.location = (gx, -gz, gy)
    return ob


# ---------------------------------------------------------------- pieces


def build_carry_backpack(root, c):
    w, ln, t = PACK
    hx, hy = w / 2.0, ln / 2.0
    s = PACK_STRAP
    # Body above the straps, rounded; a darker top band and a front pocket.
    tbox("Pack_Body", (-hx, -hy, s), (hx, hy, s + t), "red", root, c, bevel=0.035)
    tbox("Pack_Band", (-hx - 0.004, -hy + 0.02, s + 0.03), (hx + 0.004, -hy + 0.06, s + t - 0.02), "coffee",
         root, c)
    tbox("Pack_Pocket", (-0.11, -0.04, s + t - 0.01), (0.11, hy - 0.04, s + t + 0.04), "sage", root, c,
         bevel=0.015)
    tbox("Pack_Zip", (-0.09, -0.035, s + t + 0.04), (0.09, -0.02, s + t + 0.045), "dark", root, c)
    # Two shoulder straps on the back panel (the body side), a grab loop at the top end.
    for side, x in (("L", -0.08), ("R", 0.08)):
        tbox("Pack_Strap_" + side, (x - 0.022, -hy + 0.04, 0.0), (x + 0.022, hy - 0.05, s), "dark", root, c)
    tbox("Pack_Loop", (-0.04, -hy - 0.025, s + 0.05), (0.04, -hy, s + 0.09), "dark", root, c)


def build_carry_shoulder_bag(root, c):
    w, ln, t = TOTE
    hx, hy = w / 2.0, ln / 2.0
    tbox("Tote_Body", (-hx, -hy, 0.0), (hx, hy, t), "gold", root, c, bevel=0.02)
    tbox("Tote_Band", (-hx - 0.004, -hy + 0.03, 0.01), (hx + 0.004, -hy + 0.07, t - 0.01), "coffee", root, c)
    tbox("Tote_Patch", (-0.08, -0.02, t), (0.08, 0.08, t + 0.006), "cream", root, c)
    # The strap: strips from the top edge (stretched by the game) and the bar over them.
    reach = reach_group("Strap_Reach", "carry_shoulder_bag", root, c)
    for side, x in (("L", -TOTE_STRAP_X), ("R", TOTE_STRAP_X)):
        tbox("Strap_Strip_" + side, (x - 0.016, -REACH_BUILT, -0.01), (x + 0.016, 0.0, 0.01), "coffee", reach, c)
    top = reach_group("Strap_Top", "carry_shoulder_bag", root, c)
    tbox("Strap_Bar", (-TOTE_STRAP_X - 0.016, -0.02, -0.01), (TOTE_STRAP_X + 0.016, 0.0, 0.01), "coffee", top, c)
    tbox("Strap_Pad", (-0.05, -0.024, -0.012), (0.05, -0.004, 0.012), "dark", top, c)


def build_carry_roller(root, c):
    w, ln, t = ROLLER
    hx, hy = w / 2.0, ln / 2.0
    # Shell above the wheels' bottom; the top end is Blender -y, the wheels at +y.
    tbox("Roller_Shell", (-hx, -hy, 0.012), (hx, hy - 0.03, t), "sage", root, c, bevel=0.03)
    tbox("Roller_Rib", (-hx - 0.004, -0.03, 0.02), (hx + 0.004, 0.03, t - 0.008), "dark", root, c)
    for side, x in (("L", -hx + 0.03), ("R", hx - 0.03)):
        tbox("Roller_Guard_" + side, (x - 0.03, hy - 0.08, 0.0), (x + 0.03, hy - 0.02, 0.06), "dark", root, c)
    # Carry handle on the front panel near the top end.
    tbox("Roller_Handle", (-0.06, -hy + 0.04, t), (0.06, -hy + 0.07, t + 0.025), "dark", root, c)
    # Wheels on the axle line (Blender z = ROD_Y), at the bottom end.
    for side, x in (("L", -0.12), ("R", 0.12)):
        bag.cyl_x("Roller_Wheel_" + side, x - 0.018, x + 0.018, hy - WHEEL_R, ROD_Y, WHEEL_R, "dark", root, c)
    # The pull handle: rods along the back panel on the axle line, and the grip bar.
    reach = reach_group("Pull_Reach", "carry_roller", root, c)
    for side, x in (("L", -ROD_X), ("R", ROD_X)):
        tbox("Pull_Rod_" + side, (x - 0.01, -REACH_BUILT, -0.01), (x + 0.01, 0.0, 0.01), "metal", reach, c)
    top = reach_group("Pull_Top", "carry_roller", root, c)
    tbox("Pull_Bar", (-ROD_X - 0.012, -0.03, -0.014), (ROD_X + 0.012, 0.0, 0.014), "dark", top, c)
    tbox("Pull_Cap", (-0.05, -0.034, -0.016), (0.05, -0.004, 0.016), "metal", top, c)


# piece -> (builder, footprint, expected Blender bounds lo/hi).
PIECES = {
    "carry_backpack": (build_carry_backpack, None, (-0.154, -0.235, 0.0), (0.154, 0.21, 0.207)),
    "carry_shoulder_bag": (build_carry_shoulder_bag, None, (-0.194, -0.184, -0.0), (0.194, 0.14, 0.106)),
    "carry_roller": (build_carry_roller, None, (-0.164, -0.274, 0.0), (0.164, 0.22, 0.225)),
}


def extra_nodes(piece):
    names = []
    for n in REACH_NODES[piece]:
        names += [n, n + "_Mesh"]
    return sorted(names)


EXTRA_NODES = {p: extra_nodes(p) for p in PIECES}


def requested():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    return argv or list(PIECES)


def guard(pieces):
    """Refuse a piece outside this kit, a name another kit owns, or an existing .glb that
    is not this builder's piece."""
    bad = [p for p in pieces if p not in PIECES]
    if bad:
        kit.fail("refusing pieces outside the carry-on kit: %s" % bad)
    others = (set(kit.PIECES) | set(cafe.PIECES) | set(act.PIECES) | set(svc.PIECES) | set(bag.PIECES)
              | set(sec.PIECES))
    taken = sorted(others & set(PIECES))
    if taken:
        kit.fail("carry-on names already owned by another kit: %s" % taken)
    for p in pieces:
        out = os.path.join(kit.OUT_DIR, p + ".glb")
        if not os.path.exists(out):
            kit.log("GUARD %s new file %s" % (p, out))
            continue
        js, _n = kit.parse_glb(out)
        names = {n.get("name") for n in js.get("nodes", [])}
        own = kit.piece_title(p) + "_ROOT" in names and set(EXTRA_NODES.get(p, [])) <= names
        kit.log("GUARD %s existing file own=%s" % (p, own))
        if not own:
            kit.fail("%s exists and is not this builder's piece; not overwriting" % out)
    if kit.FAILS:
        sys.exit(1)


def register():
    kit.PALETTE.update(cafe.CAFE_PALETTE)
    kit.PIECES.update(PIECES)
    kit.EXTRA_NODES.update(EXTRA_NODES)
    for nodes in REACH_NODES.values():
        for name, pos in nodes.items():
            kit.NODE_TRANSLATIONS[name] = pos


def check_reach(written):
    """Each stretchable node in the written file, at its position, unrotated and
    unscaled, with its mesh child."""
    for piece, out in written:
        js, _n = kit.parse_glb(out)
        by_name = {n.get("name"): n for n in js.get("nodes", [])}
        for name, pos in REACH_NODES[piece].items():
            node = by_name.get(name)
            if node is None:
                kit.fail("%s: %s missing from the written file" % (piece, name))
                continue
            t = node.get("translation", [0.0, 0.0, 0.0])
            kids = [js["nodes"][i].get("name") for i in node.get("children", [])]
            kit.log("REACH %s %s pos=(%.3f, %.3f, %.3f) rotation=%s scale=%s children=%s"
                    % (piece, name, t[0], t[1], t[2], node.get("rotation"), node.get("scale"), kids))
            if max(abs(a - b) for a, b in zip(t, pos)) > 1e-4 or "rotation" in node or "scale" in node:
                kit.fail("%s: %s at %s, expected %s unrotated, unscaled" % (piece, name, t, pos))
            if kids != [name + "_Mesh"]:
                kit.fail("%s: %s children %s" % (piece, name, kids))
    kit.log("CARRY_ON done pieces=%d fails=%d" % (len(written), len(kit.FAILS)))
    if kit.FAILS:
        sys.exit(1)


if __name__ == "__main__":
    wanted = requested()
    guard(wanted)
    register()
    check_reach(kit.main(default_pieces=wanted, blend_out=BLEND_OUT))
