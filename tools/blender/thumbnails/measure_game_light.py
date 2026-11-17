"""Measure the game's lighting so the thumbnails can copy it (board item L1).

Run (headless):
  blender.exe --background --factory-startup --python-exit-code 1 --python \
    tools/blender/thumbnails/measure_game_light.py -- <look-pass tile png>

1. Integrates the sky irradiance of main.tscn's default ProceduralSkyMaterial
   (its sun glow included) for the six axis normals, the numbers
   render_kit_thumbnails.py uses as its ambient cube (SKY_AMBIENT).
2. Checks the model on a game plate: a look-pass piece tile (main.tscn's sky,
   sun and Filmic tonemap) holds the green ground and the orange 1 m reference
   cube, both StandardMaterial3D Lambert surfaces with known albedo. The model
   is albedo * (sun * n.L + E(n)), then Godot's Filmic curve (white 1.0), then
   sRGB. It prints the predicted and the measured colour of each face.
3. With -- --fit <tile png>, grid-fits the ambient scale and the Filmic white on
   those faces (render_kit_thumbnails.py's AMBIENT_SCALE and FILMIC_WHITE).
"""

import math
import sys

import bpy
import numpy as np

# ProceduralSkyMaterial defaults (Godot 4), sRGB source colours.
SKY_TOP = (0.385, 0.454, 0.55)
SKY_HORIZON = (0.6463, 0.6558, 0.6708)
GROUND_BOTTOM = (0.2, 0.169, 0.133)
GROUND_HORIZON = (0.6463, 0.6558, 0.6708)
SKY_CURVE = 0.15
GROUND_CURVE = 0.02
SUN_ANGLE_MAX = math.radians(30.0)
SUN_CURVE = 0.15
# main.tscn Sun: toward the light, Godot axes (y up). Energy 1, white.
SUN_G = np.array([0.353553, 0.707107, 0.612372])


def lin(c):
    c = np.asarray(c, dtype=float)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def srgb(c):
    c = np.clip(np.asarray(c, dtype=float), 0.0, 1.0)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055)


def filmic(x, white=1.0):
    a, b, c, d, e, f = 0.22 * 4.0, 0.30 * 2.0, 0.10, 0.20, 0.01, 0.30

    def curve(v):
        return (v * (a * v + c * b) + d * e) / (v * (a * v + b) + d * f) - e / f

    return curve(np.asarray(x, dtype=float)) / curve(white)


def sky(dirs):
    """Godot's procedural sky radiance (linear) for unit directions (N, 3), y up."""
    y = np.clip(dirs[:, 1], -1.0, 1.0)
    v_angle = np.arccos(y)
    c = 1.0 - v_angle / (math.pi * 0.5)
    t = np.clip(1.0 - np.power(np.clip(1.0 - c, 0, None), 1.0 / SKY_CURVE), 0.0, 1.0)
    up = lin(SKY_HORIZON)[None] * (1 - t[:, None]) + lin(SKY_TOP)[None] * t[:, None]
    c2 = (v_angle - math.pi * 0.5) / (math.pi * 0.5)
    t2 = np.clip(1.0 - np.power(np.clip(1.0 - c2, 0, None), 1.0 / GROUND_CURVE), 0.0, 1.0)
    down = lin(GROUND_HORIZON)[None] * (1 - t2[:, None]) + lin(GROUND_BOTTOM)[None] * t2[:, None]
    out = np.where((y >= 0)[:, None], up, down)
    sun_angle = np.arccos(np.clip(dirs @ SUN_G, -1, 1))
    k = np.clip(sun_angle / SUN_ANGLE_MAX, 0, 1)
    tk = np.clip(1.0 - np.power(1.0 - k, 1.0 / SUN_CURVE), 0.0, 1.0)
    glow = np.ones(3)[None] * (1 - tk[:, None]) + out * tk[:, None]
    return np.where((sun_angle < SUN_ANGLE_MAX)[:, None], glow, out)


def irradiance(normal, n=400000, seed=7):
    rng = np.random.default_rng(seed)
    d = rng.normal(size=(n, 3))
    d /= np.linalg.norm(d, axis=1)[:, None]
    cos = d @ normal
    keep = cos > 0
    # Irradiance over pi, so a uniform sky of 1 gives 1: (4 pi / N) sum(L cos) / pi.
    return (sky(d[keep]) * cos[keep][:, None]).sum(axis=0) * 4.0 / n


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    axes = {
        "+X": (1, 0, 0), "-X": (-1, 0, 0), "+Y(up)": (0, 1, 0),
        "-Y(down)": (0, -1, 0), "+Z": (0, 0, 1), "-Z": (0, 0, -1),
    }
    E = {}
    for k, v in axes.items():
        E[k] = irradiance(np.array(v, dtype=float))
        print("IRRADIANCE godot %s = (%.4f, %.4f, %.4f)" % (k, *E[k]))
    if not argv or argv[0].startswith("--"):
        return
    img = bpy.data.images.load(argv[0])
    w, h = img.size
    px = np.array(img.pixels[:]).reshape(h, w, 4)

    def sample(x, y, r=6):
        # x, y from the top-left; Blender rows run bottom-up.
        row = h - 1 - y
        return px[row - r : row + r, x - r : x + r, :3].reshape(-1, 3).mean(axis=0)

    faces = [
        ("ground", (0.36, 0.5, 0.3), (0, 1, 0), (150, 950)),
        ("cube top", (1.0, 0.45, 0.1), (0, 1, 0), (800, 400)),
        ("cube +Z (left)", (1.0, 0.45, 0.1), (0, 0, 1), (740, 530)),
        ("cube +X (right)", (1.0, 0.45, 0.1), (1, 0, 0), (860, 540)),
    ]
    for name, albedo, n, xy in faces:
        nv = np.array(n, dtype=float)
        e = irradiance(nv)
        direct = max(0.0, float(nv @ SUN_G))
        pred = srgb(filmic(lin(albedo) * (direct + e)))
        pred_none = srgb(lin(albedo) * (direct + e))
        got = sample(*xy)
        print(
            "CHECK %-16s n.L=%.3f E=(%.3f %.3f %.3f) predicted_filmic=(%.3f %.3f %.3f)"
            " predicted_no_tonemap=(%.3f %.3f %.3f) measured=(%.3f %.3f %.3f)"
            % (name, direct, *e, *pred, *pred_none, *got)
        )


main()


def fit(path):
    """Grid-fit an ambient scale k and a Filmic white on the plate's four faces."""
    img = bpy.data.images.load(path)
    w, h = img.size
    px = np.array(img.pixels[:]).reshape(h, w, 4)
    faces = [
        ((0.36, 0.5, 0.3), (0, 1, 0), (150, 950)),
        ((1.0, 0.45, 0.1), (0, 1, 0), (800, 400)),
        ((1.0, 0.45, 0.1), (0, 0, 1), (740, 530)),
        ((1.0, 0.45, 0.1), (1, 0, 0), (860, 540)),
    ]
    rows = []
    for albedo, n, (x, y) in faces:
        nv = np.array(n, dtype=float)
        row = h - 1 - y
        got = px[row - 6 : row + 6, x - 6 : x + 6, :3].reshape(-1, 3).mean(axis=0)
        rows.append((lin(albedo), max(0.0, float(nv @ SUN_G)), irradiance(nv), got))
    best = None
    for k in np.arange(0.5, 4.01, 0.05):
        for white in (0.8, 0.9, 1.0, 1.1, 1.2, 1.5, 2.0, 4.0, 8.0):
            err = 0.0
            for alb, direct, e, got in rows:
                err += float(((srgb(filmic(alb * (direct + k * e), white)) - got) ** 2).sum())
            if best is None or err < best[0]:
                best = (err, k, white)
    print("FIT ambient_scale=%.2f white=%.1f rms=%.4f" % (best[1], best[2], math.sqrt(best[0] / 12)))
    for alb, direct, e, got in rows:
        p = srgb(filmic(alb * (direct + best[1] * e), best[2]))
        print("FIT face predicted=(%.3f %.3f %.3f) measured=(%.3f %.3f %.3f)" % (*p, *got))


if "--fit" in sys.argv:
    fit(sys.argv[sys.argv.index("--fit") + 1])
