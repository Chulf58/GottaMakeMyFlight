"""Self-contained 48 kHz stereo cozy-tycoon soundtrack + D5 game SFX mixer
for the Gotta Make My Flight 60-90s Full Gameplay Trailer (board D8b, decision 888d509e).

Loads and resamples the real merged D5 game audio cues from game/assets/audio/
(terminal_ambience.wav, build_place.wav, build_remove.wav, cash_chime.wav, ui_click.wav),
layers a 100 BPM (18 frames/beat @ 30 fps) beat-locked multi-section cozy acoustic-jazz
& marimba underscore, and mixes frame-accurate gameplay SFX events from shots.json.

Run standalone or imported by build_gameplay_trailer.py:
  "/mnt/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background \
    --factory-startup --python-exit-code 1 \
    --python tools/blender/trailer/build_gameplay_audio.py < /dev/null
"""

import argparse
import json
import math
import os
import sys
import wave

sys.dont_write_bytecode = True

import numpy as np

SAMPLE_RATE = 48000
FPS = 30
BPM = 100.0
BEAT_FRAMES = 18  # 60 / 100 * 30 = 18.0 frames per beat exact!


def fail(msg):
    print("PROBE_INVALID " + msg, flush=True)
    sys.exit(1)


def midi_to_hz(m):
    return 440.0 * (2.0 ** ((m - 69.0) / 12.0))


def _pan(mono, pan=0.0):
    ang = (np.clip(pan, -1.0, 1.0) + 1.0) * (math.pi / 4.0)
    return np.column_stack((mono * math.cos(ang), mono * math.sin(ang)))


def _add_clip(mix, clip_stereo, t_sec, gain=1.0):
    i0 = int(round(t_sec * SAMPLE_RATE))
    if i0 >= mix.shape[0] or clip_stereo.shape[0] == 0:
        return
    if i0 < 0:
        clip_stereo = clip_stereo[-i0:]
        i0 = 0
    n = min(clip_stereo.shape[0], mix.shape[0] - i0)
    if n > 0:
        mix[i0 : i0 + n] += clip_stereo[:n] * gain


def load_wav_mono_48k(path):
    """Read a 16-bit PCM WAV (mono or stereo, any sample rate) and resample to 48 kHz mono float64."""
    if not os.path.isfile(path):
        fail("missing required D5 game audio file: %s" % path)
    with wave.open(path, "rb") as wf:
        ch = wf.getnchannels()
        sw = wf.getsampwidth()
        sr = wf.getframerate()
        n = wf.getnframes()
        raw = wf.readframes(n)
    if sw != 2:
        fail("expected 16-bit WAV for %s, got sampwidth=%d" % (path, sw))
    pcm = np.frombuffer(raw, dtype=np.int16).astype(np.float64) / 32768.0
    if ch > 1:
        pcm = pcm.reshape(-1, ch).mean(axis=1)
    if sr == SAMPLE_RATE:
        return pcm
    out_len = max(1, int(round(len(pcm) * float(SAMPLE_RATE) / float(sr))))
    x_old = np.linspace(0.0, 1.0, len(pcm), endpoint=False)
    x_new = np.linspace(0.0, 1.0, out_len, endpoint=False)
    return np.interp(x_new, x_old, pcm)


def pitch_shift_mono(mono, ratio):
    if abs(ratio - 1.0) < 1e-4 or len(mono) < 4:
        return mono
    out_len = max(2, int(round(len(mono) / float(ratio))))
    x_old = np.linspace(0.0, 1.0, len(mono), endpoint=False)
    x_new = np.linspace(0.0, 1.0, out_len, endpoint=False)
    return np.interp(x_new, x_old, mono)


# ---------------------------------------------------------------- Cozy Instruments


def synth_marimba(midi_note, dur=0.42, vel=1.0):
    n = int(SAMPLE_RATE * dur)
    t = np.arange(n, dtype=np.float64) / SAMPLE_RATE
    f0 = midi_to_hz(midi_note)
    bar = (
        1.00 * np.sin(2 * math.pi * f0 * t) * np.exp(-t * 7.0)
        + 0.32 * np.sin(2 * math.pi * f0 * 3.98 * t) * np.exp(-t * 23.0)
        + 0.09 * np.sin(2 * math.pi * f0 * 9.20 * t) * np.exp(-t * 52.0)
    )
    strike = np.sin(2 * math.pi * (f0 * 2.4) * t) * np.exp(-t * 95.0) * 0.18
    env = np.minimum(1.0, t / 0.003)
    return (bar + strike) * env * vel * 0.22


def synth_epiano_chord(midi_notes, dur=1.1, vel=1.0):
    """Warm cozy Rhodes-style tine bell electric piano pad."""
    n = int(SAMPLE_RATE * dur)
    t = np.arange(n, dtype=np.float64) / SAMPLE_RATE
    out = np.zeros(n, dtype=np.float64)
    for mn in midi_notes:
        f0 = midi_to_hz(mn)
        mod = 0.65 * np.exp(-t * 9.0) * np.sin(2 * math.pi * f0 * 2.0 * t)
        voice = np.sin(2 * math.pi * f0 * t + mod) * np.exp(-t * 2.4)
        tine = 0.12 * np.sin(2 * math.pi * f0 * 6.0 * t) * np.exp(-t * 18.0)
        out += (voice + tine) / max(1, len(midi_notes))
    env = np.minimum(1.0, t / 0.008) * np.minimum(1.0, (dur - t) / 0.12)
    return out * env * vel * 0.24


def synth_upright_bass(midi_note, dur=0.64, vel=1.0):
    n = int(SAMPLE_RATE * dur)
    t = np.arange(n, dtype=np.float64) / SAMPLE_RATE
    f0 = midi_to_hz(midi_note)
    phase = 2 * math.pi * f0 * (t + 0.0013 * (1.0 - np.exp(-t * 34.0)))
    sig = (
        0.86 * np.sin(phase)
        + 0.45 * np.sin(2 * phase) * np.exp(-t * 4.2)
        + 0.22 * np.sin(3 * phase) * np.exp(-t * 7.8)
    )
    thump = np.sin(2 * math.pi * 110.0 * t) * np.exp(-t * 62.0) * 0.24
    env = np.minimum(1.0, t / 0.005) * np.exp(-t * 3.1)
    fade = np.minimum(1.0, np.linspace(1.0, 0.0, n) * 16.0)
    return (sig * env + thump) * fade * vel * 0.28


def synth_guitar_strum(midi_notes, dur=0.48, vel=1.0, upstroke=False):
    n = int(SAMPLE_RATE * dur)
    out = np.zeros(n, dtype=np.float64)
    rng = np.random.default_rng(sum(midi_notes) + (11 if upstroke else 5))
    notes = list(reversed(midi_notes)) if upstroke else list(midi_notes)
    for idx, mn in enumerate(notes):
        delay = max(12, int(round(SAMPLE_RATE / midi_to_hz(mn))))
        offset = int(idx * 0.011 * SAMPLE_RATE)
        if offset >= n:
            continue
        length = n - offset
        buf = rng.uniform(-1.0, 1.0, delay)
        buf = 0.5 * buf + 0.5 * np.roll(buf, 1)
        s = np.empty(length, dtype=np.float64)
        pos = 0
        while pos < length:
            chunk = min(delay, length - pos)
            s[pos : pos + chunk] = buf[:chunk]
            buf = 0.9935 * (0.54 * buf + 0.46 * np.roll(buf, 1))
            pos += chunk
        out[offset:] += s * (0.86 ** idx)
    fade = np.exp(-np.arange(n, dtype=np.float64) / SAMPLE_RATE * 4.8)
    return out * fade * vel * 0.11


def synth_warm_brass_chord(midi_notes, dur=1.6, vel=1.0, swell=True):
    n = int(SAMPLE_RATE * dur)
    t = np.arange(n, dtype=np.float64) / SAMPLE_RATE
    out = np.zeros(n, dtype=np.float64)
    for i, mn in enumerate(midi_notes):
        f0 = midi_to_hz(mn) * (1.0 + (i - 1.5) * 0.0012)
        vib = 1.0 + 0.0028 * np.sin(2 * math.pi * 5.0 * t)
        ph = 2 * math.pi * f0 * np.cumsum(vib) / SAMPLE_RATE
        voice = (
            0.66 * np.sin(ph)
            + 0.34 * np.sin(2 * ph)
            + 0.20 * np.sin(3 * ph)
            + 0.10 * np.sin(4 * ph)
        )
        out += voice / max(1, len(midi_notes))
    if swell:
        att = np.minimum(1.0, t / min(0.32, dur * 0.35))
        rel = np.minimum(1.0, (dur - t) / min(0.38, dur * 0.35))
        env = att * rel
    else:
        env = np.minimum(1.0, t / 0.016) * np.exp(-t * 1.7) * np.minimum(1.0, (dur - t) / 0.22)
    return out * env * vel * 0.24


def synth_drum(kind, rng):
    if kind == "kick":
        n = int(SAMPLE_RATE * 0.18)
        t = np.arange(n) / SAMPLE_RATE
        f = 52.0 + 82.0 * np.exp(-t * 36.0)
        return np.sin(2 * math.pi * np.cumsum(f) / SAMPLE_RATE) * np.exp(-t * 15.0) * 0.30
    if kind == "brush":
        n = int(SAMPLE_RATE * 0.15)
        t = np.arange(n) / SAMPLE_RATE
        noise = rng.normal(0.0, 1.0, n)
        noise = noise - 0.65 * np.roll(noise, 1)
        body = np.sin(2 * math.pi * 190.0 * t) * np.exp(-t * 32.0) * 0.22
        return noise * np.exp(-t * 21.0) * 0.13 + body
    if kind == "ride":
        n = int(SAMPLE_RATE * 0.24)
        t = np.arange(n) / SAMPLE_RATE
        bell = sum(np.sin(2 * math.pi * f * t) for f in (523.0, 789.0, 1143.0, 1682.0, 2410.0)) * 0.035
        hiss = (rng.normal(0.0, 1.0, n) - np.roll(rng.normal(0.0, 1.0, n), 1)) * 0.03
        return bell * np.exp(-t * 14.0) + hiss * np.exp(-t * 25.0)
    if kind == "tom":
        n = int(SAMPLE_RATE * 0.20)
        t = np.arange(n) / SAMPLE_RATE
        f = 112.0 + 54.0 * np.exp(-t * 28.0)
        return np.sin(2 * math.pi * np.cumsum(f) / SAMPLE_RATE) * np.exp(-t * 14.0) * 0.26
    return np.zeros(64)


# ---------------------------------------------------------------- World Foley Helpers


def foley_car_arrive(rng):
    n = int(SAMPLE_RATE * 1.1)
    t = np.arange(n) / SAMPLE_RATE
    rpm = 122.0 - 46.0 * np.clip(t / 0.9, 0.0, 1.0)
    ph = 2 * math.pi * np.cumsum(rpm) / SAMPLE_RATE
    eng = (0.6 * np.sin(ph) + 0.35 * np.sin(2 * ph)) * 0.11 * np.exp(-np.maximum(0.0, t - 0.8) * 6.0)
    chirp = np.sin(2 * math.pi * (1680.0 - 220.0 * t) * t) * np.exp(-((t - 0.78) ** 2) / (2 * 0.05 ** 2)) * 0.10
    return eng + chirp


def foley_roller(dur_s, rng):
    n = max(64, int(SAMPLE_RATE * dur_s))
    t = np.arange(n) / SAMPLE_RATE
    whirr = np.sin(2 * math.pi * 66.0 * t + 0.5 * np.sin(2 * math.pi * 16.0 * t)) * 0.04
    clicks = np.zeros(n)
    step = int(0.17 * SAMPLE_RATE)
    c_len = int(0.016 * SAMPLE_RATE)
    ct = np.arange(c_len) / SAMPLE_RATE
    click_wave = np.sin(2 * math.pi * 900.0 * ct) * np.exp(-ct * 220.0) * 0.085
    for p in range(1200, n - c_len * 3, step):
        clicks[p : p + c_len] += click_wave
    env = np.minimum(1.0, t / 0.05) * np.minimum(1.0, (dur_s - t) / 0.06)
    return (whirr + clicks) * env


def foley_scanner_beep():
    n = int(SAMPLE_RATE * 0.38)
    t = np.arange(n) / SAMPLE_RATE
    b1 = np.where((t >= 0.0) & (t < 0.10), np.sin(2 * math.pi * 880.0 * t) * np.exp(-t * 8.0), 0.0)
    b2 = np.where((t >= 0.12) & (t < 0.35), np.sin(2 * math.pi * 1318.5 * (t - 0.12)) * np.exp(-(t - 0.12) * 7.5), 0.0)
    return (b1 + b2) * 0.24


def foley_pa_chime():
    n = int(SAMPLE_RATE * 1.35)
    out = np.zeros(n)
    for idx, hz in enumerate((587.33, 739.99, 880.00)):
        p = int(idx * 0.27 * SAMPLE_RATE)
        t = np.arange(n - p) / SAMPLE_RATE
        tone = (
            np.sin(2 * math.pi * hz * t) * np.exp(-t * 3.3)
            + 0.28 * np.sin(2 * math.pi * hz * 2.0 * t) * np.exp(-t * 6.5)
        ) * np.minimum(1.0, t / 0.006)
        out[p:] += tone * 0.18
    return out


def foley_prop_plane(dur_s, rev_up, rng):
    n = max(64, int(SAMPLE_RATE * dur_s))
    t = np.arange(n) / SAMPLE_RATE
    if rev_up:
        ramp = np.clip(t / max(0.5, dur_s * 0.62), 0.0, 1.0)
        blade_hz = 78.0 + 64.0 * (ramp ** 1.1)
        whine_hz = 740.0 + 920.0 * ramp
        env = (0.35 + 0.65 * ramp) * np.minimum(1.0, (dur_s - t) / 0.45)
    else:
        blade_hz = np.full(n, 72.0)
        whine_hz = np.full(n, 680.0)
        env = np.minimum(1.0, t / 0.2) * np.minimum(1.0, (dur_s - t) / 0.25) * 0.32
    ph_b = 2 * math.pi * np.cumsum(blade_hz) / SAMPLE_RATE
    ph_w = 2 * math.pi * np.cumsum(whine_hz) / SAMPLE_RATE
    prop = 0.08 * np.sin(ph_b) + 0.045 * np.sin(2 * ph_b) + 0.022 * np.sin(ph_w)
    air = rng.normal(0.0, 1.0, n)
    wash = (0.45 * air + 0.35 * np.roll(air, 1) + 0.20 * np.roll(air, 2)) * (0.075 if rev_up else 0.03)
    return (prop + wash) * env


def foley_logo_slam(rng):
    n = int(SAMPLE_RATE * 0.80)
    t = np.arange(n) / SAMPLE_RATE
    sub_f = 48.0 + 95.0 * np.exp(-t * 25.0)
    sub = np.sin(2 * math.pi * np.cumsum(sub_f) / SAMPLE_RATE) * np.exp(-t * 7.8) * 0.34
    shimmer = sum(
        np.sin(2 * math.pi * hz * t) * np.exp(-t * (5.2 + i * 1.3))
        for i, hz in enumerate((1174.7, 1568.0, 1975.5, 2349.3))
    ) * 0.048
    return sub + shimmer


# ---------------------------------------------------------------- Ambience & Score


def layer_terminal_ambience(mix, amb_mono, t_start, t_end, gain=0.15):
    """Loop the 14 s D5 terminal_ambience.wav smoothly with 1.2 s crossfades."""
    if t_end <= t_start + 0.5 or len(amb_mono) < SAMPLE_RATE:
        return
    seg_len = int(round((t_end - t_start) * SAMPLE_RATE))
    bed = np.zeros(seg_len, dtype=np.float64)
    xfade = min(int(1.2 * SAMPLE_RATE), len(amb_mono) // 4)
    step = len(amb_mono) - xfade
    pos = 0
    chunk_i = 0
    while pos < seg_len:
        take = min(len(amb_mono), seg_len - pos)
        clip = amb_mono[:take].copy()
        if chunk_i > 0 and take > xfade:
            clip[:xfade] *= np.linspace(0.0, 1.0, xfade)
        if pos + take < seg_len and take >= len(amb_mono):
            clip[-xfade:] *= np.linspace(1.0, 0.0, xfade)
        bed[pos : pos + take] += clip
        pos += step
        chunk_i += 1
    fade_in = min(int(1.5 * SAMPLE_RATE), seg_len // 3)
    fade_out = min(int(1.8 * SAMPLE_RATE), seg_len // 3)
    if fade_in > 0:
        bed[:fade_in] *= np.linspace(0.0, 1.0, fade_in)
    if fade_out > 0:
        bed[-fade_out:] *= np.linspace(1.0, 0.0, fade_out)
    # Subtle Haas stereo widening (12 ms right delay) so mono ambience breathes wide
    d = int(0.012 * SAMPLE_RATE)
    right = np.concatenate((bed[d:], bed[:d])) if len(bed) > d else bed
    stereo = np.column_stack((bed * 0.95, right * 0.95))
    _add_clip(mix, stereo, t_start, gain=gain)


def build_cozy_score(mix, total_s, finale_start_s, logo_slam_s, rng):
    """Compose a 100 BPM beat-locked 5-chapter cozy airport tycoon underscore."""
    beat_s = 60.0 / BPM  # 0.600 s exact (18 frames @ 30 fps)

    f_build = [
        ([41, 45, 48, 45], [53, 57, 60, 64, 67], [65, 69, 72, 76]),  # Fmaj9
        ([46, 50, 53, 50], [58, 62, 65, 69, 72], [70, 74, 77, 81]),  # Bbmaj9
        ([43, 46, 50, 48], [55, 58, 62, 65, 69], [67, 70, 74, 77]),  # Gm9
        ([48, 52, 55, 46], [52, 58, 62, 65, 69], [64, 67, 72, 76]),  # C13
    ]
    f_story = [
        ([45, 48, 52, 50], [57, 60, 64, 67, 71], [69, 72, 76, 79]),  # Am9
        ([38, 41, 45, 43], [50, 53, 57, 60, 65], [62, 65, 69, 74]),  # Dm11
        ([43, 46, 50, 48], [55, 58, 62, 65, 69], [67, 70, 74, 79]),  # Gm9
        ([48, 50, 52, 55], [55, 58, 64, 67, 72], [67, 72, 76, 79]),  # C9sus4 -> C9
    ]
    g_finale = [
        ([43, 47, 50, 49], [55, 59, 62, 66, 69], [67, 71, 74, 78]),  # Gmaj9
        ([40, 43, 47, 46], [52, 55, 59, 62, 66], [64, 67, 71, 76]),  # Em9
        ([48, 52, 55, 54], [52, 55, 59, 64, 67], [64, 67, 71, 74]),  # Cmaj9
        ([50, 54, 57, 48], [54, 60, 64, 67, 71], [66, 69, 74, 78]),  # D13
    ]

    n_beats = max(4, int(math.floor(min(logo_slam_s, total_s - 0.5) / beat_s)))
    for b in range(n_beats):
        t = b * beat_s
        frac = t / max(1.0, total_s)
        bar_i = (b // 4) % 4
        b_in_bar = b % 4

        if t >= finale_start_s:
            prog = g_finale
            energy = 1.06
            mode = "finale"
        elif frac < 0.20:
            prog = f_build
            energy = 0.80
            mode = "build"
        elif frac < 0.38:
            prog = f_build
            energy = 0.90
            mode = "open"
        elif frac < 0.58:
            prog = f_story
            energy = 0.88
            mode = "follow"
        else:
            prog = f_build
            energy = 0.98
            mode = "bustle"

        bass_notes, gtr_chord, mar_notes = prog[bar_i]

        # 1. Upright walking bass on every beat
        bn = synth_upright_bass(bass_notes[b_in_bar], dur=beat_s * 1.06, vel=energy)
        _add_clip(mix, _pan(bn, -0.06), t)

        # 2. Warm Rhodes chord pad on beat 0 of every bar during follow/bustle/finale
        if b_in_bar == 0 and mode in ("follow", "bustle", "finale"):
            ep = synth_epiano_chord(gtr_chord[:4], dur=beat_s * 3.6, vel=energy * 0.72)
            _add_clip(mix, _pan(ep, 0.18), t)

        # 3. Acoustic jazz guitar comping (enters after initial shell build)
        if mode != "build":
            if b_in_bar in (1, 3) or (mode == "finale" and b_in_bar == 0):
                st = synth_guitar_strum(gtr_chord, dur=beat_s * 0.82, vel=energy * 0.92, upstroke=(b_in_bar == 3))
                _add_clip(mix, _pan(st, -0.34), t)
            if b_in_bar in (1, 3):
                st2 = synth_guitar_strum(gtr_chord[1:], dur=beat_s * 0.50, vel=energy * 0.68, upstroke=True)
                _add_clip(mix, _pan(st2, -0.28), t + beat_s * 0.66)

        # 4. Playful wooden marimba melody & syncopated off-beats
        m1 = mar_notes[(b_in_bar + bar_i) % len(mar_notes)]
        _add_clip(mix, _pan(synth_marimba(m1, vel=energy * 0.92), 0.30), t)
        if (b + bar_i) % 2 == 0 or mode in ("bustle", "finale"):
            oct_lift = 12 if (mode == "finale" and b_in_bar == 2) else 0
            m2 = mar_notes[(b_in_bar * 2 + 1) % len(mar_notes)] + oct_lift
            _add_clip(mix, _pan(synth_marimba(m2, vel=energy * 0.76), 0.36), t + beat_s * 0.50)

        # 5. Cozy jazz brush & ride kit
        if b_in_bar in (0, 2):
            _add_clip(mix, _pan(synth_drum("kick", rng), 0.0), t, gain=energy * 0.82)
        else:
            _add_clip(mix, _pan(synth_drum("brush", rng), 0.12), t, gain=energy * 0.90)
        if mode != "build" or b >= 12:
            _add_clip(mix, _pan(synth_drum("ride", rng), -0.20), t, gain=energy * 0.78)
            if b_in_bar in (1, 3):
                _add_clip(mix, _pan(synth_drum("ride", rng), -0.20), t + beat_s * 0.66, gain=energy * 0.58)

        # 6. Soaring warm horns on bar downbeats in the finale!
        if mode == "finale" and b_in_bar == 0:
            hrn = synth_warm_brass_chord(gtr_chord, dur=beat_s * 3.8, vel=0.82, swell=True)
            _add_clip(mix, _pan(hrn, 0.0), t)

    # Heroic Gmaj9(#11) Big-Band Button & Marimba Flourish on Option A Logo Reveal!
    if logo_slam_s < total_s - 0.4:
        rem = max(0.8, total_s - logo_slam_s - 0.15)
        for fi in range(6):
            ft = logo_slam_s - 0.66 + fi * 0.11
            if ft > 0.0:
                _add_clip(mix, _pan(synth_drum("tom" if fi >= 3 else "brush", rng), -0.2 + 0.08 * fi), ft, gain=0.85)
        btn = synth_warm_brass_chord([43, 55, 59, 62, 66, 69, 73, 74], dur=min(4.2, rem), vel=1.12, swell=False)
        _add_clip(mix, _pan(btn, 0.0), logo_slam_s)
        for i, mn in enumerate((67, 71, 74, 78, 81, 86)):
            _add_clip(mix, _pan(synth_marimba(mn, dur=0.75, vel=1.02), -0.28 + 0.11 * i), logo_slam_s + i * 0.055)
        _add_clip(mix, _pan(synth_guitar_strum([55, 59, 62, 66, 71, 74], dur=min(2.4, rem), vel=1.05), -0.18), logo_slam_s + 0.02)
        _add_clip(mix, _pan(synth_upright_bass(43, dur=min(2.6, rem), vel=1.10), 0.0), logo_slam_s)


def _add_stereo_reverb(mix, wet=0.12):
    out = mix.copy()
    rev = np.zeros_like(mix)
    for d_s, g, swap in ((0.029, 0.42, True), (0.047, 0.31, False), (0.073, 0.22, True), (0.113, 0.14, False)):
        d = int(d_s * SAMPLE_RATE)
        if d < mix.shape[0]:
            src = mix[:-d, ::-1] if swap else mix[:-d]
            rev[d:] += src * g
    return out + rev * wet


def verify_wav_windows(wav_path):
    with wave.open(wav_path, "rb") as wf:
        ch = wf.getnchannels()
        sr = wf.getframerate()
        n = wf.getnframes()
        raw = wf.readframes(n)
    if ch != 2 or sr != SAMPLE_RATE:
        fail("WAV format %dch %dHz != 2ch 48000Hz" % (ch, sr))
    arr = np.frombuffer(raw, dtype=np.int16).reshape(-1, 2).astype(np.float64) / 32768.0
    third = max(1, len(arr) // 3)
    stats = {"duration_s": round(len(arr) / float(sr), 3), "windows": {}}
    for wname, seg in (("early", arr[:third]), ("mid", arr[third : 2 * third]), ("end", arr[2 * third :])):
        pk = float(np.abs(seg).max())
        rms = float(np.sqrt(np.mean(seg ** 2)))
        print("PROBE audio_window %s peak=%.4f rms=%.4f" % (wname, pk, rms), flush=True)
        if pk < 0.05 or rms < 0.01:
            fail("audio window %s too quiet (peak=%.4f rms=%.4f)" % (wname, pk, rms))
        stats["windows"][wname] = {"peak": round(pk, 4), "rms": round(rms, 4)}
    return stats


def build_gameplay_audio(
    out_wav_path,
    cut_events,
    total_frames,
    game_audio_dir,
    ambience_range_frames=(451, 2070),
    finale_start_frame=1711,
    logo_slam_frame=2148,
):
    """Synthesize and mix the complete 48 kHz stereo gameplay trailer soundtrack WAV."""
    total_s = total_frames / float(FPS)
    n_samples = max(SAMPLE_RATE, int(round(total_s * SAMPLE_RATE)))
    mix = np.zeros((n_samples, 2), dtype=np.float64)
    rng = np.random.default_rng(20261119)

    # 1. Load real D5 game WAVs
    d5_amb = load_wav_mono_48k(os.path.join(game_audio_dir, "terminal_ambience.wav"))
    d5_place = load_wav_mono_48k(os.path.join(game_audio_dir, "build_place.wav"))
    d5_remove = load_wav_mono_48k(os.path.join(game_audio_dir, "build_remove.wav"))
    d5_cash = load_wav_mono_48k(os.path.join(game_audio_dir, "cash_chime.wav"))
    d5_click = load_wav_mono_48k(os.path.join(game_audio_dir, "ui_click.wav"))

    # 2. Compose 100 BPM cozy tycoon score
    finale_s = max(0.0, (finale_start_frame - 1) / float(FPS))
    slam_s = max(0.0, (logo_slam_frame - 1) / float(FPS))
    build_cozy_score(mix, total_s, finale_s, slam_s, rng)

    # 3. Layer looped D5 terminal_ambience.wav across live terminal shots
    amb_t0 = max(0.0, (ambience_range_frames[0] - 1) / float(FPS))
    amb_t1 = min(total_s, ambience_range_frames[1] / float(FPS))
    layer_terminal_ambience(mix, d5_amb, amb_t0, amb_t1, gain=0.16)

    # 4. Layer every frame-locked D5 SFX & world foley event (fail loud on unknown event!)
    place_idx = 0
    penta_ratios = (0.94, 1.00, 1.06, 1.12, 0.97, 1.03, 1.09)
    counts = {}
    for ev in cut_events:
        kind = ev["type"]
        counts[kind] = counts.get(kind, 0) + 1
        t0 = max(0.0, (int(ev["frame"]) - 1) / float(FPS))
        if kind == "build_place":
            ratio = penta_ratios[place_idx % len(penta_ratios)]
            pan_x = -0.24 + 0.48 * ((place_idx * 5) % 9) / 8.0
            place_idx += 1
            _add_clip(mix, _pan(pitch_shift_mono(d5_place, ratio), pan_x), t0, gain=0.72)
        elif kind == "build_remove":
            _add_clip(mix, _pan(d5_remove, -0.10), t0, gain=0.68)
        elif kind == "ui_click":
            _add_clip(mix, _pan(d5_click, 0.04), t0, gain=0.88)
        elif kind == "cash_chime":
            _add_clip(mix, _pan(d5_cash, 0.12), t0, gain=0.95)
        elif kind == "car_arrive":
            _add_clip(mix, _pan(foley_car_arrive(rng), -0.30), t0, gain=0.95)
        elif kind == "roller":
            dur_s = float(ev.get("dur", 90)) / float(FPS)
            _add_clip(mix, _pan(foley_roller(dur_s, rng), 0.14), t0, gain=0.90)
        elif kind == "scanner_beep":
            _add_clip(mix, _pan(foley_scanner_beep(), 0.06), t0, gain=1.05)
        elif kind == "pa_chime":
            _add_clip(mix, _pan(foley_pa_chime(), -0.16), t0, gain=1.05)
        elif kind == "prop_idle":
            dur_s = float(ev.get("dur", 150)) / float(FPS)
            _add_clip(mix, _pan(foley_prop_plane(dur_s, False, rng), -0.10), t0, gain=0.90)
        elif kind == "prop_rev":
            dur_s = float(ev.get("dur", 165)) / float(FPS)
            raw = foley_prop_plane(dur_s, True, rng)
            p_curve = np.linspace(0.24, -0.28, len(raw))
            ang = (p_curve + 1.0) * (math.pi / 4.0)
            _add_clip(mix, np.column_stack((raw * np.cos(ang), raw * np.sin(ang))), t0, gain=1.10)
        elif kind == "takeoff_whoosh":
            n_w = int(SAMPLE_RATE * 1.3)
            wt = np.arange(n_w) / SAMPLE_RATE
            wh = rng.normal(0, 1, n_w) * np.exp(-((wt - 0.55) ** 2) / (2 * 0.26 ** 2)) * 0.10
            _add_clip(mix, _pan(wh, -0.08), t0, gain=1.0)
        elif kind == "logo_slam":
            _add_clip(mix, _pan(foley_logo_slam(rng), 0.0), t0, gain=1.10)
        elif kind == "badge_pop":
            _add_clip(mix, _pan(pitch_shift_mono(d5_place, 1.18), 0.0), t0, gain=0.95)
        else:
            fail("unhandled gameplay audio event type: %r" % kind)

    print("PROBE audio_events counts=%s" % json.dumps(counts, sort_keys=True), flush=True)

    # 5. Cozy room glue + clean cosine tail fadeout + -1.2 dBFS peak normalization
    mix = _add_stereo_reverb(mix, wet=0.12)
    fade_n = min(int(1.25 * SAMPLE_RATE), n_samples // 4)
    if fade_n > 0:
        fade_curve = 0.5 * (1.0 + np.cos(np.linspace(0.0, math.pi, fade_n)))
        mix[-fade_n:] *= fade_curve[:, None]
    in_n = min(int(0.025 * SAMPLE_RATE), n_samples // 4)
    if in_n > 0:
        mix[:in_n] *= np.linspace(0.0, 1.0, in_n)[:, None]

    mix = np.tanh(mix * 1.12)
    peak = float(np.abs(mix).max())
    if peak < 1e-4:
        fail("gameplay audio mix is silent")
    mix = mix * (0.87 / peak)

    os.makedirs(os.path.dirname(out_wav_path), exist_ok=True)
    pcm16 = np.clip(mix * 32767.0, -32768, 32767).astype(np.int16)
    with wave.open(out_wav_path, "wb") as wf:
        wf.setnchannels(2)
        wf.setsampwidth(2)
        wf.setframerate(SAMPLE_RATE)
        wf.writeframes(pcm16.tobytes())

    stats = verify_wav_windows(out_wav_path)
    stats["event_counts"] = counts
    return stats


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    here = os.path.dirname(os.path.abspath(__file__))
    repo = os.path.abspath(os.path.join(here, "..", "..", ".."))
    default_out = os.path.join(repo, "tools", "blender", "out", "gameplay-trailer", "gameplay_audio.wav")
    default_audio = os.path.join(repo, "game", "assets", "audio")
    p = argparse.ArgumentParser()
    p.add_argument("--out-wav", default=default_out)
    p.add_argument("--events-json", default="")
    p.add_argument("--game-audio-dir", default=default_audio)
    p.add_argument("--total-frames", type=int, default=2286)
    args = p.parse_args(argv)

    events = []
    if args.events_json and os.path.isfile(args.events_json):
        data = json.load(open(args.events_json, "r", encoding="utf-8"))
        events = data.get("cut_events", [])
        args.total_frames = int(data.get("total_frames", args.total_frames))

    stats = build_gameplay_audio(
        os.path.abspath(args.out_wav),
        events,
        args.total_frames,
        os.path.abspath(args.game_audio_dir),
    )
    print("GAMEPLAY_AUDIO_OK " + json.dumps(stats), flush=True)


if __name__ == "__main__":
    main()
