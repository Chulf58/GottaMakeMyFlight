"""Convert a phone dialog speaker's body to a .glb OUTSIDE game/, for a portrait probe to
render. Two speakers (IntroDialogue.Speakers):

- terminal_manager (the default): the intro dialogue's airport manager,
  TCP_Male_Character_02 (waistcoat, shirt and tie), rendered by
  game/spike/manager_portrait_probe.gd to game/assets/ui/intro_manager_portrait.png.
- station_manager: Gotta Air's station manager for the airline's opening call (decision
  the-airline-s-opening-phone-call-shows-a-new-gotta-air-stati), TCP_Female_Character_07
  (skirt suit), rendered by game/assets/ui/station_manager_portrait_probe.gd, which
  recolours the suit in Gotta Air's livery, to game/assets/ui/station_manager_portrait.png.

    "/mnt/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background \
        --factory-startup --python 'C:\\Users\\chulf\\Gotta-make-my-flight\\tools\\blender\\manager_portrait_glb.py' \
        -- <out dir, Windows form, outside game/> [terminal_manager|station_manager]

It runs convert_toon_batch.py's own convert() (prefab parts, atlas rebind, idle clip,
clothes' mark, written-file checks) with one extra BATCH entry, so the speaker is built
exactly as the passengers are. The game does not ship this .glb: only the rendered
portrait PNG is committed.
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
CONVERTER = os.path.join(HERE, "convert_toon_batch.py")
# Speaker -> (stem, BATCH spec).
SPEAKERS = {
    "terminal_manager": (
        "tcp_male_character_02",
        (
            "TCP",
            "people",
            "TCP_Male_Character_02.fbx",
            "Poses\\TCP_Male_Idle_01.fbx",
            "Prefabs\\Male Character Sources\\TCP_Male_Character_02.prefab",
        ),
    ),
    "station_manager": (
        "tcp_female_character_07",
        (
            "TCP",
            "people",
            "TCP_Female_Character_07.fbx",
            "Poses\\TCP_Female_Idle_01.fbx",
            "Prefabs\\Female Character Sources\\TCP_Female_Character_07.prefab",
        ),
    ),
}


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    if len(argv) not in (1, 2) or (len(argv) == 2 and argv[1] not in SPEAKERS):
        raise SystemExit("usage: -- <out dir outside game/> [%s]" % "|".join(SPEAKERS))
    speaker = argv[1] if len(argv) == 2 else "terminal_manager"
    stem, spec = SPEAKERS[speaker]
    with open(CONVERTER, encoding="utf-8") as f:
        source = f.read()
    # The converter calls main() at module level; load its functions without running it.
    body, tail = source.rsplit("\nmain()", 1)
    if tail.strip():
        raise SystemExit("convert_toon_batch.py no longer ends with main(); update this script")
    ns = {"__name__": "convert_toon_batch", "__file__": CONVERTER}
    exec(compile(body, CONVERTER, "exec"), ns)
    out_root = ns["out_dir_arg"](argv[0])
    ns["BATCH"][stem] = spec
    ns["convert"](stem, spec, out_root)
    print("MANAGER_GLB %s %s" % (speaker, os.path.join(out_root, stem + ".glb")))


main()
