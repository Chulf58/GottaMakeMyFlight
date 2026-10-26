"""Convert the intro dialogue's airport manager (TCP_Male_Character_02: waistcoat, shirt
and tie) to a .glb OUTSIDE game/, for game/spike/manager_portrait_probe.gd to render.

    "/mnt/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background \
        --factory-startup --python 'C:\\Users\\chulf\\Gotta-make-my-flight\\tools\\blender\\manager_portrait_glb.py' \
        -- <out dir, Windows form, outside game/>

It runs convert_toon_batch.py's own convert() (prefab parts, atlas rebind, idle clip,
written-file checks) with one extra BATCH entry, so the manager is built exactly as the
passengers are. The game does not ship this .glb: only the rendered portrait PNG is
committed (game/assets/ui/intro_manager_portrait.png).
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
CONVERTER = os.path.join(HERE, "convert_toon_batch.py")
STEM = "tcp_male_character_02"
SPEC = (
    "TCP",
    "people",
    "TCP_Male_Character_02.fbx",
    "Poses\\TCP_Male_Idle_01.fbx",
    "Prefabs\\Male Character Sources\\TCP_Male_Character_02.prefab",
)


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    if len(argv) != 1:
        raise SystemExit("usage: -- <out dir outside game/>")
    with open(CONVERTER, encoding="utf-8") as f:
        source = f.read()
    # The converter calls main() at module level; load its functions without running it.
    body, tail = source.rsplit("\nmain()", 1)
    if tail.strip():
        raise SystemExit("convert_toon_batch.py no longer ends with main(); update this script")
    ns = {"__name__": "convert_toon_batch", "__file__": CONVERTER}
    exec(compile(body, CONVERTER, "exec"), ns)
    out_root = ns["out_dir_arg"](argv[0])
    ns["BATCH"][STEM] = SPEC
    ns["convert"](STEM, SPEC, out_root)
    print("MANAGER_GLB %s" % os.path.join(out_root, STEM + ".glb"))


main()
