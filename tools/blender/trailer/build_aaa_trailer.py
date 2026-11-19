"""Master reproducible headless Blender 5.2 pipeline for the Gotta Make My Flight
30-45s pre-rendered 3D cinematic CG story trailer (board D8a, decision 888d509e).

Run from WSL (note mandatory `< /dev/null` for Windows .exe under agy, anti-pattern a69ffb51):
  "/mnt/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background \
    --factory-startup --python-exit-code 1 \
    --python 'C:\\Users\\chulf\\Gotta-make-my-flight\\.claude\\worktrees\\aaa-trailer\\tools\\blender\\trailer\\build_aaa_trailer.py' \
    [-- --strips-only] < /dev/null

Outputs under tools/blender/out/aaa-trailer/ (gitignored):
  ui/logo_a_sticker.png         Option A 'Gotta Make My Flight' sticker wordmark
  ui/wishlist_badge.png         'WISHLIST ON STEAM' pill badge (spike-free SDF Nunito)
  strips/shot_01_strip.png ..   Per-shot 5-frame horizontal filmstrips (640x360 x 5 = 3200x360)
  contact_sheet.png             Stitched 6x5 full-trailer storyboard sheet (3200x2160)
  audio/trailer_mix.wav         48 kHz stereo score + frame-accurate foley mix
  aaa_teaser.mp4                1920x1080, 30 fps, H.264 >= 5000 kbps + 48 kHz AAC stereo
  verification_report.json      Measured prove_in_frame coords, MP4 & audio RMS proofs
"""

import argparse
import json
import math
import os
import struct
import sys
import time

sys.dont_write_bytecode = True

import aud
import bpy
import numpy as np
import OpenImageIO as oiio

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import build_audio  # noqa: E402
import shots  # noqa: E402
import toon_kit as tk  # noqa: E402

VIDEO_KBPS = 14000
TILE_W = 640
TILE_H = 360


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--strips-only", action="store_true", help="Render only the 5 strip keyframes per shot for fast visual QA")
    p.add_argument("--verify-only", action="store_true", help="Run verify_human_motion + 23 prove_subject_in_frame checks without rendering")
    p.add_argument("--extra-frames", nargs="*", type=int, default=[], help="Extra global 1-indexed frames to render in --strips-only mode")
    p.add_argument("--encode-only", action="store_true", help="Re-mix audio & VSE encode from already-rendered frames")
    return p.parse_args(argv)


def _elastic_scale(frame_local, start_local):
    """2D elastic pop-in scale curve for Shot 6 Logo Slam & Wishlist Callout."""
    dt = frame_local - start_local
    if dt < 0:
        return 0.0
    if dt == 0:
        return 0.35
    if dt <= 4:
        return 0.35 + (1.14 - 0.35) * (dt / 4.0)
    if dt <= 8:
        return 1.14 + (0.95 - 1.14) * ((dt - 4.0) / 4.0)
    if dt <= 12:
        return 0.95 + (1.03 - 0.95) * ((dt - 8.0) / 4.0)
    if dt <= 16:
        return 1.03 + (1.00 - 1.03) * ((dt - 12.0) / 4.0)
    return 1.0


def _resize_rgba(img, w, h):
    if w <= 0 or h <= 0:
        return None
    src = oiio.ImageBuf(oiio.ImageSpec(img.shape[1], img.shape[0], 4, oiio.FLOAT))
    src.set_pixels(oiio.ROI(), np.ascontiguousarray(img, dtype=np.float32))
    dst = oiio.ImageBufAlgo.resize(src, filtername="lanczos3", roi=oiio.ROI(0, w, 0, h, 0, 1, 0, 4))
    return np.clip(dst.get_pixels(oiio.FLOAT), 0.0, 1.0)


def _alpha_over(bg_rgba, fg_rgba, cx, cy):
    """Composite straight-alpha sRGB `fg_rgba` centered at pixel `(cx, cy)` over `bg_rgba`."""
    if fg_rgba is None:
        return bg_rgba
    H, W = bg_rgba.shape[:2]
    fh, fw = fg_rgba.shape[:2]
    x0 = cx - fw // 2
    y0 = cy - fh // 2
    sx0 = max(0, -x0)
    sy0 = max(0, -y0)
    dx0 = max(0, x0)
    dy0 = max(0, y0)
    cw = min(fw - sx0, W - dx0)
    ch = min(fh - sy0, H - dy0)
    if cw <= 0 or ch <= 0:
        return bg_rgba
    sub_fg = fg_rgba[sy0 : sy0 + ch, sx0 : sx0 + cw]
    sub_bg = bg_rgba[dy0 : dy0 + ch, dx0 : dx0 + cw]
    a = sub_fg[:, :, 3:4]
    out_rgb = sub_fg[:, :, :3] * a + sub_bg[:, :, :3] * (1.0 - a)
    bg_rgba[dy0 : dy0 + ch, dx0 : dx0 + cw, :3] = out_rgb
    return bg_rgba


def postprocess_rendered_frame(frame_path, shot_id, f_local, logo_rgba, badge_rgba):
    """Apply AAA Highlight Bloom + Lens Vignette + Warm Contrast grade to the 3D render,
    and then composite crisp Option A Logo & Wishlist Badge on Shot 6."""
    arr = tk.apply_cinematic_grade(tk.read_png_float(frame_path))
    if shot_id == "shot_06":
        s_logo = _elastic_scale(f_local, 18)
        s_badge = _elastic_scale(f_local, 42)
        if s_logo > 0.0:
            lw = int(round(1120 * s_logo))
            lh = int(round(logo_rgba.shape[0] * (lw / float(logo_rgba.shape[1]))))
            arr = _alpha_over(arr, _resize_rgba(logo_rgba, lw, lh), tk.RES_W // 2, int(tk.RES_H * 0.56))
        if s_badge > 0.0:
            bw = int(round(740 * s_badge))
            bh = int(round(badge_rgba.shape[0] * (bw / float(badge_rgba.shape[1]))))
            arr = _alpha_over(arr, _resize_rgba(badge_rgba, bw, bh), tk.RES_W // 2, int(tk.RES_H * 0.85))
    tk.write_png_float(frame_path, arr)


def pick_five_frames(n_frames):
    """Pick 5 evenly spaced frames [start, 25%, mid, 75%, end] (1-indexed)."""
    return [
        1,
        1 + (n_frames - 1) // 4,
        1 + (n_frames - 1) // 2,
        1 + (3 * (n_frames - 1)) // 4,
        n_frames,
    ]


def shrink_tile(rgba, tw=TILE_W, th=TILE_H):
    h, w = rgba.shape[:2]
    fy, fx = h // th, w // tw
    return rgba[: th * fy, : tw * fx].reshape(th, fy, tw, fx, 4).mean(axis=(1, 3))


def encode_vse_mp4(frames_dir, wav_path, mp4_path, total_frames):
    """Encode 1920x1080 30fps H.264 + 48kHz Stereo AAC .mp4 in Blender 5.2 VSE."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.resolution_x = tk.RES_W
    scene.render.resolution_y = tk.RES_H
    scene.render.resolution_percentage = 100
    scene.render.fps = tk.FPS
    scene.render.fps_base = 1.0
    scene.frame_start = 1
    scene.frame_end = total_frames
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.render.use_sequencer = True

    ed = scene.sequence_editor_create()
    first_png = os.path.join(frames_dir, "frame_0001.png")
    if not os.path.isfile(first_png):
        tk.fail("missing first frame: %s" % first_png)
    img_strip = ed.strips.new_image("TrailerFrames", first_png, 1, 1)
    for f in range(2, total_frames + 1):
        fn = "frame_%04d.png" % f
        if not os.path.isfile(os.path.join(frames_dir, fn)):
            tk.fail("missing rendered frame %s" % fn)
        img_strip.elements.append(fn)

    snd_strip = ed.strips.new_sound("TrailerAudio", wav_path, 2, 1)
    tk.log("PROBE vse image_frames=%d sound_frames=%d" % (img_strip.frame_final_duration, snd_strip.frame_final_duration))

    scene.render.image_settings.media_type = "VIDEO"
    scene.render.image_settings.file_format = "FFMPEG"
    ff = scene.render.ffmpeg
    ff.format = "MPEG4"
    ff.codec = "H264"
    ff.constant_rate_factor = "NONE"
    ff.video_bitrate = VIDEO_KBPS
    ff.maxrate = VIDEO_KBPS * 4 // 3
    ff.buffersize = VIDEO_KBPS * 2
    ff.gopsize = tk.FPS
    ff.ffmpeg_preset = "GOOD"
    ff.audio_codec = "AAC"
    ff.audio_mixrate = 48000
    ff.audio_channels = "STEREO"
    ff.audio_bitrate = 192
    scene.render.use_file_extension = False
    scene.render.filepath = mp4_path
    bpy.ops.render.render(animation=True)


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
    """Walk ISO BMFF `moov -> trak -> mdia -> minf -> stbl -> stsd` boxes and return
    dict mapping sample-entry fourcc (e.g. b'avc1', b'mp4a') -> entry payload bytes."""
    found = {}
    containers = {b"moov", b"trak", b"mdia", b"minf", b"stbl"}

    def walk(start, end, in_moov):
        for btype, body_start, body_end in _iter_mp4_boxes(data, start, end):
            if btype in containers:
                walk(body_start, body_end, in_moov or (btype == b"moov"))
            elif in_moov and btype == b"stsd" and body_start + 8 <= body_end:
                for etype, estart, eend in _iter_mp4_boxes(data, body_start + 8, body_end):
                    found[etype] = data[estart:eend]

    walk(0, len(data), False)
    return found


def verify_mp4(mp4_path, expected_frames):
    """Verify written MP4 resolution, fps, duration in [34..45]s, bitrate >= 5000 kbps,
    ISO BMFF moov/stsd avc1 + mp4a sample entries, AND decoded audio via Audaspace!"""
    if not os.path.isfile(mp4_path):
        tk.fail("aaa_teaser.mp4 was not written: %s" % mp4_path)
    with open(mp4_path, "rb") as fh:
        data = fh.read()
    stsd_entries = _find_moov_stsd_codecs(data)
    has_avc1 = b"avc1" in stsd_entries
    has_mp4a = b"mp4a" in stsd_entries
    clip = bpy.data.movieclips.load(mp4_path)
    w, h = clip.size
    fps = float(clip.fps)
    n_frames = int(clip.frame_duration)
    dur_s = n_frames / max(1e-6, fps)
    avg_kbps = (len(data) * 8.0) / 1000.0 / max(1e-6, dur_s)

    channels = rate = 0
    if has_mp4a and len(stsd_entries[b"mp4a"]) >= 28:
        mp4a_body = stsd_entries[b"mp4a"]
        channels = struct.unpack(">H", mp4a_body[16:18])[0]
        rate = struct.unpack(">I", mp4a_body[24:28])[0] >> 16

    tk.log(
        "PROBE mp4_readback path=%s res=%dx%d fps=%.3f frames=%d duration=%.2fs size_mb=%.2f avg_kbps=%.0f avc1=%s mp4a=%s rate=%d ch=%d"
        % (
            mp4_path,
            w,
            h,
            fps,
            n_frames,
            dur_s,
            len(data) / (1024.0 * 1024.0),
            avg_kbps,
            has_avc1,
            has_mp4a,
            rate,
            channels,
        )
    )
    if (w, h) != (1920, 1080):
        tk.fail("MP4 resolution %dx%d != 1920x1080" % (w, h))
    if abs(fps - 30.0) > 0.05:
        tk.fail("MP4 fps %.3f != 30" % fps)
    if not (34.0 <= dur_s <= 45.0):
        tk.fail("MP4 duration %.2fs outside [34.0, 45.0]s" % dur_s)
    if abs(n_frames - expected_frames) > 2:
        tk.fail("MP4 frames %d != expected %d" % (n_frames, expected_frames))
    if avg_kbps < 5000.0:
        tk.fail("MP4 total bitrate %.0f kbps < 5000 kbps (size %.2f MB)" % (avg_kbps, len(data) / 1048576.0))
    if not has_avc1 or not has_mp4a or rate != 48000 or channels != 2:
        tk.fail("MP4 moov/stsd missing H.264 avc1 or 48kHz stereo AAC mp4a stream (rate=%d ch=%d)" % (rate, channels))

    # Decode the actual muxed AAC audio stream from aaa_teaser.mp4 via Blender's bundled
    # Audaspace (`aud`) C++ decoder to prove non-zero peak & RMS across early/mid/end!
    snd = aud.Sound(mp4_path)
    sr, ch = snd.specs
    pcm = snd.data()
    if pcm.ndim == 1:
        pcm = pcm[:, None]
    third = len(pcm) // 3
    mp4_audio_stats = {"samplerate": int(round(sr)), "channels": int(ch), "samples": int(len(pcm)), "windows": {}}
    for wname, seg in (("early", pcm[:third]), ("mid", pcm[third : 2 * third]), ("end", pcm[2 * third :])):
        pk = float(np.abs(seg).max())
        rms = float(np.sqrt(np.mean(seg.astype(np.float64) ** 2)))
        tk.log("PROBE mp4_audio_window %s peak=%.4f rms=%.4f" % (wname, pk, rms))
        if pk < 0.05 or rms < 0.01:
            tk.fail("decoded MP4 audio window %s too quiet (peak=%.4f rms=%.4f)" % (wname, pk, rms))
        mp4_audio_stats["windows"][wname] = {"peak": round(pk, 4), "rms": round(rms, 4)}

    return {
        "resolution": [w, h],
        "fps": round(fps, 3),
        "frames": n_frames,
        "duration_s": round(dur_s, 2),
        "bytes": len(data),
        "size_mb": round(len(data) / (1024.0 * 1024.0), 2),
        "avg_kbps": round(avg_kbps, 1),
        "avc1": has_avc1,
        "mp4a": has_mp4a,
        "audio_rate": rate,
        "audio_channels": channels,
        "decoded_mp4_audio": mp4_audio_stats,
    }


def main():
    t_start = time.time()
    args = parse_args()

    ui_dir = os.path.join(tk.OUT_DIR, "ui")
    frames_dir = os.path.join(tk.OUT_DIR, "frames")
    strips_dir = os.path.join(tk.OUT_DIR, "strips")
    audio_dir = os.path.join(tk.OUT_DIR, "audio")
    for d in (ui_dir, frames_dir, strips_dir, audio_dir):
        os.makedirs(d, exist_ok=True)

    logo_path, badge_path = tk.ensure_branding_pngs(ui_dir)
    logo_rgba = tk.read_png_float(logo_path)
    badge_rgba = tk.read_png_float(badge_path)

    total_frames = sum(s["frames"] for s in shots.SHOT_SPECS)
    all_events = []
    in_frame_proofs = []
    human_motion_proofs = []
    strip_rows = []

    if not args.encode_only:
        from bpy_extras.object_utils import world_to_camera_view
        grip_strip_globals = [110, 205, 337, 565, 650, 843]
        grip_crop_centers = {}
        g_cursor = 0
        for s_idx, (spec, builder) in enumerate(zip(shots.SHOT_SPECS, shots.SHOT_BUILDERS)):
            shot_id = spec["id"]
            n_f = spec["frames"]
            tk.log("=== BUILDING %s (%s, %d frames, global %d..%d) ===" % (shot_id, spec["title"], n_f, g_cursor + 1, g_cursor + n_f))
            scene, cam, prove_targets, hero_arm, evs, motion_spec = builder(g_cursor)
            all_events.extend(evs)

            # 0. Automated per-frame human motion, quaternion bone, stride-lock & >=0.45m obstacle clearance verification!
            hm_summary = tk.verify_human_motion(
                scene,
                shot_id,
                n_f,
                obstacle_roots=motion_spec.get("obstacle_roots"),
                extra_boxes_xy=motion_spec.get("extra_boxes_xy"),
                seated_exempt=motion_spec.get("seated_exempt"),
                exempt_ranges=motion_spec.get("exempt_ranges"),
                pulled_rollers=motion_spec.get("pulled_rollers"),
                roller_grip_checks=motion_spec.get("roller_grip_checks"),
                forbid_char_boxes=motion_spec.get("forbid_char_boxes"),
                stair_foot_checks=motion_spec.get("stair_foot_checks"),
                min_clearance=0.45,
            )
            human_motion_proofs.append(hm_summary)

            # Record exact projected pixel centers of Hero's right hand + handle for zoomed `roller_grip_strip.png`!
            if hero_arm is not None:
                for ggf in grip_strip_globals:
                    if g_cursor < ggf <= g_cursor + n_f:
                        scene.frame_set(ggf - g_cursor)
                        bpy.context.view_layer.update()
                        pb_kn = hero_arm.pose.bones.get("Fingers.R") or hero_arm.pose.bones.get("Hand.R")
                        ndc_g = world_to_camera_view(scene, cam, hero_arm.matrix_world @ pb_kn.head)
                        grip_crop_centers[ggf] = (
                            int(round(float(ndc_g.x) * tk.RES_W)),
                            int(round((1.0 - float(ndc_g.y)) * tk.RES_H)),
                        )

            # 1. Automated prove_in_frame + raycast occlusion check on every shot target!
            for tag, fl, subj_objs in prove_targets:
                scene.frame_set(fl)
                proof = tk.prove_subject_in_frame(
                    scene,
                    cam,
                    subj_objs,
                    "%s_%s(f=%d)" % (shot_id, tag, g_cursor + fl),
                    check_occlusion=True,
                )
                in_frame_proofs.append(proof)

            if args.verify_only:
                g_cursor += n_f
                continue

            # 2. Render frames: fast GPU batch `animation=True` for full build, or stills for --strips-only
            default_extra_beats = [18, 19, 20, 24, 28, 110, 205, 243, 337, 441, 532, 565, 650, 700, 829, 830, 836, 843, 850, 858, 866, 885, 892]
            all_extra_globals = set(default_extra_beats) | set(args.extra_frames)
            five_picks = pick_five_frames(n_f)
            extra_locals = {gf - g_cursor for gf in all_extra_globals if g_cursor < gf <= g_cursor + n_f}
            scene.render.image_settings.media_type = "IMAGE"
            scene.render.image_settings.file_format = "PNG"
            scene.render.image_settings.color_mode = "RGBA"
            scene.render.use_file_extension = True

            if args.strips_only:
                for fl in sorted(set(five_picks) | extra_locals):
                    gf = g_cursor + fl
                    out_png = os.path.join(frames_dir, "frame_%04d.png" % gf)
                    scene.frame_set(fl)
                    scene.render.filepath = out_png
                    bpy.ops.render.render(write_still=True)
                    postprocess_rendered_frame(out_png, shot_id, fl, logo_rgba, badge_rgba)
            else:
                scene.frame_start = 1
                scene.frame_end = n_f
                raw_prefix = os.path.join(frames_dir, "_raw_%s_" % shot_id)
                scene.render.filepath = raw_prefix
                bpy.ops.render.render(animation=True)
                for fl in range(1, n_f + 1):
                    gf = g_cursor + fl
                    src_png = "%s%04d.png" % (raw_prefix, fl)
                    out_png = os.path.join(frames_dir, "frame_%04d.png" % gf)
                    if not os.path.isfile(src_png):
                        tk.fail("expected animation frame missing: %s" % src_png)
                    os.replace(src_png, out_png)
                    postprocess_rendered_frame(out_png, shot_id, fl, logo_rgba, badge_rgba)

            # Verify rendered pixel quality & character skin on all 5 strip keyframes (+ extra frames)!
            for fl in sorted(set(five_picks) | extra_locals):
                gf = g_cursor + fl
                out_png = os.path.join(frames_dir, "frame_%04d.png" % gf)
                scene.frame_set(fl)
                arr = tk.read_png_float(out_png)
                suv = None
                if shot_id == "shot_03" and (34 <= fl <= 58 or 132 <= fl <= 154):
                    alt_name = "CHAR_QueuePax1" if fl <= 58 else "CHAR_SecOfficer"
                    alt_arm = next(
                        (c for o in scene.objects if o.name == alt_name for c in o.children if c.type == "ARMATURE"),
                        None,
                    )
                    if alt_arm is not None:
                        suv = tk.head_ndc(scene, cam, alt_arm)
                else:
                    hero_visible = (
                        hero_arm is not None
                        and not (shot_id == "shot_01" and fl < 35)
                        and not (shot_id == "shot_05" and fl > 48)
                    )
                    if hero_visible:
                        suv = tk.head_ndc(scene, cam, hero_arm)
                tk.verify_frame_not_black_and_skin(arr, "%s_f%04d" % (shot_id, gf), skin_uv=suv)

            # 3. Build 5-frame horizontal filmstrip for this shot!
            tiles = [shrink_tile(tk.read_png_float(os.path.join(frames_dir, "frame_%04d.png" % (g_cursor + fl)))) for fl in five_picks]
            strip_img = np.concatenate(tiles, axis=1)
            strip_path = os.path.join(strips_dir, "%s_strip.png" % shot_id)
            tk.write_png_float(strip_path, strip_img)
            tk.log("PROBE strip wrote %s (%dx%d)" % (strip_path, strip_img.shape[1], strip_img.shape[0]))
            strip_rows.append(strip_img)

            g_cursor += n_f

        if args.verify_only:
            tk.log("VERIFY_ONLY_PASS shots=%d in_frame=%d/%d" % (len(shots.SHOT_SPECS), len(in_frame_proofs), len(in_frame_proofs)))
            return

        # Stitch full 6x5 storyboard contact_sheet.png with clean dark gutters!
        gut = 8
        H = len(strip_rows) * TILE_H + (len(strip_rows) + 1) * gut
        W = 5 * TILE_W + 6 * gut
        sheet = np.full((H, W, 4), 0.08, dtype=np.float32)
        sheet[:, :, 3] = 1.0
        for r_i, row_arr in enumerate(strip_rows):
            y0 = gut + r_i * (TILE_H + gut)
            for c_i in range(5):
                x0 = gut + c_i * (TILE_W + gut)
                sheet[y0 : y0 + TILE_H, x0 : x0 + TILE_W] = row_arr[:, c_i * TILE_W : (c_i + 1) * TILE_W]
        contact_path = os.path.join(tk.OUT_DIR, "contact_sheet.png")
        tk.write_png_float(contact_path, sheet)
        tk.log("PROBE contact_sheet wrote %s (%dx%d)" % (contact_path, W, H))

        # Write dedicated 6-tile `extra_beats_strip.png` covering taxi step-out, Shot 2 pop-in & 00:11 turn,
        # Shot 3 two-hand tray heave + rubber duck & pickup snatch, and Shot 5 stair climb!
        beat_globals = [28, 243, 337, 441, 532, 843]
        beat_tiles = [shrink_tile(tk.read_png_float(os.path.join(frames_dir, "frame_%04d.png" % gf))) for gf in beat_globals]
        extra_strip = np.concatenate(beat_tiles, axis=1)
        extra_strip_path = os.path.join(strips_dir, "extra_beats_strip.png")
        tk.write_png_float(extra_strip_path, extra_strip)
        tk.log("PROBE extra_beats_strip wrote %s (%dx%d)" % (extra_strip_path, extra_strip.shape[1], extra_strip.shape[0]))

        # Write dedicated 6-tile zoomed `stair_climb_strip.png` across Shot 5 f=19,26,33,40,48,56 (global 829..866)
        # centered on the airstairs so boot-to-tread contact is large and crystal-clear!
        stair_globals = [829, 836, 843, 850, 858, 866]
        stair_tiles = []
        for sgf in stair_globals:
            s_arr = tk.read_png_float(os.path.join(frames_dir, "frame_%04d.png" % sgf))
            crop = s_arr[240:780, 360:1320, :]
            stair_tiles.append(_resize_rgba(crop, TILE_W, TILE_H))
        stair_strip = np.concatenate(stair_tiles, axis=1)
        stair_strip_path = os.path.join(strips_dir, "stair_climb_strip.png")
        tk.write_png_float(stair_strip_path, stair_strip)
        tk.log("PROBE stair_climb_strip wrote %s (%dx%d)" % (stair_strip_path, stair_strip.shape[1], stair_strip.shape[0]))

        # Write dedicated 6-tile zoomed `roller_grip_strip.png` (`3840x640`) tightly cropped on Hero's right hand + handle
        # across Shot 1 f=110, Shot 2 f=40 (0205), Shot 2 f=172 (0337), Shot 3 f=175 (0565), Shot 4 (0650), Shot 5 f=33 (0843)!
        grip_tiles = []
        half_c = 160
        for ggf in grip_strip_globals:
            g_arr = tk.read_png_float(os.path.join(frames_dir, "frame_%04d.png" % ggf))
            cx_p, cy_p = grip_crop_centers.get(ggf, (tk.RES_W // 2, tk.RES_H // 2))
            x0_c = max(0, min(tk.RES_W - 2 * half_c, cx_p - half_c))
            y0_c = max(0, min(tk.RES_H - 2 * half_c, cy_p - half_c))
            g_crop = g_arr[y0_c : y0_c + 2 * half_c, x0_c : x0_c + 2 * half_c, :]
            grip_tiles.append(_resize_rgba(g_crop, 640, 640))
        grip_strip = np.concatenate(grip_tiles, axis=1)
        grip_strip_path = os.path.join(strips_dir, "roller_grip_strip.png")
        tk.write_png_float(grip_strip_path, grip_strip)
        tk.log("PROBE roller_grip_strip wrote %s (%dx%d)" % (grip_strip_path, grip_strip.shape[1], grip_strip.shape[0]))

        with open(os.path.join(tk.OUT_DIR, "shot_events.json"), "w", encoding="utf-8") as fh:
            json.dump(
                {
                    "total_frames": total_frames,
                    "fps": tk.FPS,
                    "events": all_events,
                    "in_frame": in_frame_proofs,
                    "human_motion": human_motion_proofs,
                },
                fh,
                indent=2,
            )

    if args.strips_only:
        tk.log("STRIPS_ONLY_DONE elapsed=%.1fs shots=%d" % (time.time() - t_start, len(shots.SHOT_SPECS)))
        return

    ev_json = os.path.join(tk.OUT_DIR, "shot_events.json")
    saved = json.load(open(ev_json, "r", encoding="utf-8"))
    all_events = saved["events"]
    in_frame_proofs = saved["in_frame"]
    human_motion_proofs = saved.get("human_motion", [])

    wav_path = os.path.join(audio_dir, "trailer_mix.wav")
    audio_stats = build_audio.build_trailer_audio(wav_path, all_events, total_frames=total_frames)

    mp4_path = os.path.join(tk.OUT_DIR, "aaa_teaser.mp4")
    encode_vse_mp4(frames_dir, wav_path, mp4_path, total_frames)
    mp4_stats = verify_mp4(mp4_path, total_frames)

    report = {
        "elapsed_s": round(time.time() - t_start, 1),
        "mp4": mp4_stats,
        "wav": audio_stats,
        "human_motion_proofs": human_motion_proofs,
        "in_frame_proofs": in_frame_proofs,
    }
    report_path = os.path.join(tk.OUT_DIR, "verification_report.json")
    with open(report_path, "w", encoding="utf-8") as fh:
        json.dump(report, fh, indent=2)
    tk.log("AAA_TRAILER_COMPLETE " + json.dumps(report["mp4"]))


if __name__ == "__main__":
    main()
