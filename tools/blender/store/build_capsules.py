"""Build all 8 Steam store and library assets + contact sheet (board D6 slice D6b).

Run (headless, reproducible, after game/spike/store_key_art_probe.gd):
  blender.exe --background --factory-startup --python-exit-code 1 --python \
    'C:\\Users\\chulf\\Gotta-make-my-flight\\.claude\\worktrees\\d6b-capsules\\tools\\blender\\store\\build_capsules.py'

Inputs (under tools/blender/out/store/raw/):
  raw_hero_3840x1240.png
  raw_landscape_2464x1412.png
  raw_portrait_1496x1792.png

Outputs (under tools/blender/out/store/, gitignored):
  header_capsule.png     920 x 430   staged key art + Option A logo only
  small_capsule.png      462 x 174   staged key art + Option A logo nearly filling frame
  main_capsule.png      1232 x 706   staged key art + Option A logo only
  vertical_capsule.png   748 x 896   portrait staged key art + Option A logo only
  library_capsule.png    600 x 900   portrait staged key art + Option A logo only
  library_header.png     920 x 430   staged key art + Option A logo only
  library_hero.png      3840 x 1240  wide staged key art, ZERO text and ZERO logo
  library_logo.png      1280 x <=720 transparent RGBA Option A logotype, >=4px clear border
  contact_sheet.png      labelled overview of all 8 assets
"""

import math
import os
import sys

import numpy as np
import OpenImageIO as oiio
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
LOGO_DIR = os.path.join(REPO, "tools", "blender", "logo")
if LOGO_DIR not in sys.path:
    sys.path.insert(0, LOGO_DIR)

import build_logos as bl  # noqa: E402

OUT = os.path.join(REPO, "tools", "blender", "out", "store")
RAW = os.path.join(OUT, "raw")

SUN_MIST_SRGB = (0.95, 0.96, 0.99)

# 5x7 bitmap glyphs for crisp labels on contact_sheet.png ONLY (never on store assets).
_FONT_5X7 = {
    "A": ("01110", "10001", "10001", "11111", "10001", "10001", "10001"),
    "B": ("11110", "10001", "10001", "11110", "10001", "10001", "11110"),
    "C": ("01111", "10000", "10000", "10000", "10000", "10000", "01111"),
    "D": ("11110", "10001", "10001", "10001", "10001", "10001", "11110"),
    "E": ("11111", "10000", "10000", "11110", "10000", "10000", "11111"),
    "G": ("01111", "10000", "10000", "10011", "10001", "10001", "01111"),
    "H": ("10001", "10001", "10001", "11111", "10001", "10001", "10001"),
    "I": ("11111", "00100", "00100", "00100", "00100", "00100", "11111"),
    "L": ("10000", "10000", "10000", "10000", "10000", "10000", "11111"),
    "M": ("10001", "11011", "10101", "10001", "10001", "10001", "10001"),
    "N": ("10001", "11001", "10101", "10011", "10001", "10001", "10001"),
    "O": ("01110", "10001", "10001", "10001", "10001", "10001", "01110"),
    "P": ("11110", "10001", "10001", "11110", "10000", "10000", "10000"),
    "R": ("11110", "10001", "10001", "11110", "10100", "10010", "10001"),
    "S": ("01111", "10000", "10000", "01110", "00001", "00001", "11110"),
    "T": ("11111", "00100", "00100", "00100", "00100", "00100", "00100"),
    "U": ("10001", "10001", "10001", "10001", "10001", "10001", "01110"),
    "V": ("10001", "10001", "10001", "10001", "10001", "01010", "00100"),
    "X": ("10001", "01010", "00100", "00100", "00100", "01010", "10001"),
    "Y": ("10001", "01010", "00100", "00100", "00100", "00100", "00100"),
    "Z": ("11111", "00010", "00100", "00100", "01000", "10000", "11111"),
    "0": ("01110", "10011", "10101", "10101", "11001", "10001", "01110"),
    "1": ("00100", "01100", "00100", "00100", "00100", "00100", "01110"),
    "2": ("01110", "10001", "00001", "00110", "01000", "10000", "11111"),
    "3": ("11110", "00001", "00001", "01110", "00001", "00001", "11110"),
    "4": ("00010", "00110", "01010", "10010", "11111", "00010", "00010"),
    "5": ("11111", "10000", "11110", "00001", "00001", "10001", "01110"),
    "6": ("01110", "10000", "10000", "11110", "10001", "10001", "01110"),
    "7": ("11111", "00001", "00010", "00100", "01000", "01000", "01000"),
    "8": ("01110", "10001", "10001", "01110", "10001", "10001", "01110"),
    "9": ("01110", "10001", "10001", "01111", "00001", "00001", "01110"),
    "_": ("00000", "00000", "00000", "00000", "00000", "00000", "11111"),
    "-": ("00000", "00000", "00000", "11111", "00000", "00000", "00000"),
    ":": ("00000", "00100", "00100", "00000", "00100", "00100", "00000"),
    ".": ("00000", "00000", "00000", "00000", "00000", "00100", "00100"),
    "(": ("00010", "00100", "01000", "01000", "01000", "00100", "00010"),
    ")": ("01000", "00100", "00010", "00010", "00010", "00100", "01000"),
    " ": ("00000", "00000", "00000", "00000", "00000", "00000", "00000"),
}


def srgb_to_lin_arr(srgb):
    a = np.clip(srgb, 0.0, 1.0)
    return np.where(a <= 0.04045, a / 12.92, np.power((a + 0.055) / 1.055, 2.4)).astype(np.float32)


def load_raw_lin(filename, expected_w, expected_h):
    path = os.path.join(RAW, filename)
    if not os.path.isfile(path):
        bl.fail("missing raw render: %s" % path)
    arr8 = bl.read_png(path)
    h, w = arr8.shape[:2]
    print("PROBE raw_input %s size=%dx%dx%d std=%.2f" % (filename, w, h, arr8.shape[2], float(arr8[:, :, :3].std())))
    if w != expected_w or h != expected_h:
        bl.fail("raw %s expected %dx%d, got %dx%d" % (filename, expected_w, expected_h, w, h))
    if float(arr8[:, :, :3].std()) < 8.0:
        bl.fail("raw %s has near-uniform colour variance" % filename)
    rgb_lin = srgb_to_lin_arr(arr8[:, :, :3].astype(np.float32) / 255.0)
    alpha = np.ones((h, w, 1), np.float32)
    return np.concatenate([rgb_lin, alpha], axis=2)


def crop_and_resize(img_lin, target_w, target_h, align_y=0.5, align_x=0.5):
    sh, sw = img_lin.shape[:2]
    target_aspect = target_w / float(target_h)
    src_aspect = sw / float(sh)
    if src_aspect > target_aspect:
        cw = int(round(sh * target_aspect))
        ch = sh
        x0 = int(round((sw - cw) * align_x))
        y0 = 0
    else:
        cw = sw
        ch = int(round(sw / target_aspect))
        x0 = 0
        y0 = int(round((sh - ch) * align_y))
    x0 = max(0, min(sw - cw, x0))
    y0 = max(0, min(sh - ch, y0))
    cropped = np.ascontiguousarray(img_lin[y0:y0 + ch, x0:x0 + cw])
    if cw == target_w and ch == target_h:
        return cropped.copy()
    return bl.resize(cropped, target_w, target_h)


def build_a_small(scene, font):
    """Option A with scaled-down plane for 462x174 small_capsule (decision 56cccfaf)."""
    l1 = bl.text_obj(scene, font, "Gotta Make", 1.0, 0.052, bl.flat_mat("cream", bl.CREAM), spacing=1.10)
    l2 = bl.text_obj(scene, font, "My Flight", 1.32, 0.068, bl.flat_mat("yellow", bl.YELLOW), spacing=1.10)
    bl.place(l2, 0.0, 0.0)
    _, _, _, l2_top = bl.local_bounds(l2)
    x0, x1, y0, y1 = bl.local_bounds(l1)
    bl.place(l1, -0.06, l2_top + 0.02 + (y1 - y0) / 2)
    x0, x1, y0, y1 = bl.local_bounds(l1)
    p0 = Vector((x0 + 0.06, y1 + 0.10))
    p1 = Vector((0.0, y1 + 0.34))
    p2 = Vector((x1 - 0.02, y1 + 0.25))
    heading = (p2 - p1).normalized()
    half = 0.35
    centre = p2 + heading * (half + 0.10)
    plane = bl.poly_obj(
        scene,
        "plane",
        bl.plane_pts(centre.x, centre.y, half, math.degrees(math.atan2(heading.y, heading.x)) + 8),
        bl.flat_mat("plane", bl.CREAM),
    )
    under = []
    dot_mat = bl.flat_mat("trail", bl.NAVY)
    n = 14
    for i in range(n):
        t = i / (n - 1) * 0.93
        p = (1 - t) ** 2 * p0 + 2 * (1 - t) * t * p1 + t * t * p2
        under.append(bl.poly_obj(scene, "dot%d" % i, bl.circle(p.x, p.y, 0.058), dot_mat, z=-0.5))
    style = {"outline": 0.080, "shadow": (0.02, -0.085)}
    return [l1, l2, plane], under, style


def render_logo_master(tag, builder):
    scene, font = bl.new_scene()
    main_objs, under_objs, style = builder(scene, font)
    ppu = bl.frame_camera(scene, main_objs + under_objs, style)
    for o in under_objs:
        o.hide_render = True
    main = bl.render_exr(scene, os.path.join(RAW, "%s_main.exr" % tag))
    for o in under_objs:
        o.hide_render = False
    for o in main_objs:
        o.hide_render = True
    under = bl.render_exr(scene, os.path.join(RAW, "%s_under.exr" % tag))
    img = bl.composite(main, under, style, ppu)
    y0, y1, x0, x1 = bl.alpha_bbox(img)
    hh, ww = img.shape[:2]
    if y0 < 2 or x0 < 2 or y1 > hh - 2 or x1 > ww - 2:
        bl.fail("composited %s touches render edge" % tag)
    tight = np.ascontiguousarray(img[y0:y1, x0:x1])
    trail_tight = np.ascontiguousarray(under[y0:y1, x0:x1, 3:4])
    return tight, trail_tight


def blur_alpha(mask_2d, sigma):
    h, w = mask_2d.shape
    src = oiio.ImageBuf(oiio.ImageSpec(w, h, 1, oiio.FLOAT))
    src.set_pixels(oiio.ROI(), np.ascontiguousarray(mask_2d[:, :, None], dtype=np.float32))
    kern = oiio.ImageBufAlgo.make_kernel("gaussian", sigma * 2.0 + 1.0, sigma * 2.0 + 1.0)
    dst = oiio.ImageBufAlgo.convolve(src, kern)
    return np.clip(dst.get_pixels(oiio.FLOAT)[:, :, 0], 0.0, 1.0)


def apply_logo_on_capsule(bg_lin, tight, trail_tight, ox, oy, lw, lh, mist_strength, name):
    """Composite Option A over staged key art with a soft sunlit mist halo so the
    navy dotted flight trail stays crisp over any background tone."""
    h, w = bg_lin.shape[:2]
    logo = bl.resize(tight, lw, lh)
    trail = bl.resize(np.repeat(trail_tight, 4, axis=2), lw, lh)[:, :, 0]
    pad = max(16, int(round(max(lw, lh) * 0.16)))
    y0, y1 = max(0, oy - pad), min(h, oy + lh + pad)
    x0, x1 = max(0, ox - pad), min(w, ox + lw + pad)
    patch_mask = np.zeros((y1 - y0, x1 - x0), np.float32)
    ly0, lx0 = oy - y0, ox - x0
    # Weight the mist toward the trail + logo coverage so dark pixels lift smoothly.
    patch_mask[ly0:ly0 + lh, lx0:lx0 + lw] = np.clip(logo[:, :, 3] * 0.75 + trail * 1.35, 0.0, 1.0)
    sigma = max(6.0, min(lw, lh) * 0.14)
    halo = blur_alpha(patch_mask, sigma)
    if halo.max() > 1e-4:
        halo = np.clip(halo / max(0.38, float(np.percentile(halo[halo > 0.01], 92))), 0.0, 1.0)
    mist_alpha = (halo * mist_strength)[:, :, None]
    mist_lin = np.array(bl.to_lin(SUN_MIST_SRGB), dtype=np.float32)[None, None, :]
    out = bg_lin.copy()
    sub = out[y0:y1, x0:x1, :3]
    out[y0:y1, x0:x1, :3] = sub * (1.0 - mist_alpha) + mist_lin * mist_alpha
    # Measure background sRGB luma directly under the navy trail dots BEFORE laying logo.
    bg_under_logo = bl.to_srgb(out[oy:oy + lh, ox:ox + lw, :3])
    bg_luma = 0.2126 * bg_under_logo[:, :, 0] + 0.7152 * bg_under_logo[:, :, 1] + 0.0722 * bg_under_logo[:, :, 2]
    dot_core = (trail > 0.45) & ((logo[:, :, 3] - trail) < 0.25)
    navy_luma = 0.2126 * bl.NAVY[0] + 0.7152 * bl.NAVY[1] + 0.0722 * bl.NAVY[2]
    min_bg_dot = float(bg_luma[dot_core].min()) if dot_core.any() else float(bg_luma.mean())
    mean_bg_dot = float(bg_luma[dot_core].mean()) if dot_core.any() else float(bg_luma.mean())
    print(
        "PROBE trail_contrast %s logo_box=(%d,%d,%dx%d) dot_px=%d navy_luma=%.3f bg_dot_min=%.3f bg_dot_mean=%.3f delta_min=%.3f"
        % (name, ox, oy, lw, lh, int(dot_core.sum()), navy_luma, min_bg_dot, mean_bg_dot, min_bg_dot - navy_luma)
    )
    if min_bg_dot - navy_luma < 0.22:
        bl.fail("%s: navy dotted trail lacks contrast against background (delta=%.3f)" % (name, min_bg_dot - navy_luma))
    out[oy:oy + lh, ox:ox + lw] = bl.over(logo, out[oy:oy + lh, ox:ox + lw])
    return out


def save_and_verify_rgb(filename, img_lin, expected_w, expected_h, check_hero_safe=False):
    path = os.path.join(OUT, filename)
    arr8 = bl.encode(img_lin)[:, :, :3]
    bl.write_png(path, arr8)
    back = bl.read_png(path)
    h, w, c = back.shape
    std_all = float(back.astype(np.float32).std())
    msg = "PROBE readback %s size=%dx%dx%d std=%.2f" % (filename, w, h, c, std_all)
    if check_hero_safe:
        sx0, sy0 = (w - 860) // 2, (h - 380) // 2
        safe_std = float(back[sy0:sy0 + 380, sx0:sx0 + 860].astype(np.float32).std())
        msg += " hero_safe_860x380_std=%.2f" % safe_std
        if safe_std < 12.0:
            bl.fail("%s center 860x380 safe zone lacks detail (std=%.2f)" % (filename, safe_std))
    print(msg)
    if w != expected_w or h != expected_h or c != 3 or std_all < 12.0:
        bl.fail("readback verification failed for %s" % filename)
    return back


def fit_logo_size(tight, max_w, max_h):
    s = min(max_w / float(tight.shape[1]), max_h / float(tight.shape[0]))
    return int(round(tight.shape[1] * s)), int(round(tight.shape[0] * s))


def draw_text_5x7(canvas, x, y, text, color=(235, 238, 245), scale=2):
    cx = x
    for ch in text.upper():
        rows = _FONT_5X7.get(ch, _FONT_5X7[" "])
        for ry, row in enumerate(rows):
            for rx, bit in enumerate(row):
                if bit == "1":
                    py = y + ry * scale
                    px = cx + rx * scale
                    canvas[py:py + scale, px:px + scale] = color
        cx += 6 * scale


def render_checker_rgba(arr8_rgba):
    h, w = arr8_rgba.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w]
    chk = np.where(((yy // 16 + xx // 16) % 2)[:, :, None] == 0, 205.0, 158.0).astype(np.float32)
    a = arr8_rgba[:, :, 3:4].astype(np.float32) / 255.0
    rgb = arr8_rgba[:, :, :3].astype(np.float32) * a + chk * (1.0 - a)
    return (rgb + 0.5).astype(np.uint8)


def fit_thumb(arr_rgb8, max_w, max_h):
    h, w = arr_rgb8.shape[:2]
    s = min(max_w / float(w), max_h / float(h), 1.0)
    tw, th = max(1, int(round(w * s))), max(1, int(round(h * s)))
    if tw == w and th == h:
        return arr_rgb8
    lin = srgb_to_lin_arr(arr_rgb8.astype(np.float32) / 255.0)
    lin4 = np.concatenate([lin, np.ones((h, w, 1), np.float32)], axis=2)
    small = bl.resize(lin4, tw, th)
    return bl.encode(small)[:, :, :3]


def build_contact_sheet(assets):
    sheet_w, sheet_h = 2640, 2020
    sheet = np.full((sheet_h, sheet_w, 3), (28, 33, 46), dtype=np.uint8)
    draw_text_5x7(sheet, 40, 28, "STEAM STORE AND LIBRARY ASSETS (D6B) - 8 DELIVERABLES", scale=3)
    # Row 1: library_hero full width
    hero_thumb = fit_thumb(assets["library_hero.png"], 2560, 620)
    draw_text_5x7(sheet, 40, 78, "LIBRARY_HERO.PNG (3840X1240 - ZERO TEXT)", scale=2)
    sheet[104:104 + hero_thumb.shape[0], 40:40 + hero_thumb.shape[1]] = hero_thumb
    y_row2 = 104 + hero_thumb.shape[0] + 36
    # Row 2: main_capsule, header_capsule, small_capsule + library_logo
    m_thumb = fit_thumb(assets["main_capsule.png"], 920, 528)
    draw_text_5x7(sheet, 40, y_row2, "MAIN_CAPSULE.PNG (1232X706)", scale=2)
    sheet[y_row2 + 24:y_row2 + 24 + m_thumb.shape[0], 40:40 + m_thumb.shape[1]] = m_thumb

    h_thumb = fit_thumb(assets["header_capsule.png"], 760, 355)
    draw_text_5x7(sheet, 1000, y_row2, "HEADER_CAPSULE.PNG (920X430)", scale=2)
    sheet[y_row2 + 24:y_row2 + 24 + h_thumb.shape[0], 1000:1000 + h_thumb.shape[1]] = h_thumb

    s_thumb = assets["small_capsule.png"]
    sy = y_row2 + 24 + h_thumb.shape[0] + 22
    draw_text_5x7(sheet, 1000, sy, "SMALL_CAPSULE.PNG (462X174 1:1)", scale=2)
    sheet[sy + 22:sy + 22 + s_thumb.shape[0], 1000:1000 + s_thumb.shape[1]] = s_thumb

    logo_chk = render_checker_rgba(assets["library_logo.png"])
    l_thumb = fit_thumb(logo_chk, 780, 365)
    draw_text_5x7(sheet, 1800, y_row2, "LIBRARY_LOGO.PNG (1280X606 RGBA)", scale=2)
    sheet[y_row2 + 24:y_row2 + 24 + l_thumb.shape[0], 1800:1800 + l_thumb.shape[1]] = l_thumb

    # Row 3: library_header, vertical_capsule, library_capsule
    y_row3 = max(y_row2 + 24 + m_thumb.shape[0], sy + 22 + s_thumb.shape[0]) + 40
    lh_thumb = fit_thumb(assets["library_header.png"], 840, 392)
    draw_text_5x7(sheet, 40, y_row3, "LIBRARY_HEADER.PNG (920X430)", scale=2)
    sheet[y_row3 + 24:y_row3 + 24 + lh_thumb.shape[0], 40:40 + lh_thumb.shape[1]] = lh_thumb

    v_thumb = fit_thumb(assets["vertical_capsule.png"], 520, 560)
    draw_text_5x7(sheet, 960, y_row3, "VERTICAL_CAPSULE.PNG (748X896)", scale=2)
    sheet[y_row3 + 24:y_row3 + 24 + v_thumb.shape[0], 960:960 + v_thumb.shape[1]] = v_thumb

    lc_thumb = fit_thumb(assets["library_capsule.png"], 460, 560)
    draw_text_5x7(sheet, 1600, y_row3, "LIBRARY_CAPSULE.PNG (600X900)", scale=2)
    sheet[y_row3 + 24:y_row3 + 24 + lc_thumb.shape[0], 1600:1600 + lc_thumb.shape[1]] = lc_thumb

    cs_path = os.path.join(OUT, "contact_sheet.png")
    bl.write_png(cs_path, sheet)
    back = bl.read_png(cs_path)
    print("PROBE readback contact_sheet.png size=%dx%dx%d" % (back.shape[1], back.shape[0], back.shape[2]))


def main():
    os.makedirs(RAW, exist_ok=True)
    if not os.path.isfile(bl.FONT_PATH):
        bl.fail("font missing: %s" % bl.FONT_PATH)

    raw_hero = load_raw_lin("raw_hero_3840x1240.png", 3840, 1240)
    raw_land = load_raw_lin("raw_landscape_2464x1412.png", 2464, 1412)
    raw_port = load_raw_lin("raw_portrait_1496x1792.png", 1496, 1792)

    tight_a, trail_a = render_logo_master("store_a_sticker", bl.build_a)
    tight_sm, trail_sm = render_logo_master("store_a_small", build_a_small)

    assets = {}

    # 1. library_logo.png (1280 wide, <= 720 tall, transparent RGBA, >= 4px clear border)
    margin = max(12, int(round(0.02 * tight_a.shape[1])))
    padded = np.zeros((tight_a.shape[0] + 2 * margin, tight_a.shape[1] + 2 * margin, 4), np.float32)
    padded[margin:margin + tight_a.shape[0], margin:margin + tight_a.shape[1]] = tight_a
    logo_h = int(round(padded.shape[0] * bl.LOGO_W / float(padded.shape[1])))
    logo_path = os.path.join(OUT, "library_logo.png")
    bl.write_png(logo_path, bl.encode(bl.resize(padded, bl.LOGO_W, logo_h)))
    assets["library_logo.png"] = bl.verify_logo(logo_path)

    # 2. library_hero.png (3840 x 1240, ZERO text and ZERO logo)
    assets["library_hero.png"] = save_and_verify_rgb(
        "library_hero.png", raw_hero, 3840, 1240, check_hero_safe=True
    )

    # 3. main_capsule.png (1232 x 706, staged landscape + Option A top-left)
    bg_main = crop_and_resize(raw_land, 1232, 706)
    lw, lh = fit_logo_size(tight_a, 1232 * 0.42, 706 * 0.38)
    comp_main = apply_logo_on_capsule(bg_main, tight_a, trail_a, 28, 22, lw, lh, 0.58, "main_capsule.png")
    assets["main_capsule.png"] = save_and_verify_rgb("main_capsule.png", comp_main, 1232, 706)

    # 4 & 5. header_capsule.png and library_header.png (920 x 430)
    bg_head = crop_and_resize(raw_land, 920, 430, align_y=0.50)
    lw_h, lh_h = fit_logo_size(tight_a, 920 * 0.42, 430 * 0.44)
    comp_head = apply_logo_on_capsule(bg_head, tight_a, trail_a, 18, 16, lw_h, lh_h, 0.60, "header_capsule.png")
    assets["header_capsule.png"] = save_and_verify_rgb("header_capsule.png", comp_head, 920, 430)
    assets["library_header.png"] = save_and_verify_rgb("library_header.png", comp_head, 920, 430)

    # 6. small_capsule.png (462 x 174, Option A nearly filling frame)
    bg_small = crop_and_resize(raw_land, 462, 174, align_y=0.52)
    # Gently lift background so the small capsule reads clean at 1:1 list scale.
    mist_full = np.array(bl.to_lin(SUN_MIST_SRGB), dtype=np.float32)[None, None, :]
    bg_small[:, :, :3] = bg_small[:, :, :3] * 0.65 + mist_full * 0.35
    lw_s, lh_s = fit_logo_size(tight_sm, 462 * 0.90, 174 * 0.88)
    ox_s, oy_s = (462 - lw_s) // 2, (174 - lh_s) // 2
    comp_small = apply_logo_on_capsule(bg_small, tight_sm, trail_sm, ox_s, oy_s, lw_s, lh_s, 0.45, "small_capsule.png")
    assets["small_capsule.png"] = save_and_verify_rgb("small_capsule.png", comp_small, 462, 174)

    # 7. vertical_capsule.png (748 x 896, Option A top-center over portrait key art)
    bg_vert = crop_and_resize(raw_port, 748, 896)
    lw_v, lh_v = fit_logo_size(tight_a, 748 * 0.84, 896 * 0.28)
    ox_v = (748 - lw_v) // 2
    comp_vert = apply_logo_on_capsule(bg_vert, tight_a, trail_a, ox_v, 28, lw_v, lh_v, 0.60, "vertical_capsule.png")
    assets["vertical_capsule.png"] = save_and_verify_rgb("vertical_capsule.png", comp_vert, 748, 896)

    # 8. library_capsule.png (600 x 900, Option A top-center over portrait key art)
    bg_lib = crop_and_resize(raw_port, 600, 900, align_x=0.50)
    lw_l, lh_l = fit_logo_size(tight_a, 600 * 0.86, 900 * 0.27)
    ox_l = (600 - lw_l) // 2
    comp_lib = apply_logo_on_capsule(bg_lib, tight_a, trail_a, ox_l, 32, lw_l, lh_l, 0.60, "library_capsule.png")
    assets["library_capsule.png"] = save_and_verify_rgb("library_capsule.png", comp_lib, 600, 900)

    build_contact_sheet(assets)
    print("DONE 8 Steam assets + contact_sheet.png verified")


if __name__ == "__main__":
    main()
