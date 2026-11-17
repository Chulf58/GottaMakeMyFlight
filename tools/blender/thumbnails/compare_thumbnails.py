"""Side-by-side plate: each piece in game beside its build-menu thumbnail (board L1).

Run (headless):
  blender.exe --background --factory-startup --python-exit-code 1 --python \
    tools/blender/thumbnails/compare_thumbnails.py -- <out.png> <old_thumb_dir|-> \
    <item>=<game tile png> ...

One row per item: the centre of its game tile (a look-pass or studio plate of the
piece in main.tscn's light; the tile's own probe proved the subject in frame),
then the new thumbnail and, when an old thumbnail folder is given, the old one,
both on the HUD card cream (hud-look-warm-cozy-cream-cards-with-a-dark-outline-
toon-pale). Each thumbnail must have opaque pixels, or PROBE_INVALID.
"""

import os
import sys

import bpy
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
THUMBS = os.path.join(REPO, "game", "assets", "ui", "thumbnails")
CELL = 256
GAP = 8
CREAM = np.array([0.96, 0.93, 0.86])
BACK = np.array([0.33, 0.37, 0.43])
CROP = 0.62  # share of the game tile's height kept around its centre


def invalid(msg):
    print("PROBE_INVALID " + msg, flush=True)
    sys.exit(1)


def load(path):
    """RGBA float pixels, top row first."""
    img = bpy.data.images.load(path)
    w, h = img.size
    px = np.array(img.pixels[:]).reshape(h, w, 4)[::-1]
    bpy.data.images.remove(img)
    return px


def resize(px, size):
    h, w = px.shape[:2]
    ys = (np.arange(size) + 0.5) * h / size
    xs = (np.arange(size) + 0.5) * w / size
    out = np.zeros((size, size, px.shape[2]))
    # Box filter: average the source pixels each output pixel covers.
    y0 = np.floor(ys - h / size / 2).astype(int).clip(0, h - 1)
    y1 = np.ceil(ys + h / size / 2).astype(int).clip(1, h)
    x0 = np.floor(xs - w / size / 2).astype(int).clip(0, w - 1)
    x1 = np.ceil(xs + w / size / 2).astype(int).clip(1, w)
    for j in range(size):
        rows = px[y0[j] : y1[j]]
        for i in range(size):
            out[j, i] = rows[:, x0[i] : x1[i]].reshape(-1, px.shape[2]).mean(axis=0)
    return out


def on_cream(px):
    a = px[..., 3:4]
    return px[..., :3] * a + CREAM * (1 - a)


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :]
    out_path, old_dir, pairs = argv[0], argv[1], argv[2:]
    cols = 3 if old_dir != "-" else 2
    W = cols * CELL + (cols + 1) * GAP
    H = len(pairs) * (CELL + GAP) + GAP
    sheet = np.ones((H, W, 3)) * BACK
    for r, pair in enumerate(pairs):
        item, tile = pair.split("=", 1)
        y = GAP + r * (CELL + GAP)
        game = load(tile)
        gh, gw = game.shape[:2]
        side = int(gh * CROP)
        cy, cx = gh // 2, gw // 2
        crop = game[cy - side // 2 : cy + side // 2, cx - side // 2 : cx + side // 2, :3]
        sheet[y : y + CELL, GAP : GAP + CELL] = resize(crop, CELL)
        thumbs = [os.path.join(THUMBS, item + ".png")]
        if old_dir != "-":
            thumbs.append(os.path.join(old_dir, item + ".png"))
        for c, path in enumerate(thumbs, start=1):
            px = load(path)
            opaque = int((px[..., 3] > 0.5).sum())
            if opaque == 0:
                invalid("%s: %s has no opaque pixels" % (item, path))
            x = GAP + c * (CELL + GAP)
            sheet[y : y + CELL, x : x + CELL] = on_cream(resize(px, CELL))
            print("ROW %s col=%d %s opaque_px=%d" % (item, c, path, opaque))
    img = bpy.data.images.new("compare", W, H, alpha=False)
    rgba = np.concatenate([sheet, np.ones((H, W, 1))], axis=2)[::-1]
    img.pixels[:] = rgba.ravel().tolist()
    img.filepath_raw = out_path
    img.file_format = "PNG"
    img.save()
    print("PLATE %s size=%dx%d rows=%d cols=game,new%s" % (out_path, W, H, len(pairs), ",old" if cols == 3 else ""))


main()
