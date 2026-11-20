"""Build and mux the reproducible 60-90 s Full Gameplay Trailer (board D8b, decision 888d509e).

Run headless in Blender 5.2 (note mandatory `< /dev/null` on Windows .exe from WSL):
  "/mnt/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background \
    --factory-startup --python-exit-code 1 \
    --python 'C:\\Users\\chulf\\Gotta-make-my-flight\\.claude\\worktrees\\d8b-gameplay-trailer\\tools\\blender\\trailer\\build_gameplay_trailer.py' \
    -- --frames <out>/frames --manifest <out>/shots.json --out <out> [--smoke] < /dev/null

Self-contained pipeline:
  1. Verifies contiguous 1920x1080 PNG frames from gameplay_trailer_probe.gd against shots.json.
  2. Writes per-shot filmstrips (strips/<shot>_strip.png) and full-size mid-frames (strips/<shot>_mid.png).
  3. Automatically builds Option A 'Gotta Make My Flight' logo (logo_a_sticker.png) via
     tools/blender/logo/build_logos.py if absent, plus spike-free cream-and-navy Nunito
     section pills matching game/ui/hud_theme.tres.
  4. Mechanically proves zero pixel overlap between every section title pill and open HUD panels.
  5. Synthesizes & mixes 48 kHz stereo cozy score + real D5 game audio SFX (gameplay_audio.wav).
  6. Renders cut/cut_sheet.png, full-size cut/cut_*.png title/modal/end-card stills, and muxes
     gameplay_trailer.mp4 (1920x1080, 30.0 fps, H.264 avc1 >= 5000 kbps + 48 kHz stereo AAC mp4a),
     verified by disk read-back and Audaspace AAC decode.
"""

import argparse
import glob
import json
import os
import shutil
import struct
import sys

sys.dont_write_bytecode = True

import aud
import bpy
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import build_gameplay_audio  # noqa: E402

RES_W = 1920
RES_H = 1080
FPS = 30
CROSS = 8
STRIP_STEP = 36
CUT_SHEET_STEP = 54
TILE = (640, 360)
COLUMNS = 4
HOLD = 28
VIDEO_KBPS = 12000

CREAM = (0.99, 0.97, 0.92)
NAVY = (0.10, 0.13, 0.26)
YELLOW = (1.00, 0.84, 0.44)
TEAL = (0.25, 0.68, 0.68)


def fail(msg):
    print("PROBE_INVALID " + msg, flush=True)
    sys.exit(1)


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    default_out = os.path.join(REPO, "tools", "blender", "out", "gameplay-trailer")
    p = argparse.ArgumentParser()
    p.add_argument("--frames", default=os.path.join(default_out, "frames"))
    p.add_argument("--manifest", default=os.path.join(default_out, "shots.json"))
    p.add_argument("--out", default=default_out)
    p.add_argument("--logo", default=os.path.join(REPO, "tools", "blender", "out", "logo", "logo_a_sticker.png"))
    p.add_argument("--game-audio-dir", default=os.path.join(REPO, "game", "assets", "audio"))
    p.add_argument("--smoke", action="store_true")
    p.add_argument("--strips-only", action="store_true")
    p.add_argument("--no-strips", action="store_true")
    args = p.parse_args(argv)
    for key in ("frames", "manifest", "out", "logo", "game_audio_dir"):
        if getattr(args, key):
            setattr(args, key, os.path.abspath(getattr(args, key)))
    return args


def frame_path(frames_dir, index):
    return os.path.join(frames_dir, "shot%08d.png" % index)


def load_pixels(path):
    image = bpy.data.images.load(path, check_existing=False)
    width, height = image.size
    flat = np.empty(width * height * 4, dtype=np.float32)
    image.pixels.foreach_get(flat)
    bpy.data.images.remove(image)
    return flat.reshape(height, width, 4)[::-1]


def shrink(pixels, size):
    height, width = pixels.shape[:2]
    fy, fx = height // size[1], width // size[0]
    if fy < 1 or fx < 1:
        fail("frame %dx%d smaller than %dx%d tile" % (width, height, size[0], size[1]))
    cut = pixels[: size[1] * fy, : size[0] * fx]
    return cut.reshape(size[1], fy, size[0], fx, 4).mean(axis=(1, 3))


def save_pixels(pixels, path):
    height, width = pixels.shape[:2]
    image = bpy.data.images.new("sheet", width, height, alpha=True)
    image.pixels.foreach_set(np.ascontiguousarray(pixels[::-1]).ravel())
    image.filepath_raw = path
    image.file_format = "PNG"
    image.save()
    bpy.data.images.remove(image)
    if not os.path.isfile(path):
        fail("%s was not written" % path)
    back = bpy.data.images.load(path, check_existing=False)
    print("PROBE plate %s readback=%dx%d" % (path, back.size[0], back.size[1]), flush=True)
    bpy.data.images.remove(back)


def sheet_of(tiles):
    rows = -(-len(tiles) // COLUMNS)
    sheet = np.zeros((rows * TILE[1], COLUMNS * TILE[0], 4), dtype=np.float32)
    sheet[..., 3] = 1.0
    for i, tile in enumerate(tiles):
        y, x = (i // COLUMNS) * TILE[1], (i % COLUMNS) * TILE[0]
        sheet[y : y + TILE[1], x : x + TILE[0]] = tile
    return sheet


# ---------------------------------------------------------------- Self-Contained Logo & Nunito Pills


def _load_logo_builder():
    logo_script = os.path.join(REPO, "tools", "blender", "logo", "build_logos.py")
    if not os.path.isfile(logo_script):
        fail("missing build_logos.py at %s" % logo_script)
    with open(logo_script, "r", encoding="utf-8") as fh:
        src = fh.read()
    cut_idx = src.rfind("\ndef main():")
    if cut_idx < 0:
        fail("could not locate def main() in build_logos.py")
    ns = {"__file__": logo_script, "__name__": "build_logos_lib"}
    exec(compile(src[:cut_idx], logo_script, "exec"), ns)
    return ns, os.path.getmtime(logo_script)


def _render_pill_png(ns, raw_dir, out_path, slug, text, target_h=74, accent_dots=False):
    scene, font = ns["new_scene"]()
    txt = ns["text_obj"](
        scene, font, text, 0.72, 0.030, ns["flat_mat"]("navy_" + slug, NAVY), spacing=1.06
    )
    ns["place"](txt, 0.0, 0.0)
    bx0, bx1, by0, by1 = ns["local_bounds"](txt)
    extra_w = 1.02 if accent_dots else 0.72
    bw = (bx1 - bx0) + extra_w
    bh = (by1 - by0) + 0.54
    pill = ns["poly_obj"](
        scene,
        "pill_" + slug,
        ns["rounded_rect"](0.0, 0.0, bw, bh, bh * 0.46, seg=14),
        ns["flat_mat"]("cream_" + slug, CREAM),
        z=-0.05,
    )
    objs = [txt, pill]
    if accent_dots:
        dot_mat = ns["flat_mat"]("dot_" + slug, YELLOW)
        objs.append(ns["poly_obj"](scene, "dl_" + slug, ns["circle"](bx0 - 0.24, 0.0, 0.085), dot_mat, z=0.01))
        objs.append(ns["poly_obj"](scene, "dr_" + slug, ns["circle"](bx1 + 0.24, 0.0, 0.085), dot_mat, z=0.01))
    style = {"outline": 0.062, "shadow": (0.016, -0.068)}
    ppu = ns["frame_camera"](scene, objs, style)
    exr = ns["render_exr"](scene, os.path.join(raw_dir, "pill_%s.exr" % slug))
    comp = ns["composite"](exr, None, style, ppu)
    y0, y1, x0, x1 = ns["alpha_bbox"](comp)
    tight = comp[y0:y1, x0:x1]
    pad = max(4, int(round(0.03 * tight.shape[0])))
    padded = np.zeros((tight.shape[0] + 2 * pad, tight.shape[1] + 2 * pad, 4), np.float32)
    padded[pad : pad + tight.shape[0], pad : pad + tight.shape[1]] = tight
    out_w = int(round(padded.shape[1] * (float(target_h) / float(padded.shape[0]))))
    ns["write_png"](out_path, ns["encode"](ns["resize"](padded, out_w, target_h)))
    return out_w, target_h


def ensure_ui_overlays(args):
    """Ensure Option A logo_a_sticker.png and all 5 Nunito cream-and-navy pill badges exist."""
    ui_dir = os.path.join(args.out, "ui")
    raw_dir = os.path.join(ui_dir, "raw")
    os.makedirs(raw_dir, exist_ok=True)
    ns, logo_mtime = _load_logo_builder()
    src_mtime = max(logo_mtime, os.path.getmtime(__file__))

    # 1. Option A Logo (build if --logo missing, and copy into <out>/ui/logo_a_sticker.png)
    ui_logo = os.path.join(ui_dir, "logo_a_sticker.png")
    if os.path.isfile(args.logo) and os.path.getmtime(args.logo) >= logo_mtime:
        if os.path.abspath(args.logo) != os.path.abspath(ui_logo):
            shutil.copyfile(args.logo, ui_logo)
    elif not (os.path.isfile(ui_logo) and os.path.getmtime(ui_logo) >= logo_mtime):
        scene, font = ns["new_scene"]()
        main_objs, under_objs, style = ns["build_a"](scene, font)
        ppu = ns["frame_camera"](scene, main_objs + under_objs, style)
        for o in under_objs:
            o.hide_render = True
        main_exr = ns["render_exr"](scene, os.path.join(raw_dir, "logo_main.exr"))
        for o in under_objs:
            o.hide_render = False
        for o in main_objs:
            o.hide_render = True
        under_exr = ns["render_exr"](scene, os.path.join(raw_dir, "logo_under.exr"))
        comp = ns["composite"](main_exr, under_exr, style, ppu)
        y0, y1, x0, x1 = ns["alpha_bbox"](comp)
        tight = comp[y0:y1, x0:x1]
        pad = int(round(0.03 * tight.shape[1]))
        padded = np.zeros((tight.shape[0] + 2 * pad, tight.shape[1] + 2 * pad, 4), np.float32)
        padded[pad : pad + tight.shape[0], pad : pad + tight.shape[1]] = tight
        lw = 1280
        lh = int(round(padded.shape[0] * lw / padded.shape[1]))
        ns["write_png"](ui_logo, ns["encode"](ns["resize"](padded, lw, lh)))
        os.makedirs(os.path.dirname(args.logo), exist_ok=True)
        if os.path.abspath(args.logo) != os.path.abspath(ui_logo):
            shutil.copyfile(ui_logo, args.logo)

    logo_img = bpy.data.images.load(ui_logo, check_existing=False)
    logo_size = (int(logo_img.size[0]), int(logo_img.size[1]))
    bpy.data.images.remove(logo_img)
    print("PROBE brand logo=%s size=%dx%d" % (ui_logo, logo_size[0], logo_size[1]), flush=True)

    # 2. Five spike-free Nunito cream-and-navy pills
    pill_defs = [
        ("build", "Build your terminal", 74, False),
        ("hire", "Hire your crew", 74, False),
        ("follow", "Follow every passenger", 74, False),
        ("grow", "Grow your airline", 74, False),
        ("wishlist", "Wishlist now on Steam", 82, True),
    ]
    pills = {}
    for slug, text, th, dots in pill_defs:
        ppath = os.path.join(ui_dir, "pill_%s.png" % slug)
        if not (os.path.isfile(ppath) and os.path.getmtime(ppath) >= src_mtime):
            _render_pill_png(ns, raw_dir, ppath, slug, text, target_h=th, accent_dots=dots)
        im = bpy.data.images.load(ppath, check_existing=False)
        pw, ph = int(im.size[0]), int(im.size[1])
        bpy.data.images.remove(im)
        pills[slug] = {"path": ppath, "text": text, "w": pw, "h": ph}
        print("PROBE brand pill_%s text=%r size=%dx%d" % (slug, text, pw, ph), flush=True)

    if os.path.isdir(raw_dir):
        shutil.rmtree(raw_dir, ignore_errors=True)
    return {"path": ui_logo, "w": logo_size[0], "h": logo_size[1]}, pills


# ---------------------------------------------------------------- Frame & Overlap Checks


def check_frames(args, manifest):
    files = sorted(glob.glob(os.path.join(args.frames, "shot*.png")))
    if not files:
        fail("no shot*.png under %s" % args.frames)
    low = int(os.path.basename(files[0])[4:12])
    high = int(os.path.basename(files[-1])[4:12])
    offset = high - int(manifest["final_frame"])
    print(
        "PROBE frames files=%d first=%d last=%d manifest_final=%d offset=%d"
        % (len(files), low, high, manifest["final_frame"], offset),
        flush=True,
    )
    if high - low + 1 != len(files):
        fail("the frame sequence has gaps (%d files across %d..%d)" % (len(files), low, high))
    if abs(offset) > 2:
        fail("written frames off manifest final_frame by %d" % offset)
    for shot in manifest["shots"]:
        first_f = shot["first"] + offset
        last_f = first_f + shot["frames"] - 1
        for check_i in (first_f, last_f):
            if not os.path.isfile(frame_path(args.frames, check_i)):
                fail("%s: frame %d missing" % (shot["name"], check_i))
    return offset


def build_strips(args, shots, offset):
    out = os.path.join(args.out, "strips")
    os.makedirs(out, exist_ok=True)
    step = 2 if args.smoke else STRIP_STEP
    for shot in shots:
        start = shot["first"] + offset + shot["handle"]
        body = shot["body"]
        picks = list(range(0, body, step))
        if picks[-1] != body - 1:
            picks.append(body - 1)
        tiles = []
        for k in picks:
            px = load_pixels(frame_path(args.frames, start + k))
            if float(px[:, :, :3].mean()) < 0.015:
                fail("%s: frame %d is blank/black" % (shot["name"], start + k))
            tiles.append(shrink(px, TILE))
        save_pixels(sheet_of(tiles), os.path.join(out, "%s_strip.png" % shot["name"]))
        mid = os.path.join(out, "%s_mid.png" % shot["name"])
        shutil.copyfile(frame_path(args.frames, start + body // 2), mid)
        print(
            "PROBE strip %s source=%d..%d tiles=%d mid=%d"
            % (shot["name"], start, start + body - 1, len(tiles), start + body // 2),
            flush=True,
        )


def _rects_overlap(a, b, pad=8):
    return not (a[2] + pad <= b[0] or b[2] + pad <= a[0] or a[3] + pad <= b[1] or b[3] + pad <= a[1])


def _pill_screen_rect(pill_info, cx_norm, cy_vse_norm, scale=1.0):
    """Convert VSE normalized center (cx_norm in 0..1 left->right, cy_vse_norm in 0..1 bottom->top)
    to 1920x1080 top-left pixel rect [x0, y0, x1, y1]."""
    w = int(round(pill_info["w"] * scale))
    h = int(round(pill_info["h"] * scale))
    cx = int(round(cx_norm * RES_W))
    cy_top = int(round((1.0 - cy_vse_norm) * RES_H))
    return [cx - w // 2, cy_top - h // 2, cx + w // 2, cy_top + h // 2]


def add_image_overlay(editor, name, png_path, first, last, cx_norm, cy_vse_norm, channel, scale=1.0):
    length = max(2, last - first + 1)
    strip = editor.strips.new_image(name, png_path, channel, first)
    strip.frame_final_duration = length
    strip.blend_type = "ALPHA_OVER"
    strip.transform.scale_x = scale
    strip.transform.scale_y = scale
    strip.transform.offset_x = (cx_norm - 0.5) * RES_W
    strip.transform.offset_y = (cy_vse_norm - 0.5) * RES_H
    fade_len = min(8, max(1, length // 3))
    fade(
        strip,
        "blend_alpha",
        [(first, 0.0), (first + fade_len, 1.0), (last - fade_len, 1.0), (last, 0.0)],
    )
    return strip


def add_image_strip(editor, name, frames_dir, first, count, channel, at):
    strip = editor.strips.new_image(name, frame_path(frames_dir, first), channel, at)
    for k in range(1, count):
        strip.elements.append("shot%08d.png" % (first + k))
    return strip


def fade(strip, path, keys):
    for frame, value in keys:
        setattr(strip, path, value)
        strip.keyframe_insert(data_path=path, frame=frame)


# ---------------------------------------------------------------- VSE Cut & Audio Assembly


def build_cut(args, shots, offset, logo_info, pills):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.resolution_x = RES_W
    scene.render.resolution_y = RES_H
    scene.render.resolution_percentage = 100
    scene.render.fps = FPS
    scene.render.fps_base = 1.0
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.render.use_sequencer = True
    editor = scene.sequence_editor_create()

    cross = 4 if args.smoke else CROSS
    half = cross // 2
    hold_len = 6 if args.smoke else HOLD
    at = 1
    previous = None
    last_shot = shots[-1]
    shot_spans = {}
    cut_events = []

    for i, shot in enumerate(shots):
        if shot["handle"] < half:
            fail("%s: handle %d < half dissolve %d" % (shot["name"], shot["handle"], half))
        lead = 0 if i == 0 else half
        tail = shot["handle"] if shot is last_shot else half
        first = shot["first"] + offset + shot["handle"] - lead
        count = lead + shot["body"] + tail
        strip = add_image_strip(editor, shot["name"], args.frames, first, count, 1 + i % 2, at - lead)
        if previous is not None:
            editor.strips.new_effect(
                "x_" + shot["name"], "CROSS", 3, at - half, length=cross, input1=previous, input2=strip
            )
        shot_end = at + shot["body"] - 1
        shot_spans[shot["name"]] = {
            "start": at,
            "end": shot_end,
            "hud_rects": shot.get("hud_rects", {}),
        }
        for ev in shot.get("events", []):
            cf = at + (int(ev["shot_frame"]) - int(shot["handle"]))
            if 1 <= cf <= shot_end + tail:
                ev_copy = dict(ev)
                ev_copy.pop("shot_frame", None)
                ev_copy["frame"] = cf
                cut_events.append(ev_copy)
        print(
            "PROBE cut %s cut_frames=%d..%d source_first=%d count=%d"
            % (shot["name"], at, shot_end, first, count),
            flush=True,
        )
        previous = strip
        at += shot["body"]

    final_source = last_shot["first"] + offset + last_shot["frames"] - 1
    hold_at = at + last_shot["handle"]
    hold = editor.strips.new_image("hold", frame_path(args.frames, final_source), 2, hold_at)
    hold.frame_final_duration = hold_len
    end = hold_at + hold_len - 1

    # Place 4 section title pills dynamically on their target shots & prove zero HUD overlap!
    #   build  -> s01_shell  (cx=0.50, cy_vse=0.165: above CategoryBar)
    #   hire   -> s03_staff  (cx=0.50, cy_vse=0.855: below TopRow, above StaffPanel, clear of sides)
    #   follow -> s05_follow (cx=0.68, cy_vse=0.165: right of PassengerInspect, above CategoryBar)
    #   grow   -> s09_boarding (cx=0.50, cy_vse=0.165: Offers closed, right of DeparturesPanel)
    section_placements = [
        ("build", "s01_shell", 0.50, 0.165),
        ("hire", "s03_staff", 0.50, 0.855),
        ("follow", "s05_follow", 0.68, 0.165),
        ("grow", "s09_boarding", 0.50, 0.165),
    ]
    still_frames = []
    for ch_idx, (slug, sname, cx_n, cy_n) in enumerate(section_placements):
        sp = shot_spans[sname]
        pad_f = 1 if args.smoke else 12
        t_first = sp["start"] + pad_f
        t_last = max(t_first + 2, sp["end"] - pad_f)
        p_rect = _pill_screen_rect(pills[slug], cx_n, cy_n, scale=1.0)
        for h_key, h_rect in sp["hud_rects"].items():
            if _rects_overlap(p_rect, h_rect, pad=6):
                fail(
                    "title pill %r %s overlaps open HUD panel %r %s in %s"
                    % (pills[slug]["text"], p_rect, h_key, h_rect, sname)
                )
        print(
            "PROBE title_clearance %s shot=%s frames=%d..%d pill_rect=%s hud=%s"
            % (slug, sname, t_first, t_last, p_rect, sp["hud_rects"]),
            flush=True,
        )
        add_image_overlay(editor, "pill_" + slug, pills[slug]["path"], t_first, t_last, cx_n, cy_n, 5 + ch_idx)
        still_frames.append((t_first + t_last) // 2)

    # Also capture a full-size still of Shot 08 (Today's offers open & signed)!
    if "s08_offers" in shot_spans:
        sp8 = shot_spans["s08_offers"]
        still_frames.append((sp8["start"] + sp8["end"]) // 2)

    # End Card over Shot 11 (s11_takeoff has HUD hidden): Option A Logo + Wishlist pill!
    s11_start = shot_spans["s11_takeoff"]["start"]
    end_first = max(s11_start + (2 if args.smoke else 66), end - (8 if args.smoke else 126))
    logo_scale = 900.0 / float(max(1, logo_info["w"]))
    logo = editor.strips.new_image("logo", logo_info["path"], 10, end_first)
    logo.frame_final_duration = max(2, end - end_first + 1)
    logo.blend_type = "ALPHA_OVER"
    logo.transform.scale_x = logo_scale
    logo.transform.scale_y = logo_scale
    logo.transform.offset_y = int(round(0.11 * RES_H))
    fade_l = min(12, max(1, (end - end_first) // 3))
    fade(logo, "blend_alpha", [(end_first, 0.0), (end_first + fade_l, 1.0)])

    wish_first = min(end - 2, end_first + (2 if args.smoke else 18))
    wish = editor.strips.new_image("wishlist", pills["wishlist"]["path"], 11, wish_first)
    wish.frame_final_duration = max(2, end - wish_first + 1)
    wish.blend_type = "ALPHA_OVER"
    wish.transform.offset_y = int(round(-0.28 * RES_H))
    fade_w = min(10, max(1, (end - wish_first) // 3))
    fade(wish, "blend_alpha", [(wish_first, 0.0), (wish_first + fade_w, 1.0)])

    cut_events.append({"frame": end_first, "type": "logo_slam"})
    cut_events.append({"frame": wish_first, "type": "badge_pop"})
    cut_events.sort(key=lambda e: int(e["frame"]))
    still_frames.append(max(wish_first + fade_w + 2, end - (2 if args.smoke else 18)))

    # Build & attach 48 kHz stereo audio mix!
    wav_name = "gameplay_audio_smoke.wav" if args.smoke else "gameplay_audio.wav"
    wav_path = os.path.join(args.out, wav_name)
    amb_start = shot_spans["s03_staff"]["start"]
    amb_end = shot_spans["s10_pullback"]["end"]
    fin_start = shot_spans["s09_boarding"]["start"]
    audio_stats = build_gameplay_audio.build_gameplay_audio(
        wav_path,
        cut_events,
        end,
        args.game_audio_dir,
        ambience_range_frames=(amb_start, amb_end),
        finale_start_frame=fin_start,
        logo_slam_frame=end_first,
    )
    sound = editor.strips.new_sound("gameplay_audio", wav_path, 12, 1)
    sound.frame_final_duration = min(sound.frame_final_duration, end)

    scene.frame_start = 1
    scene.frame_end = end
    print(
        "PROBE cut frames=%d seconds=%.2f sound_frames=%d"
        % (end, end / float(FPS), sound.frame_final_duration),
        flush=True,
    )
    return end, sorted(set(still_frames)), audio_stats


def render_stills(args, end, still_frames):
    scene = bpy.context.scene
    out = os.path.join(args.out, "cut")
    os.makedirs(out, exist_ok=True)
    for old in glob.glob(os.path.join(out, "cut_*.png")):
        os.remove(old)
    scene.render.image_settings.media_type = "IMAGE"
    scene.render.image_settings.file_format = "PNG"
    scene.render.resolution_percentage = 100

    step = 8 if args.smoke else CUT_SHEET_STEP
    picks = list(range(1, end + 1, step))
    if picks[-1] != end:
        picks.append(end)
    tiles = []
    for frame in picks:
        scene.frame_set(frame)
        path = os.path.join(out, "tmp_%04d.png" % frame)
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        tiles.append(shrink(load_pixels(path), TILE))
        os.remove(path)
    save_pixels(sheet_of(tiles), os.path.join(out, "cut_sheet.png"))

    for frame in still_frames:
        scene.frame_set(frame)
        scene.render.filepath = os.path.join(out, "cut_%04d.png" % frame)
        bpy.ops.render.render(write_still=True)
        print("PROBE plate %s" % scene.render.filepath, flush=True)


def render_movie(args):
    scene = bpy.context.scene
    mp4_name = "gameplay_trailer_smoke.mp4" if args.smoke else "gameplay_trailer.mp4"
    path = os.path.join(args.out, mp4_name)
    scene.render.resolution_percentage = 100
    scene.render.image_settings.media_type = "VIDEO"
    scene.render.image_settings.file_format = "FFMPEG"
    ff = scene.render.ffmpeg
    ff.format = "MPEG4"
    ff.codec = "H264"
    ff.constant_rate_factor = "NONE"
    ff.video_bitrate = VIDEO_KBPS
    ff.maxrate = VIDEO_KBPS * 4 // 3
    ff.buffersize = VIDEO_KBPS * 2
    ff.gopsize = FPS
    ff.ffmpeg_preset = "GOOD"
    ff.audio_codec = "AAC"
    ff.audio_mixrate = 48000
    ff.audio_channels = "STEREO"
    ff.audio_bitrate = 192
    scene.render.use_file_extension = False
    scene.render.filepath = path
    bpy.ops.render.render(animation=True)
    return path


def _iter_mp4_boxes(buf, start, end):
    pos = start
    while pos + 8 <= end:
        sz, btype = struct.unpack(">I4s", buf[pos : pos + 8])
        hdr = 8
        if sz == 1:
            if pos + 16 > end:
                break
            sz = struct.unpack(">Q", buf[pos + 8 : pos + 16])[0]
            hdr = 16
        elif sz == 0:
            sz = end - pos
        if sz < hdr or pos + sz > end:
            break
        yield btype, pos + hdr, pos + sz
        pos += sz


def _find_moov_stsd_codecs(data):
    found = {}
    containers = {b"moov", b"trak", b"mdia", b"minf", b"stbl"}

    def walk(start, end, in_moov):
        for btype, bstart, bend in _iter_mp4_boxes(data, start, end):
            if btype in containers:
                walk(bstart, bend, in_moov or (btype == b"moov"))
            elif in_moov and btype == b"stsd" and bstart + 8 <= bend:
                for etype, estart, eend in _iter_mp4_boxes(data, bstart + 8, bend):
                    found[etype] = data[estart:eend]

    walk(0, len(data), False)
    return found


def verify_mp4(path, expected_frames, smoke=False):
    if not os.path.isfile(path):
        fail("%s was not written" % path)
    with open(path, "rb") as fh:
        data = fh.read()
    stsd = _find_moov_stsd_codecs(data)
    has_avc1 = b"avc1" in stsd
    has_mp4a = b"mp4a" in stsd
    clip = bpy.data.movieclips.load(path)
    w, h = clip.size
    fps = float(clip.fps)
    n_frames = int(clip.frame_duration)
    dur_s = n_frames / max(1e-6, fps)
    avg_kbps = (len(data) * 8.0) / 1000.0 / max(1e-6, dur_s)

    channels = rate = 0
    if has_mp4a and len(stsd[b"mp4a"]) >= 28:
        body = stsd[b"mp4a"]
        channels = struct.unpack(">H", body[16:18])[0]
        rate = struct.unpack(">I", body[24:28])[0] >> 16

    print(
        "PROBE mp4_readback path=%s res=%dx%d fps=%.3f frames=%d duration_s=%.2f size_mb=%.2f avg_kbps=%.0f avc1=%s mp4a=%s audio_rate=%d channels=%d"
        % (
            path,
            w,
            h,
            fps,
            n_frames,
            dur_s,
            len(data) / 1048576.0,
            avg_kbps,
            has_avc1,
            has_mp4a,
            rate,
            channels,
        ),
        flush=True,
    )
    if (w, h) != (RES_W, RES_H):
        fail("MP4 resolution %dx%d != 1920x1080" % (w, h))
    if abs(fps - float(FPS)) > 0.05:
        fail("MP4 fps %.3f != 30.0" % fps)
    if not smoke and not (60.0 <= dur_s <= 90.0):
        fail("MP4 duration %.2fs outside [60.0, 90.0]s" % dur_s)
    if abs(n_frames - expected_frames) > 2:
        fail("MP4 frames %d != expected %d" % (n_frames, expected_frames))
    if not smoke and avg_kbps < 5000.0:
        fail("MP4 avg_kbps %.0f < 5000 kbps" % avg_kbps)
    if not has_avc1 or not has_mp4a or rate != 48000 or channels != 2:
        fail("MP4 missing avc1 or 48kHz stereo mp4a (avc1=%s mp4a=%s rate=%d ch=%d)" % (has_avc1, has_mp4a, rate, channels))

    snd = aud.Sound(path)
    sr, ch = snd.specs
    pcm = snd.data()
    if pcm.ndim == 1:
        pcm = pcm[:, None]
    third = max(1, len(pcm) // 3)
    for wname, seg in (("early", pcm[:third]), ("mid", pcm[third : 2 * third]), ("end", pcm[2 * third :])):
        pk = float(np.abs(seg).max())
        rms = float(np.sqrt(np.mean(seg.astype(np.float64) ** 2)))
        print("PROBE mp4_audio_window %s peak=%.4f rms=%.4f" % (wname, pk, rms), flush=True)
        if pk < 0.05 or rms < 0.01:
            fail("decoded MP4 audio window %s too quiet (peak=%.4f rms=%.4f)" % (wname, pk, rms))


def main():
    args = parse_args()
    with open(args.manifest, "r", encoding="utf-8") as fh:
        manifest = json.load(fh)
    shots = sorted(manifest["shots"], key=lambda s: s["name"])
    print("PROBE manifest seed=%s shots=%s" % (manifest["seed"], [s["name"] for s in shots]), flush=True)
    offset = check_frames(args, manifest)
    if not args.no_strips:
        build_strips(args, shots, offset)
    if args.strips_only:
        return
    logo_info, pills = ensure_ui_overlays(args)
    end, still_frames, _audio_stats = build_cut(args, shots, offset, logo_info, pills)
    render_stills(args, end, still_frames)
    mp4_path = render_movie(args)
    verify_mp4(mp4_path, end, smoke=args.smoke)
    print("GAMEPLAY_TRAILER_COMPLETE " + mp4_path, flush=True)


if __name__ == "__main__":
    main()
