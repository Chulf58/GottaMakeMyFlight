"""Build wall_belt_hatch.glb in the Toon Series interior kit.

Low rubber strip-curtain suitcase hatch cut through an interior plain wall,
sized so a baggage belt (BELT_TOP = 0.355 m, RAIL_TOP = 0.460 m, outer rails
x in [-0.42, 0.42]) passes cleanly through the bottom opening while the
hanging rubber strips stop just above the moving belt surface and guide rails.

Run from repo root:
  timeout 180 "/mnt/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" \\
    --background --factory-startup --python-exit-code 1 \\
    --python tools/blender/interior/build_wall_belt_hatch.py < /dev/null
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import build_interior_kit as kit  # noqa: E402

BELT_TOP = 0.355
RAIL_TOP = 0.460
HATCH_HALF_W = 0.422
HATCH_CLEAR_H = 1.120
FRAME_OUTER_W = 0.460
FRAME_TOP_H = 1.165
FRAME_HALF_D = 0.075
BAR_Z0 = 1.075
CLAMP_Z0 = 1.045
CENTER_FLAP_Z0 = BELT_TOP + 0.008
RAIL_FLAP_Z0 = RAIL_TOP + 0.008
FLAP_HALF_D = 0.012
CLAMP_HALF_D = 0.018

BLEND_OUT = os.path.join(kit.REPO, "tools", "blender", "out", "wall-belt-hatch", "wall_belt_hatch.blend")


def _flap(name, x0, x1, z0, root, c):
    kit.box(
        name + "_Clamp",
        (x0, -CLAMP_HALF_D, CLAMP_Z0),
        (x1, CLAMP_HALF_D, BAR_Z0),
        "metal",
        root,
        c,
    )
    kit.box(
        name,
        (x0, -FLAP_HALF_D, z0),
        (x1, FLAP_HALF_D, CLAMP_Z0),
        "dark",
        root,
        c,
        bevel=0.002,
    )


def build_wall_belt_hatch(root, c):
    for side, x0, x1 in (("L", -0.5, -FRAME_OUTER_W), ("R", FRAME_OUTER_W, 0.5)):
        kit.box(
            "Hatch_Skirting_" + side,
            (x0, -kit.TRIM_T / 2.0, 0.0),
            (x1, kit.TRIM_T / 2.0, 0.12),
            "trim",
            root,
            c,
        )
        kit.box(
            "Hatch_Jamb_" + side,
            (x0, -kit.WALL_T / 2.0, 0.12),
            (x1, kit.WALL_T / 2.0, kit.WALL_H - 0.06),
            "wall",
            root,
            c,
        )
    kit.box(
        "Hatch_Header",
        (-FRAME_OUTER_W, -kit.WALL_T / 2.0, FRAME_TOP_H),
        (FRAME_OUTER_W, kit.WALL_T / 2.0, kit.WALL_H - 0.06),
        "wall",
        root,
        c,
    )
    kit.box(
        "Hatch_Cap",
        (-0.5, -kit.TRIM_T / 2.0, kit.WALL_H - 0.06),
        (0.5, kit.TRIM_T / 2.0, kit.WALL_H),
        "trim",
        root,
        c,
    )

    for side, x0, x1 in (("L", -FRAME_OUTER_W, -HATCH_HALF_W), ("R", HATCH_HALF_W, FRAME_OUTER_W)):
        kit.box(
            "Hatch_Frame_" + side,
            (x0, -FRAME_HALF_D, 0.0),
            (x1, FRAME_HALF_D, HATCH_CLEAR_H),
            "frame",
            root,
            c,
            bevel=0.003,
        )
    kit.box(
        "Hatch_Frame_Top",
        (-FRAME_OUTER_W, -FRAME_HALF_D, HATCH_CLEAR_H),
        (FRAME_OUTER_W, FRAME_HALF_D, FRAME_TOP_H),
        "frame",
        root,
        c,
        bevel=0.003,
    )
    kit.box(
        "Hatch_Curtain_Bar",
        (-HATCH_HALF_W, -0.032, BAR_Z0),
        (HATCH_HALF_W, 0.032, HATCH_CLEAR_H),
        "metal",
        root,
        c,
    )

    _flap("Hatch_Flap_Rail_L", -0.415, -0.352, RAIL_FLAP_Z0, root, c)
    _flap("Hatch_Flap_Rail_R", 0.352, 0.415, RAIL_FLAP_Z0, root, c)
    for i, cx in enumerate((-0.276, -0.138, 0.0, 0.138, 0.276)):
        _flap("Hatch_Flap_%d" % i, cx - 0.061, cx + 0.061, CENTER_FLAP_Z0, root, c)


kit.PIECES["wall_belt_hatch"] = (
    build_wall_belt_hatch,
    "edge",
    (-0.5, -FRAME_HALF_D, 0.0),
    (0.5, FRAME_HALF_D, kit.WALL_H),
)


def main():
    kit.log("WALL_BELT_HATCH OUT_DIR=%s" % kit.OUT_DIR)
    kit.main(default_pieces=["wall_belt_hatch"], blend_out=BLEND_OUT)


if __name__ == "__main__":
    main()
