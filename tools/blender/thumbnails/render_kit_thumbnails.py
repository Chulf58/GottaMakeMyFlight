"""Render one square build-menu thumbnail per placeable build item.

Run (headless, reproducible):
  blender.exe --background --factory-startup --python-exit-code 1 --python \
    'C:\\Users\\chulf\\Gotta-make-my-flight\\tools\\blender\\thumbnails\\render_kit_thumbnails.py' \
    [-- --force] [-- item ...]

Each item is drawn from its interior kit .glb in game/assets/interior/ (the pieces
game/build/view/interior_kit.gd uses), or for a piece named with a folder
("landside/tp_curb_bay_01a") from that .glb under game/assets/, framed by one orthographic 3/4 camera at a
fixed direction, at one scale per footprint class, on a transparent background.
Writes 256x256 PNGs to game/assets/ui/thumbnails/<item>.png and a manifest of the
source .glb hashes there; an item re-renders only when a source hash (or STYLE)
changes, or with --force. The contact sheet goes to
tools/blender/out/thumbnails/contact_sheet.png (gitignored).

Toon look: the glTF carries no images, so every material is rebound by name to its
atlas in game/assets/textures/. Surfaces are shaded with an emission-only node tree
that copies game/shaders/toon.gdshader: albedo times (the vendor ramp looked up at
the half-Lambert term of the game's sun direction, plus a flat ambient). No specular,
no PBR. Lights are unshaded, glass is the atlas gradient at the game's 0.29 alpha.
The outline is Freestyle at a fixed pixel width in the game's outline colour.

Every thumbnail proves its subject is in frame (all vertices projected inside a
margin) and big enough before it is saved; otherwise PROBE_INVALID and exit 1.
"""

import hashlib
import json
import math
import os
import sys

import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
ASSETS_DIR = os.path.join(REPO, "game", "assets")
KIT_DIR = os.path.join(ASSETS_DIR, "interior")
TEXTURES = os.path.join(REPO, "game", "assets", "textures")
OUT_DIR = os.path.join(REPO, "game", "assets", "ui", "thumbnails")
MANIFEST = os.path.join(OUT_DIR, "manifest.json")
SHEET_DIR = os.path.join(REPO, "tools", "blender", "out", "thumbnails")
SHEET = os.path.join(SHEET_DIR, "contact_sheet.png")

# Bump when the look or framing changes, so every thumbnail re-renders.
STYLE = 3
SIZE = 256
SUPERSAMPLE = 2  # render at SIZE * SUPERSAMPLE, scale down: smoother outline
MARGIN = 0.05  # every vertex lands this far inside the frame (fraction)
MIN_SHARE = 0.45  # the subject spans at least this much of the frame's width or height

# Camera: front-left 3/4, looking down 30 degrees. Godot +Z (the front) is Blender -Y.
CAM_AZIMUTH = math.radians(-35.0)  # from the front (-Y), towards -X
CAM_ELEVATION = math.radians(30.0)
# Toward the light, from the game's Sun (main.tscn) converted to Blender axes.
SUN = Vector((0.354, -0.612, 0.707)).normalized()
AMBIENT = 0.24  # flat stand-in for the game sky ambient
LIGHT_GAIN = 0.76  # sun share; lit faces land at albedo x 1.0 with no tonemapper
OUTLINE_RGB = (0.1, 0.1, 0.12)  # toon_outline outline_color
OUTLINE_PX = 1.5  # toon_outline outline_px, at the final size

ATLAS_PNG = {
    "TP_Atlas_1A_D": "tp_atlas_1a_d.png",
    # The converted Toon packs: the simple atlas is the same image
    # (tp_atlas_simple_toon.tres); the multi-storey has its own texture and ramp.
    "TP_Atlas_Simple_1A_D": "tp_atlas_1a_d.png",
    "TC_Building_17A_D": "tc_building_17a_d.png",
    # The Toon City decor models (game/assets/decor/), each its own atlas.
    "TC_Road_1A_D": "tc_road_1a_d.png",
    "TC_Tree_1A_D": "tc_tree_1a_d.png",
    "TC_Tree_3A_D": "tc_tree_3a_d.png",
    "TC_Props_2A_D": "tc_props_2a_d.png",
    "TC_Building_4A_D": "tc_building_4a_d.png",
    "TP_Atlas_Lights_1A_D": "tp_atlas_lights_1a_d.png",
    "TP_Glass_1A_D": "tp_glass_gradient_1a_d.png",
}
RAMP_PNG = "tp_toon_ramp_1d_d.png"
# Materials whose toon ramp is not the TP one (tc_building_17a_toon.tres and the
# other Toon City materials in game/assets/materials/).
TC_RAMP = "tc_toon_ramp_01a_d.png"
TOON_MATERIALS = (
    "TP_Atlas_1A_D",
    "TP_Atlas_Simple_1A_D",
    "TC_Building_17A_D",
    "TC_Road_1A_D",
    "TC_Tree_1A_D",
    "TC_Tree_3A_D",
    "TC_Props_2A_D",
    "TC_Building_4A_D",
)
RAMP_FOR = {name: TC_RAMP for name in TOON_MATERIALS if name.startswith("TC_")}
GLASS_ALPHA = 0.29  # tp_glass.tres albedo alpha
GLASS_TINT = 0.85

# Footprint class -> nominal box (width X, depth Y, height Z) in metres, with the
# box centre's offset from the piece origin. One class, one camera scale.
CLASSES = {
    "tile": ((1.0, 1.0, 0.25), (0.0, 0.0, 0.0)),
    "edge": ((1.2, 0.2, 2.6), (0.0, 0.0, 1.3)),
    "door_1x1": ((1.1, 1.1, 2.5), (0.0, 0.0, 1.25)),
    "2x1": ((2.0, 1.0, 1.6), (0.0, 0.0, 0.8)),
    "1x2": ((1.0, 2.0, 2.3), (0.0, 0.0, 1.15)),
    "3x1": ((3.0, 1.0, 1.0), (0.0, 0.0, 0.5)),
    "3x2": ((3.0, 2.0, 0.5), (0.0, 0.0, 0.25)),
    "2x2": ((2.0, 2.0, 1.7), (0.0, 0.0, 0.85)),
    "1x1": ((1.0, 1.0, 1.6), (0.0, 0.0, 0.8)),
    "1x1_tall": ((1.0, 1.0, 2.0), (0.0, 0.0, 1.0)),
    "2x1_tall": ((2.0, 1.0, 2.1), (0.0, 0.0, 1.05)),
    "3x3": ((3.0, 3.0, 2.0), (0.0, 0.0, 1.0)),
    "2x3": ((2.0, 3.0, 2.2), (0.0, 0.0, 1.1)),
    # The duty free and fashion rooms (3x4 min, F4-5): three wide, four deep.
    "3x4": ((3.0, 4.0, 2.1), (0.0, 0.0, 1.05)),
    # Furniture (Furniture 4/4 F4-2): the 29 placeable pieces, each in the class of
    # its footprint and height; the tall classes are for pieces over 2 m.
    "1x3": ((1.0, 3.0, 1.4), (0.0, 0.0, 0.7)),
    "1x2_plant": ((1.0, 2.0, 2.3), (0.0, 0.0, 1.15)),
    "4x4": ((4.0, 4.0, 2.4), (0.0, 0.0, 1.2)),
    "6x3": ((6.0, 3.0, 2.3), (0.0, 0.0, 1.15)),
    "2x2_tall": ((2.0, 2.0, 2.4), (0.0, 0.0, 1.2)),
    "1x1_xtall": ((1.0, 1.0, 2.4), (0.0, 0.0, 1.2)),
    "2x1_xtall": ((2.0, 1.0, 2.3), (0.0, 0.0, 1.15)),
    # Landside (Landside 4/4), at their own scale: the 16 x 3 m curb bay on its
    # strip of road (Godot +Z into the road is Blender -Y), the 32.3 x 24 m surface
    # lot (local x -7.3 to 25), the 24 x 52 x 28.3 m multi-storey and the lot's two
    # barrier arms at its barrier line (local x -7).
    "bay": ((17.0, 4.6, 2.0), (0.0, -1.9, 1.0)),
    "lot": ((32.3, 24.0, 3.0), (8.85, 0.0, 1.5)),
    "multi": ((24.0, 52.0, 28.35), (0.0, 0.0, 14.17)),
    "gate": ((1.0, 15.0, 2.0), (-7.0, 0.0, 1.0)),
}
# The converted Toon assets import with every face its own island (split vertices),
# so border lines would outline every triangle and crease lines are denser than the
# pixels between them at tens of metres per frame: both grey the picture out. Their
# classes draw silhouette lines only, like the game's outline hull.
# The foliage classes (the tree bench, the planter, the trees) are the same: their
# leaves are many small faces and the crease lines turn them into a grey blob.
NO_CREASE_CLASSES = {"bay", "lot", "multi", "gate", "4x4", "1x2_plant", "2x2_tall"}

# Catalog colours (build_catalog.gd), sRGB.
ENTRANCE_RGB = (0.35, 0.7, 0.4)
EXIT_RGB = (0.3, 0.55, 0.85)
REMOVE_RGB = (0.86, 0.18, 0.16)
# Under the curb bay thumbnail, a strip of road and sidewalk in the shell's road
# and kerb greys (by eye, from the landside plates); the barrier posts.
ROAD_RGB = (0.36, 0.37, 0.4)
SIDEWALK_RGB = (0.74, 0.73, 0.7)
POST_RGB = (0.28, 0.28, 0.3)

# item -> (footprint class, main piece, extras). Extras are glyphs this script
# builds. A piece entry is a name, or (name, offset[, yaw[, keep]]); the offset is a
# Blender (x, y, z), or the name of a Mount_ empty of an earlier piece of the item,
# which the piece then stands on, turned the way the mount points. Entrance and exit draw wall_door on their back edge (Godot -Z 0.5, Blender
# +Y 0.5), as InteriorKit.OBJECT_OFFSETS does, over a floor tile.
ITEMS = {
    "floor": ("tile", ["floor_tile"], []),
    "wall": ("edge", ["wall"], []),
    "glass": ("edge", ["wall_glass"], []),
    "door": ("edge", ["wall_door"], []),
    "desk": ("2x1", ["checkin_desk"], []),
    "scanner": ("1x2", ["security_scanner"], []),
    "seats": ("3x1", ["seat_row"], []),
    "entrance": ("door_1x1", ["floor_tile", ("wall_door", (0.0, 0.5, 0.0))], ["arrow_in"]),
    "exit": ("door_1x1", ["floor_tile", ("wall_door", (0.0, 0.5, 0.0))], ["arrow_out"]),
    "remove": ("tile", ["floor_tile"], ["cross"]),
    # Baggage (decision baggage-belts-are-one-auto-shaping-belt-tool-one-baggage-tray).
    # Belt: the shapes the Belt tool lays, two straights along Godot X, a corner
    # (facing 1) and one straight coming toward the camera, as BeltShaper shapes them.
    # A Godot facing f is a Blender Z turn of -90 f degrees; Godot +Z is Blender -Y.
    "belt": (
        "3x2",
        [
            ("baggage_belt", (-1.0, 0.5, 0.0), -90.0),
            ("baggage_belt", (0.0, 0.5, 0.0), -90.0),
            ("baggage_belt_corner", (1.0, 0.5, 0.0), -90.0),
            ("baggage_belt", (1.0, -0.5, 0.0), 0.0),
        ],
        [],
    ),
    "cart": ("1x2", ["baggage_cart"], []),
    # Bag room (conductor ruling): a 2x2 floor with a belt end and a cart.
    "bag_room": (
        "2x2",
        [
            ("floor_tile", (-0.5, -0.5, 0.0)),
            ("floor_tile", (0.5, -0.5, 0.0)),
            ("floor_tile", (-0.5, 0.5, 0.0)),
            ("floor_tile", (0.5, 0.5, 0.0)),
            ("baggage_belt_end", (-0.5, -0.5, 0.0)),
            ("baggage_cart", (0.5, 0.0, 0.0)),
        ],
        [],
    ),
    # Security lane parts, the Lane tray (decision security-lane-parts-get-their-own-
    # lane-build-category-next-t), each 1x1. The arch is as tall as a door.
    "tray_table": ("1x1", ["tray_table"], []),
    "xray_belt": ("1x1", ["xray_belt"], []),
    "arch": ("door_1x1", ["security_arch"], []),
    "pickup_table": ("1x1", ["pickup_table"], []),
    # Toilet pieces (decision toilet-design-queue-free-reservable-stalls-per-stall-daily-u):
    # the 1x2 stall with its doors closed and the sink with its 1.95 m mirror.
    "toilet_stall": ("1x2", ["toilet_stall"], []),
    "toilet_sink": ("1x1_tall", ["toilet_sink"], []),
    # Cafe pieces: the 2x1 counter is 1.98 m to its menu board, so it gets a
    # taller box than the check-in desk's; the 3x1 table with its two chairs.
    "counter": ("2x1_tall", ["cafe_counter"], []),
    "table": ("3x1", ["cafe_table"], []),
    # Rooms, as the bag room: the room tool's minimum floor, furnished with what
    # makes it ready, every interaction and seat approach cell on the floor and
    # clear. Cafe room (3x3 min): the counter across the back-right two cells
    # (order spot: the middle cell), the table across the front row at facing 2,
    # so its chairs are reached from the middle row's outer cells.
    "cafe_room": (
        "3x3",
        [
            ("floor_tile", (-1.0, -1.0, 0.0)),
            ("floor_tile", (0.0, -1.0, 0.0)),
            ("floor_tile", (1.0, -1.0, 0.0)),
            ("floor_tile", (-1.0, 0.0, 0.0)),
            ("floor_tile", (0.0, 0.0, 0.0)),
            ("floor_tile", (1.0, 0.0, 0.0)),
            ("floor_tile", (-1.0, 1.0, 0.0)),
            ("floor_tile", (0.0, 1.0, 0.0)),
            ("floor_tile", (1.0, 1.0, 0.0)),
            ("cafe_counter", (0.5, 1.0, 0.0)),
            ("cafe_table", (0.0, -1.0, 0.0), -180.0),
        ],
        [],
    ),
    # Toilet room (2x3 min): the sink in the back-left cell and the stall down the
    # right column's back two cells, so the 2.1 m stall does not hide the sink from
    # the front-left camera.
    "toilet_room": (
        "2x3",
        [
            ("floor_tile", (-0.5, -1.0, 0.0)),
            ("floor_tile", (0.5, -1.0, 0.0)),
            ("floor_tile", (-0.5, 0.0, 0.0)),
            ("floor_tile", (0.5, 0.0, 0.0)),
            ("floor_tile", (-0.5, 1.0, 0.0)),
            ("floor_tile", (0.5, 1.0, 0.0)),
            ("toilet_sink", (-0.5, 1.0, 0.0)),
            ("toilet_stall", (0.5, 0.5, 0.0)),
        ],
        [],
    ),
    # Kiosk pieces (Boredom 5/5, build_kiosk_kit.py): the counter is 1.99 m to its
    # canopy and the display 1.68 m, so both take the tall 2x1 box.
    "kiosk_counter": ("2x1_tall", ["kiosk_counter"], []),
    "kiosk_display": ("2x1_tall", ["kiosk_display"], []),
    # Kiosk room (3x3 min): the counter across the back row's left two cells facing
    # front, its till cell the middle row's left cell; the display down the right
    # column's front two cells facing Godot -X, its browse slots the centre column's
    # middle (slot 0) and front (slot 1) cells. Every interaction and browse cell is
    # distinct and clear, and both fronts face the front-left camera.
    "kiosk_room": (
        "3x3",
        [
            ("floor_tile", (-1.0, -1.0, 0.0)),
            ("floor_tile", (0.0, -1.0, 0.0)),
            ("floor_tile", (1.0, -1.0, 0.0)),
            ("floor_tile", (-1.0, 0.0, 0.0)),
            ("floor_tile", (0.0, 0.0, 0.0)),
            ("floor_tile", (1.0, 0.0, 0.0)),
            ("floor_tile", (-1.0, 1.0, 0.0)),
            ("floor_tile", (0.0, 1.0, 0.0)),
            ("floor_tile", (1.0, 1.0, 0.0)),
            ("kiosk_counter", (-0.5, 1.0, 0.0)),
            ("kiosk_display", (1.0, -0.5, 0.0), -90.0),
        ],
        [],
    ),
    # The boredom screen stand (one floor cell, its picture to the front).
    "screen_stand": ("1x1_tall", ["screen_stand"], []),
    # Landside (Landside 4/4). A piece is (name, Blender offset, Blender Z turn
    # in degrees[, the mesh objects to keep]); a car's nose (Godot +Z, Blender -Y)
    # turned -90 points along Blender -X, the way the near carriageway drives.
    # Curb bay: the bay on its road strip, a taxi in its west berth (Mount_Berth_1).
    "curb_bay": (
        "bay",
        [
            ("landside/tp_curb_bay_01a", (0.0, 0.0, 0.0), 0.0),
            ("vehicles/tp_taxi_01a", (-3.25, -1.5, 0.02), -90.0),
        ],
        ["road_strip"],
    ),
    # Surface lot: two cars nose-in in middle stalls of the two rows (stalls
    # between paint lines 4 m apart, rows at local z 7), away from the aisle.
    "surface_lot": (
        "lot",
        [
            ("landside/tp_parking_01a", (0.0, 0.0, 0.0), 0.0),
            ("vehicles/tp_suv_01b", (8.0, -7.0, 0.11), 0.0),
            ("vehicles/tp_taxi_01b", (12.0, 7.0, 0.11), 180.0),
        ],
        [],
    ),
    "multi_storey": ("multi", [("landside/tc_parking_2a", (0.0, 0.0, 0.0), 0.0)], []),
    # Open / close: the lot's entry and exit barrier arms, on posts at their hinges.
    "lot_gate": (
        "gate",
        [
            (
                "landside/tp_parking_01a",
                (0.0, 0.0, 0.0),
                0.0,
                ["TP_Parking_01A_Entry_Barrier", "TP_Parking_01A_Exit_Barrier"],
            ),
        ],
        ["gate_posts"],
    ),
}

# Furniture (Furniture 4/4 F4-2), one item per catalog id, drawn as the build view
# draws it (InteriorKit.OBJECT_PIECES, OBJECT_MOUNTED, OBJECT_POSTS). The prize
# podium carries its SUV on Mount_Car. The chain piece starts on one post and runs
# 2 m to the other (Godot +Z, Blender -Y), so it is drawn with its two posts, which
# stand on the two ends of the chain: the object node sits 1 m back of the centre.
FURNITURE = {
    "bench_1a": ("1x3", ["decor/tc_bench_1a"]),
    "bench_2a_indoor": ("4x4", ["decor/tc_bench_2a_indoor"]),
    "bush": ("2x2", ["decor/tc_bush_1a"]),
    "fountain_indoor": ("2x2_tall", ["decor/tc_fountain_1a_indoor"]),
    "metal_pole": ("1x1_tall", ["decor/tc_metal_pole_1a"]),
    "metal_pole_chain": (
        "1x3",
        [
            ("decor/tc_metal_pole_chain_1a", (0.0, 1.0, 0.0)),
            ("decor/tc_metal_pole_1a", (0.0, 1.0, 0.0)),
            ("decor/tc_metal_pole_1a", (0.0, -1.0, 0.0)),
        ],
    ),
    "plant_pot_1a": ("1x2_plant", ["decor/tc_plant_pot_1a"]),
    "plant_pot_2a": ("2x2", ["decor/tc_plant_pot_2a"]),
    "statue_indoor": ("1x1_xtall", ["decor/tc_statue_1b_indoor"]),
    "trash_can": ("1x1", ["decor/tc_trash_can_1a"]),
    "tree_indoor": ("2x2_tall", ["decor/tc_tree_3a_indoor"]),
    "bar_counter": ("2x2", ["bar_counter"]),
    "grab_and_go_stall": ("2x1_xtall", ["grab_and_go_stall"]),
    "restaurant_table": ("2x3", ["restaurant_table"]),
    "restaurant_booth": ("2x3", ["restaurant_booth"]),
    "info_desk": ("2x1_tall", ["info_desk"]),
    "info_screen": ("1x1_xtall", ["info_screen"]),
    "currency_exchange": ("2x1_xtall", ["currency_exchange"]),
    "atm": ("1x1_tall", ["atm"]),
    "pharmacy_counter": ("2x1_tall", ["pharmacy_counter"]),
    "pharmacy_shelf": ("2x1_tall", ["pharmacy_shelf"]),
    "shower_cubicle": ("1x1_xtall", ["shower_cubicle"]),
    "nap_pod": ("1x1_tall", ["nap_pod"]),
    "play_blocks": ("2x2", ["play_blocks"]),
    "play_slide": ("2x1", ["play_slide"]),
    "lounge_sofa": ("2x1", ["lounge_sofa"]),
    "lounge_armchair": ("1x1", ["lounge_armchair"]),
    "work_desk": ("2x2", ["work_desk"]),
    "prize_podium": ("6x3", ["prize_podium", ("vehicles/tp_suv_01a", "Mount_Car")]),
}
ITEMS.update({item: (cls, pieces, []) for item, (cls, pieces) in FURNITURE.items()})


def _store_room(cls, depth, counter, browse):
    """A store room (F4-5) on its minimum floor (three wide, depth deep), the
    counter or till across the back row's left two cells facing front, its order
    cell the cell in front of its left half.

    3x3 (the pharmacy), as the kiosk room: the shelf down the right column's
    front two cells facing Godot -X, its browse slot the centre column's front
    cell. 3x4 (duty free, fashion): the shelf or rail across the second row from
    the front, right two cells, facing front, its two browse slots the front
    row's right two cells; facing the camera its goods read, and it stands
    clear of the till's line of sight. Every use cell is distinct, on the floor
    and reachable from the front row."""
    back = (depth - 1) / 2.0
    tiles = [
        ("floor_tile", (float(x), back - y, 0.0)) for y in range(depth) for x in (-1, 0, 1)
    ]
    if depth == 3:
        shelf = (browse, (1.0, 0.5 - back, 0.0), -90.0)
    else:
        shelf = (browse, (0.5, 1.0 - back, 0.0))
    return (cls, tiles + [(counter, (-0.5, back, 0.0)), shelf], [])


# Store rooms (F4-5): the pharmacy at 3x3 min, duty free and fashion at 3x4 min
# (RoomTypes); the retail kit pieces (build_retail_kit.py) take the tall 2x1 box
# like the pharmacy counter and shelf.
ITEMS.update(
    {
        "pharmacy_room": _store_room("3x3", 3, "pharmacy_counter", "pharmacy_shelf"),
        "duty_free_till": ("2x1_tall", ["duty_free_till"], []),
        "duty_free_shelf": ("2x1_tall", ["duty_free_shelf"], []),
        "duty_free_room": _store_room("3x4", 4, "duty_free_till", "duty_free_shelf"),
        "fashion_till": ("2x1_tall", ["fashion_till"], []),
        "fashion_rail": ("2x1_tall", ["fashion_rail"], []),
        "fashion_room": _store_room("3x4", 4, "fashion_till", "fashion_rail"),
    }
)


def _money_room(cls, width, depth, piece):
    """A money room (F4-5b) on its minimum floor (width wide, depth deep), its one
    piece facing front against the back row's server cell when there is one:
    the exchange counter across the middle row of 2x3, the server's cell behind
    it and the visit slot in front; the ATM in the back cell of 1x2, the visit
    slot in front."""
    back = (depth - 1) / 2.0
    xs = [x - (width - 1) / 2.0 for x in range(width)]
    tiles = [("floor_tile", (x, back - y, 0.0)) for y in range(depth) for x in xs]
    row = back - 1.0 if depth == 3 else back
    return (cls, tiles + [(piece, (0.0, row, 0.0))], [])


# Money rooms (F4-5b): the exchange at 2x3 min, the ATM at 1x2 min (RoomTypes).
ITEMS.update(
    {
        "exchange_room": _money_room("2x3", 2, 3, "currency_exchange"),
        "atm_room": _money_room("1x2", 1, 2, "atm"),
    }
)
ORDER = list(ITEMS)


def log(msg):
    print("THUMB " + msg, flush=True)


def invalid(msg):
    print("PROBE_INVALID " + msg, flush=True)
    sys.exit(1)


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        h.update(f.read())
    return h.hexdigest()


def piece_name(entry):
    return entry if isinstance(entry, str) else entry[0]


def piece_path(name):
    """A kit piece by name, or a .glb under game/assets/ named with its folder."""
    return os.path.join(ASSETS_DIR if "/" in name else KIT_DIR, name + ".glb")


def source_hashes(item):
    names = sorted({piece_name(e) for e in ITEMS[item][1]})
    return {n + ".glb": sha256(piece_path(n)) for n in names}


# ---------------------------------------------------------------- materials

_images = {}


def image(png, non_color=False):
    if png not in _images:
        img = bpy.data.images.load(os.path.join(TEXTURES, png), check_existing=True)
        if non_color:
            img.colorspace_settings.name = "Non-Color"
        _images[png] = img
    return _images[png]


def toon_material(name, rgb=None):
    """Emission-only copy of toon.gdshader: albedo * (ramp(half_lambert) + ambient)."""
    m = bpy.data.materials.new("THUMB_" + name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    emit = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(emit.outputs["Emission"], out.inputs["Surface"])
    if rgb is not None:
        albedo = nt.nodes.new("ShaderNodeRGB")
        albedo.outputs[0].default_value = (*[srgb_to_linear(c) for c in rgb], 1.0)
        albedo_out = albedo.outputs[0]
    else:
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = image(ATLAS_PNG[name])
        tex.interpolation = "Closest"
        albedo_out = tex.outputs["Color"]
    ramp_png = RAMP_FOR.get(name, RAMP_PNG)
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    dot = nt.nodes.new("ShaderNodeVectorMath")
    dot.operation = "DOT_PRODUCT"
    dot.inputs[1].default_value = SUN
    nt.links.new(geo.outputs["Normal"], dot.inputs[0])
    hl = nt.nodes.new("ShaderNodeMath")
    hl.operation = "MULTIPLY_ADD"
    hl.use_clamp = True
    hl.inputs[1].default_value = 0.495
    hl.inputs[2].default_value = 0.5
    nt.links.new(dot.outputs["Value"], hl.inputs[0])
    uv = nt.nodes.new("ShaderNodeCombineXYZ")
    uv.inputs["Y"].default_value = 0.5
    nt.links.new(hl.outputs["Value"], uv.inputs["X"])
    ramp = nt.nodes.new("ShaderNodeTexImage")
    ramp.image = image(ramp_png, non_color=True)
    ramp.interpolation = "Closest"
    ramp.extension = "EXTEND"
    nt.links.new(uv.outputs["Vector"], ramp.inputs["Vector"])
    # Colour maths as vector maths: the Mix node shares socket names across types.
    amb = nt.nodes.new("ShaderNodeVectorMath")
    amb.operation = "MULTIPLY_ADD"
    nt.links.new(ramp.outputs["Color"], amb.inputs[0])
    amb.inputs[1].default_value = (LIGHT_GAIN, LIGHT_GAIN, LIGHT_GAIN)
    amb.inputs[2].default_value = (AMBIENT, AMBIENT, AMBIENT)
    mul = nt.nodes.new("ShaderNodeVectorMath")
    mul.operation = "MULTIPLY"
    nt.links.new(albedo_out, mul.inputs[0])
    nt.links.new(amb.outputs["Vector"], mul.inputs[1])
    nt.links.new(mul.outputs["Vector"], emit.inputs["Color"])
    return m


def unshaded_material(name):
    m = bpy.data.materials.new("THUMB_" + name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    emit = nt.nodes.new("ShaderNodeEmission")
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = image(ATLAS_PNG[name])
    tex.interpolation = "Closest"
    nt.links.new(tex.outputs["Color"], emit.inputs["Color"])
    nt.links.new(emit.outputs["Emission"], out.inputs["Surface"])
    return m


def glass_material(name):
    m = bpy.data.materials.new("THUMB_" + name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    emit = nt.nodes.new("ShaderNodeEmission")
    emit.inputs["Strength"].default_value = GLASS_TINT
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = image(ATLAS_PNG[name])
    nt.links.new(tex.outputs["Color"], emit.inputs["Color"])
    clear = nt.nodes.new("ShaderNodeBsdfTransparent")
    mix = nt.nodes.new("ShaderNodeMixShader")
    mix.inputs["Fac"].default_value = GLASS_ALPHA
    nt.links.new(clear.outputs["BSDF"], mix.inputs[1])
    nt.links.new(emit.outputs["Emission"], mix.inputs[2])
    nt.links.new(mix.outputs["Shader"], out.inputs["Surface"])
    return m


_materials = {}


def kit_material(name):
    if name not in _materials:
        if name in TOON_MATERIALS:
            _materials[name] = toon_material(name)
        elif name == "TP_Atlas_Lights_1A_D":
            _materials[name] = unshaded_material(name)
        elif name == "TP_Glass_1A_D":
            _materials[name] = glass_material(name)
        else:
            invalid("unmapped kit material '%s'" % name)
    return _materials[name]


# ---------------------------------------------------------------- scene


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _materials.clear()
    _images.clear()
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 32
    scene.cycles.use_denoising = False
    scene.cycles.max_bounces = 2
    scene.cycles.transparent_max_bounces = 8
    scene.render.film_transparent = True
    scene.render.resolution_x = SIZE * SUPERSAMPLE
    scene.render.resolution_y = SIZE * SUPERSAMPLE
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    world = bpy.data.worlds.new("THUMB_World")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.0
    scene.world = world
    if not hasattr(scene.render, "use_freestyle"):
        invalid("this Blender has no Freestyle; the outline cannot be drawn")
    scene.render.use_freestyle = True
    scene.render.line_thickness_mode = "ABSOLUTE"
    scene.render.line_thickness = OUTLINE_PX * SUPERSAMPLE
    fs = scene.view_layers[0].freestyle_settings
    lineset = fs.linesets[0] if len(fs.linesets) else fs.linesets.new("THUMB_Lines")
    lineset.select_by_visibility = True
    lineset.select_silhouette = True
    lineset.select_border = True
    lineset.select_crease = True
    if lineset.linestyle is None:
        lineset.linestyle = bpy.data.linestyles.new("THUMB_Outline")
    lineset.linestyle.color = OUTLINE_RGB
    lineset.linestyle.thickness = OUTLINE_PX * SUPERSAMPLE
    return scene


_mounts = {}


def import_piece(name, offset, yaw=0.0, keep=None):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=piece_path(name))
    new = [o for o in bpy.data.objects if o not in before]
    if keep is not None:
        # Only the named meshes stay; the rest of the asset is removed.
        drop = [o for o in new if o.type == "MESH" and o.name.split(".")[0] not in keep]
        for o in drop:
            new.remove(o)
            bpy.data.objects.remove(o, do_unlink=True)
        kept = sorted(o.name for o in new if o.type == "MESH")
        log("%s kept %s" % (name, kept))
        if len(kept) != len(keep):
            invalid("%s: kept %s, wanted %s" % (name, kept, keep))
    roots = [o for o in new if o.parent is None]
    # Turn about the piece origin (Blender Z is Godot Y), then move it into place.
    if isinstance(offset, str):
        if offset not in _mounts:
            invalid("%s: no earlier piece has a %s" % (name, offset))
        place = _mounts[offset].normalized() @ Matrix.Rotation(math.radians(yaw), 4, "Z")
    else:
        place = Matrix.Translation(Vector(offset)) @ Matrix.Rotation(math.radians(yaw), 4, "Z")
    for r in roots:
        r.matrix_world = place @ r.matrix_world
    bpy.context.view_layer.update()
    for o in new:
        if o.type == "EMPTY" and o.name.startswith("Mount_"):
            _mounts[o.name.split(".")[0]] = o.matrix_world.copy()
    meshes = [o for o in new if o.type == "MESH"]
    if not meshes:
        invalid("%s.glb imported no meshes" % name)
    names = set()
    for o in meshes:
        for slot in o.material_slots:
            if slot.material is None:
                invalid("%s: %s has an empty material slot" % (name, o.name))
            names.add(slot.material.name.split(".")[0])
            slot.material = kit_material(slot.material.name.split(".")[0])
    return meshes, names


def glyph_mesh(name, polys, rgb, z0, z1):
    """Prism meshes from 2D outlines (Blender XY), between heights z0 and z1."""
    verts, faces = [], []
    for poly in polys:
        n = len(poly)
        base = len(verts)
        verts += [(x, y, z0) for x, y in poly] + [(x, y, z1) for x, y in poly]
        faces.append(tuple(base + i for i in reversed(range(n))))
        faces.append(tuple(base + n + i for i in range(n)))
        for i in range(n):
            j = (i + 1) % n
            faces.append((base + i, base + j, base + n + j, base + n + i))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.data.materials.append(toon_material(name, rgb))
    return obj


def arrow(direction):
    """Flat arrow on the tile, pointing Blender -Y (into the hall) or +Y (out)."""
    s = 1.0 if direction == "out" else -1.0
    shaft = [(-0.16, -0.46 * s), (0.16, -0.46 * s), (0.16, 0.02 * s), (-0.16, 0.02 * s)]
    head = [(-0.44, 0.0), (0.44, 0.0), (0.0, 0.46 * s)]
    if s < 0:
        shaft = [p for p in reversed(shaft)]
        head = [p for p in reversed(head)]
    return [shaft, head]


def cross():
    """An X that reads as an X on screen, not a plus: each bar sits at the plan angle
    that the camera's tilt foreshortens to 45 degrees off the screen's horizontal."""
    w, r = 0.09, 0.4
    view = math.degrees(math.atan(1.0 / math.sin(CAM_ELEVATION)))
    right = math.degrees(CAM_AZIMUTH)  # the camera's right axis in plan
    bars = []
    for ang in (right + view, right - view):
        a = math.radians(ang)
        c, s = math.cos(a), math.sin(a)
        rect = [(-r, -w), (r, -w), (r, w), (-r, w)]
        bars.append([(x * c - y * s, x * s + y * c) for x, y in rect])
    return bars


def add_glyphs(extras):
    objs = []
    for g in extras:
        if g == "arrow_in":
            objs.append(glyph_mesh("Glyph_Arrow_In", arrow("in"), ENTRANCE_RGB, 0.0, 0.07))
        elif g == "arrow_out":
            objs.append(glyph_mesh("Glyph_Arrow_Out", arrow("out"), EXIT_RGB, 0.0, 0.07))
        elif g == "cross":
            objs.append(glyph_mesh("Glyph_Cross", cross(), REMOVE_RGB, 0.0, 0.08))
        elif g == "road_strip":
            # Road from the kerb line (Blender y 0) out to -4.2, sidewalk behind it.
            road = [(-8.5, -4.2), (8.5, -4.2), (8.5, 0.0), (-8.5, 0.0)]
            walk = [(-8.5, 0.0), (8.5, 0.0), (8.5, 0.4), (-8.5, 0.4)]
            objs.append(glyph_mesh("Glyph_Road", [road], ROAD_RGB, -0.1, 0.0))
            objs.append(glyph_mesh("Glyph_Sidewalk", [walk], SIDEWALK_RGB, -0.1, 0.0))
        elif g == "gate_posts":
            # Posts at the barrier hinges, Godot (-7, z, +-7) is Blender (-7, -+7).
            posts = []
            for y in (-7.0, 7.0):
                posts.append(
                    [(-7.15, y - 0.15), (-6.85, y - 0.15), (-6.85, y + 0.15), (-7.15, y + 0.15)]
                )
            objs.append(glyph_mesh("Glyph_Posts", posts, POST_RGB, 0.0, 1.75))
    return objs


def class_scale(cls, cam_rot):
    """Ortho scale fitting the class's nominal box in the frame with the margin."""
    (w, d, h), (cx, cy, cz) = CLASSES[cls]
    inv = cam_rot.to_matrix().inverted()
    xs, ys = [], []
    for sx in (-0.5, 0.5):
        for sy in (-0.5, 0.5):
            for sz in (-0.5, 0.5):
                p = inv @ Vector((cx + sx * w, cy + sy * d, cz + sz * h))
                xs.append(p.x)
                ys.append(p.y)
    extent = max(max(xs) - min(xs), max(ys) - min(ys))
    return extent / (1.0 - 2.0 * MARGIN - 0.04)


def setup_camera(scene, cls, objs):
    cam_data = bpy.data.cameras.new("THUMB_Cam")
    cam_data.type = "ORTHO"
    cam = bpy.data.objects.new("THUMB_Cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    direction = Vector(
        (
            math.sin(CAM_AZIMUTH) * math.cos(CAM_ELEVATION),
            -math.cos(CAM_AZIMUTH) * math.cos(CAM_ELEVATION),
            math.sin(CAM_ELEVATION),
        )
    )
    rot = (-direction).to_track_quat("-Z", "Y")
    cam.rotation_mode = "QUATERNION"
    cam.rotation_quaternion = rot
    # Centre on the subject's own bounds in camera space. The scale is the class's;
    # a subject bigger than its class box widens it and says so.
    bpy.context.view_layer.update()
    inv = rot.to_matrix().inverted()
    pts = [inv @ (o.matrix_world @ v.co) for o in objs for v in o.data.vertices]
    span = max(
        max(p.x for p in pts) - min(p.x for p in pts),
        max(p.y for p in pts) - min(p.y for p in pts),
    )
    nominal = class_scale(cls, rot)
    actual = span / (1.0 - 2.0 * MARGIN - 0.04)
    if actual > nominal:
        log("CLASS_OVERFLOW %s outgrows its class box: %.2f > %.2f" % (cls, actual, nominal))
    cam_data.ortho_scale = max(nominal, actual)
    mid = Vector(
        (
            (min(p.x for p in pts) + max(p.x for p in pts)) / 2,
            (min(p.y for p in pts) + max(p.y for p in pts)) / 2,
            max(p.z for p in pts) + 20.0,
        )
    )
    cam.location = rot.to_matrix() @ mid
    cam_data.clip_start = 0.1
    cam_data.clip_end = 100.0
    bpy.context.view_layer.update()
    return cam


def prove_in_frame(item, scene, cam, objs):
    xs, ys = [], []
    for o in objs:
        for v in o.data.vertices:
            p = world_to_camera_view(scene, cam, o.matrix_world @ v.co)
            xs.append(p.x)
            ys.append(p.y)
            if p.z <= cam.data.clip_start:
                invalid("%s: vertex behind the camera" % item)
    box = (min(xs), min(ys), max(xs), max(ys))
    share = max(box[2] - box[0], box[3] - box[1])
    log(
        "%s in_frame u=[%.3f,%.3f] v=[%.3f,%.3f] share=%.2f margin=%.2f ortho=%.2f"
        % (item, box[0], box[2], box[1], box[3], share, MARGIN, cam.data.ortho_scale)
    )
    if box[0] < MARGIN or box[1] < MARGIN or box[2] > 1 - MARGIN or box[3] > 1 - MARGIN:
        invalid("%s: subject leaves the frame margin" % item)
    if share < MIN_SHARE:
        invalid("%s: subject spans only %.2f of the frame" % (item, share))
    # Occlusion: the scene holds only the subject, so nothing can stand in front.
    others = [o for o in scene.objects if o.type == "MESH" and o not in objs]
    if others:
        invalid("%s: stray meshes in the scene: %s" % (item, [o.name for o in others]))


def render_item(item, path):
    scene = reset_scene()
    cls, pieces, extras = ITEMS[item]
    if cls in NO_CREASE_CLASSES:
        for lineset in scene.view_layers[0].freestyle_settings.linesets:
            lineset.select_crease = False
            lineset.select_border = False
    objs, mats = [], set()
    _mounts.clear()
    for entry in pieces:
        name = piece_name(entry)
        offset = (0.0, 0.0, 0.0) if isinstance(entry, str) else entry[1]
        yaw = entry[2] if not isinstance(entry, str) and len(entry) > 2 else 0.0
        keep = entry[3] if not isinstance(entry, str) and len(entry) > 3 else None
        meshes, names = import_piece(name, offset, yaw, keep)
        objs += meshes
        mats |= names
    objs += add_glyphs(extras)
    images = sorted(i.name for i in bpy.data.images if i.users)
    log(
        "%s class=%s pieces=%s meshes=%d kit_materials=%s images=%s"
        % (item, cls, [piece_name(e) for e in pieces], len(objs), sorted(mats), images)
    )
    if not any(n in ATLAS_PNG for n in mats):
        invalid("%s: no atlas material bound" % item)
    cam = setup_camera(scene, cls, objs)
    prove_in_frame(item, scene, cam, objs)
    tmp = path + ".full.png"
    scene.render.filepath = tmp
    bpy.ops.render.render(write_still=True)
    img = bpy.data.images.load(tmp)
    img.scale(SIZE, SIZE)
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)
    os.remove(tmp)
    check = bpy.data.images.load(path)
    w, h = check.size
    px = check.pixels[:]
    opaque = sum(1 for i in range(3, len(px), 4) if px[i] > 0.5)
    corner = px[3]
    bpy.data.images.remove(check)
    log("%s wrote %s size=%dx%d opaque_px=%d corner_alpha=%.2f" % (item, path, w, h, opaque, corner))
    if (w, h) != (SIZE, SIZE) or opaque == 0 or corner > 0.01:
        invalid("%s: written PNG is wrong (size, empty, or opaque background)" % item)


# ---------------------------------------------------------------- contact sheet


def contact_sheet(items):
    """Row 1-2: the thumbnails at 256 on a dark card. Row 3: each at 64 px on dark,
    then on light, to judge legibility at card size."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    cols, gap, small = 5, 8, 64
    rows = math.ceil(len(items) / cols)
    # Wide enough for the 256 px grid and for the row of 64 px copies.
    W = max(cols * SIZE + (cols + 1) * gap, len(items) * (small + gap) + gap)
    small_h = 2 * small + 3 * gap
    H = rows * (SIZE + gap) + gap + small_h
    dark, light = (0.16, 0.18, 0.22), (0.86, 0.87, 0.84)
    sheet = [0.0] * (W * H * 4)
    for y in range(H):
        for x in range(W):
            i = (y * W + x) * 4
            sheet[i : i + 4] = [0.08, 0.08, 0.09, 1.0]

    def blit(pixels, w, h, x0, y0, bg):
        # y0 is from the top; Blender pixel rows run bottom-up.
        for yy in range(h):
            dst_row = H - 1 - (y0 + yy)
            src_row = h - 1 - yy
            for xx in range(w):
                s = (src_row * w + xx) * 4
                a = pixels[s + 3]
                d = (dst_row * W + x0 + xx) * 4
                for c in range(3):
                    sheet[d + c] = pixels[s + c] * a + bg[c] * (1 - a)
                sheet[d + 3] = 1.0

    for n, item in enumerate(items):
        img = bpy.data.images.load(os.path.join(OUT_DIR, item + ".png"))
        img.colorspace_settings.name = "sRGB"
        px = img.pixels[:]
        r, c = divmod(n, cols)
        blit(px, SIZE, SIZE, gap + c * (SIZE + gap), gap + r * (SIZE + gap), dark)
        img.scale(small, small)
        spx = img.pixels[:]
        y_small = rows * (SIZE + gap) + gap
        blit(spx, small, small, gap + n * (small + gap), y_small, dark)
        blit(spx, small, small, gap + n * (small + gap), y_small + small + gap, light)
        bpy.data.images.remove(img)
    out = bpy.data.images.new("contact_sheet", W, H, alpha=True)
    out.pixels[:] = sheet
    out.filepath_raw = SHEET
    out.file_format = "PNG"
    out.save()
    log("contact sheet %s size=%dx%d order=%s" % (SHEET, W, H, items))


# ---------------------------------------------------------------- main


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    force = "--force" in argv
    wanted = [a for a in argv if not a.startswith("--")] or ORDER
    unknown = [a for a in wanted if a not in ITEMS]
    if unknown:
        invalid("unknown items %s; known: %s" % (unknown, ORDER))
    ramp = bpy.data.images.load(os.path.join(TEXTURES, RAMP_PNG))
    rpx = ramp.pixels[:]
    steps = sorted({round(rpx[i], 3) for i in range(0, len(rpx), 4)})
    log("ramp %s %dx%d red steps=%s" % (RAMP_PNG, ramp.size[0], ramp.size[1], steps))
    os.makedirs(OUT_DIR, exist_ok=True)
    os.makedirs(SHEET_DIR, exist_ok=True)
    manifest = {}
    if os.path.exists(MANIFEST):
        with open(MANIFEST, encoding="utf-8") as f:
            manifest = json.load(f)
    entries = manifest.get("items", {})
    rendered, skipped = [], []
    for item in wanted:
        hashes = source_hashes(item)
        path = os.path.join(OUT_DIR, item + ".png")
        prev = entries.get(item, {})
        fresh = (
            prev.get("sources") == hashes
            and prev.get("style") == STYLE
            and os.path.exists(path)
        )
        if fresh and not force:
            skipped.append(item)
            continue
        render_item(item, path)
        entries[item] = {
            "png": item + ".png",
            "class": ITEMS[item][0],
            "style": STYLE,
            "sources": hashes,
        }
        rendered.append(item)
    manifest = {
        "generator": "tools/blender/thumbnails/render_kit_thumbnails.py",
        "style": STYLE,
        "size": SIZE,
        "items": {k: entries[k] for k in ORDER if k in entries},
    }
    with open(MANIFEST, "w", encoding="utf-8", newline="\n") as f:
        json.dump(manifest, f, indent=2, sort_keys=False)
        f.write("\n")
    log("rendered=%s skipped=%s" % (rendered, skipped))
    have = [k for k in ORDER if os.path.exists(os.path.join(OUT_DIR, k + ".png"))]
    contact_sheet(have)
    log("THUMBS_OK %d thumbnails" % len(have))


main()
