"""Self-contained 48 kHz stereo comedy-jazz underscore + frame-accurate foley mixer
for the Gotta Make My Flight AAA 3D CG trailer (decision 888d509e).

Run standalone or imported by build_aaa_trailer.py:
  blender.exe --background --factory-startup --python tools/blender/trailer/build_audio.py < /dev/null
"""

import json
import math
import os
import sys
import wave

import numpy as np

SAMPLE_RATE = 48000
FPS = 30


def midi_to_hz(m):
    return 440.0 * (2.0 ** ((m - 69.0) / 12.0))


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


def _pan(mono, pan=0.0):
    """Constant-power stereo pan: pan in [-1.0 (left) .. +1.0 (right)]."""
    ang = (np.clip(pan, -1.0, 1.0) + 1.0) * (math.pi / 4.0)
    l_gain = math.cos(ang)
    r_gain = math.sin(ang)
    return np.column_stack((mono * l_gain, mono * r_gain))


# ---------------------------------------------------------------- Musical Instruments


def synth_marimba(midi_note, dur=0.38, vel=1.0):
    """Wooden bar modal synthesis (1 : 3.98 : 9.2 overtones + mallet wood transient)."""
    n = int(SAMPLE_RATE * dur)
    t = np.arange(n, dtype=np.float64) / SAMPLE_RATE
    f0 = midi_to_hz(midi_note)
    bar = (
        1.00 * np.sin(2 * math.pi * f0 * t) * np.exp(-t * 7.5)
        + 0.34 * np.sin(2 * math.pi * f0 * 3.98 * t) * np.exp(-t * 24.0)
        + 0.10 * np.sin(2 * math.pi * f0 * 9.20 * t) * np.exp(-t * 55.0)
    )
    # Soft felt-mallet strike click
    strike = np.sin(2 * math.pi * (f0 * 2.5) * t) * np.exp(-t * 95.0) * 0.22
    env = np.minimum(1.0, t / 0.003)
    return ((bar + strike) * env * vel * 0.24).astype(np.float64)


def synth_upright_bass(midi_note, dur=0.52, vel=1.0):
    """Warm plucked acoustic upright walking bass with woody finger thump."""
    n = int(SAMPLE_RATE * dur)
    t = np.arange(n, dtype=np.float64) / SAMPLE_RATE
    f0 = midi_to_hz(midi_note)
    # Slight pitch drop on pluck transient like a real gut/steel upright string
    phase = 2 * math.pi * f0 * (t + 0.0014 * (1.0 - np.exp(-t * 35.0)))
    sig = (
        0.85 * np.sin(phase)
        + 0.48 * np.sin(2 * phase) * np.exp(-t * 4.5)
        + 0.24 * np.sin(3 * phase) * np.exp(-t * 8.0)
        + 0.10 * np.sin(4 * phase) * np.exp(-t * 14.0)
    )
    thump = np.sin(2 * math.pi * 115.0 * t) * np.exp(-t * 65.0) * 0.28
    env = np.minimum(1.0, t / 0.005) * np.exp(-t * 3.6)
    fade = np.minimum(1.0, np.linspace(1.0, 0.0, n) * 18.0)
    return ((sig * env + thump) * fade * vel * 0.30).astype(np.float64)


def synth_guitar_strum(midi_notes, dur=0.42, vel=1.0, upstroke=False):
    """Karplus-Strong plucked acoustic jazz guitar chord strum."""
    n = int(SAMPLE_RATE * dur)
    out = np.zeros(n, dtype=np.float64)
    rng = np.random.default_rng(sum(midi_notes) + (7 if upstroke else 3))
    notes = list(reversed(midi_notes)) if upstroke else list(midi_notes)
    for idx, mn in enumerate(notes):
        delay = max(12, int(round(SAMPLE_RATE / midi_to_hz(mn))))
        offset = int(idx * 0.011 * SAMPLE_RATE)
        if offset >= n:
            continue
        length = n - offset
        buf = rng.uniform(-1.0, 1.0, delay)
        # Warm body lowpass on excitation
        buf = 0.5 * buf + 0.5 * np.roll(buf, 1)
        s = np.empty(length, dtype=np.float64)
        pos = 0
        damp = 0.9935
        while pos < length:
            chunk = min(delay, length - pos)
            s[pos : pos + chunk] = buf[:chunk]
            buf = damp * (0.54 * buf + 0.46 * np.roll(buf, 1))
            pos += chunk
        out[offset:] += s * (0.85 ** idx)
    fade = np.exp(-np.arange(n, dtype=np.float64) / SAMPLE_RATE * 5.2)
    return out * fade * vel * 0.12


def synth_warm_brass_chord(midi_notes, dur=1.2, vel=1.0, swell=True):
    """Warm cozy big-band horn/pad chord for takeoff soar & logo button."""
    n = int(SAMPLE_RATE * dur)
    t = np.arange(n, dtype=np.float64) / SAMPLE_RATE
    out = np.zeros(n, dtype=np.float64)
    for i, mn in enumerate(midi_notes):
        f0 = midi_to_hz(mn) * (1.0 + (i - 1.5) * 0.0012)
        vib = 1.0 + 0.003 * np.sin(2 * math.pi * 5.2 * t)
        ph = 2 * math.pi * f0 * np.cumsum(vib) / SAMPLE_RATE
        voice = (
            0.65 * np.sin(ph)
            + 0.36 * np.sin(2 * ph)
            + 0.22 * np.sin(3 * ph)
            + 0.11 * np.sin(4 * ph)
            + 0.06 * np.sin(5 * ph)
        )
        out += voice / max(1, len(midi_notes))
    if swell:
        att = np.minimum(1.0, t / min(0.28, dur * 0.35))
        rel = np.minimum(1.0, (dur - t) / min(0.35, dur * 0.35))
        env = att * rel
    else:
        env = np.minimum(1.0, t / 0.015) * np.exp(-t * 1.9) * np.minimum(1.0, (dur - t) / 0.18)
    return out * env * vel * 0.26


def synth_drum(kind, rng):
    """Brush jazz kit: kick, brush_snare, hat_closed, ride_ping, tom."""
    if kind == "kick":
        n = int(SAMPLE_RATE * 0.18)
        t = np.arange(n) / SAMPLE_RATE
        f = 54.0 + 85.0 * np.exp(-t * 38.0)
        ph = 2 * math.pi * np.cumsum(f) / SAMPLE_RATE
        return np.sin(ph) * np.exp(-t * 16.0) * 0.34
    if kind == "brush":
        n = int(SAMPLE_RATE * 0.15)
        t = np.arange(n) / SAMPLE_RATE
        noise = rng.normal(0.0, 1.0, n)
        # Band-shaped brush swish
        noise = noise - 0.65 * np.roll(noise, 1)
        body = np.sin(2 * math.pi * 195.0 * t) * np.exp(-t * 32.0) * 0.25
        return (noise * np.exp(-t * 22.0) * 0.14 + body)
    if kind == "ride":
        n = int(SAMPLE_RATE * 0.24)
        t = np.arange(n) / SAMPLE_RATE
        # Metallic jazz ride shimmer
        bell = sum(np.sin(2 * math.pi * f * t) for f in (523.0, 789.0, 1143.0, 1682.0, 2410.0)) * 0.04
        hiss = (rng.normal(0.0, 1.0, n) - np.roll(rng.normal(0.0, 1.0, n), 1)) * 0.035
        return (bell * np.exp(-t * 14.0) + hiss * np.exp(-t * 26.0))
    if kind == "tom":
        n = int(SAMPLE_RATE * 0.20)
        t = np.arange(n) / SAMPLE_RATE
        f = 115.0 + 55.0 * np.exp(-t * 28.0)
        ph = 2 * math.pi * np.cumsum(f) / SAMPLE_RATE
        return np.sin(ph) * np.exp(-t * 14.0) * 0.28
    return np.zeros(64)


# ---------------------------------------------------------------- Foley & Sound Effects


def foley_pop(pitch_idx):
    """Juicy Planet Coaster / Two Point elastic wood+bubble snap-pop!"""
    n = int(SAMPLE_RATE * 0.13)
    t = np.arange(n) / SAMPLE_RATE
    # Pentatonic scale degrees in F major so consecutive pops sound delightfully musical!
    penta = [65, 67, 69, 72, 74, 77, 79, 81, 84]
    base_hz = midi_to_hz(penta[pitch_idx % len(penta)])
    # Rapid upward bubble chirp + crisp woodblock knock
    f_curve = base_hz * (0.58 + 0.62 * (1.0 - np.exp(-t * 65.0)))
    ph = 2 * math.pi * np.cumsum(f_curve) / SAMPLE_RATE
    pop = np.sin(ph) * np.exp(-t * 28.0) * 0.36
    knock = np.sin(2 * math.pi * base_hz * 2.4 * t) * np.exp(-t * 90.0) * 0.20
    return pop + knock


def foley_footstep(rng, step_i):
    n = int(SAMPLE_RATE * 0.065)
    t = np.arange(n) / SAMPLE_RATE
    f = 155.0 if (step_i % 2 == 0) else 172.0
    sole = np.sin(2 * math.pi * f * t) * np.exp(-t * 58.0) * 0.16
    scuff = (rng.normal(0, 1, n) - 0.7 * np.roll(rng.normal(0, 1, n), 1)) * np.exp(-t * 75.0) * 0.07
    return sole + scuff


def foley_roller(dur_s, rng):
    n = int(SAMPLE_RATE * dur_s)
    t = np.arange(n) / SAMPLE_RATE
    whirr = np.sin(2 * math.pi * 68.0 * t + 0.6 * np.sin(2 * math.pi * 17.0 * t)) * 0.055
    # Tile-seam double-clicks every ~0.16s!
    clicks = np.zeros(n)
    step = int(0.165 * SAMPLE_RATE)
    c_len = int(0.018 * SAMPLE_RATE)
    ct = np.arange(c_len) / SAMPLE_RATE
    click_wave = np.sin(2 * math.pi * 920.0 * ct) * np.exp(-ct * 220.0) * 0.11
    for p in range(1200, n - c_len * 3, step):
        clicks[p : p + c_len] += click_wave
        clicks[p + int(0.025 * SAMPLE_RATE) : p + int(0.025 * SAMPLE_RATE) + c_len] += click_wave * 0.75
    rumble = rng.normal(0, 1, n) * 0.018
    rumble = 0.5 * rumble + 0.5 * np.roll(rumble, 2)
    env = np.minimum(1.0, t / 0.04) * np.minimum(1.0, (dur_s - t) / 0.05)
    return (whirr + clicks + rumble) * env


def foley_car_arrive_and_brake(rng):
    n = int(SAMPLE_RATE * 1.15)
    t = np.arange(n) / SAMPLE_RATE
    rpm = 128.0 - 52.0 * np.clip(t / 0.95, 0.0, 1.0)
    ph = 2 * math.pi * np.cumsum(rpm) / SAMPLE_RATE
    eng = (0.6 * np.sin(ph) + 0.35 * np.sin(2 * ph)) * 0.14 * np.exp(-np.maximum(0.0, t - 0.85) * 6.0)
    # Short rubber tire brake chirp around t=0.72..0.95s
    squeal_env = np.exp(-((t - 0.82) ** 2) / (2 * 0.055 ** 2))
    squeal = np.sin(2 * math.pi * (1780.0 - 240.0 * t) * t) * squeal_env * 0.16
    return eng + squeal


def foley_car_door(rng):
    n = int(SAMPLE_RATE * 0.24)
    t = np.arange(n) / SAMPLE_RATE
    latch = np.sin(2 * math.pi * 640.0 * t) * np.exp(-t * 95.0) * 0.18
    thud = np.sin(2 * math.pi * (95.0 + 40.0 * np.exp(-t * 35.0)) * t) * np.exp(-t * 22.0) * 0.32
    return latch + thud


def foley_board_flips(count=9):
    dur = 0.048 * count + 0.12
    n = int(SAMPLE_RATE * dur)
    out = np.zeros(n)
    cl_n = int(0.028 * SAMPLE_RATE)
    ct = np.arange(cl_n) / SAMPLE_RATE
    flap = (np.sin(2 * math.pi * 1450.0 * ct) + 0.6 * np.sin(2 * math.pi * 2380.0 * ct)) * np.exp(-ct * 180.0) * 0.24
    for i in range(count):
        p = int(i * 0.042 * SAMPLE_RATE)
        if p + cl_n < n:
            out[p : p + cl_n] += flap * (0.85 + 0.15 * (i / max(1, count - 1)))
    return out


def foley_stamp_ding():
    n = int(SAMPLE_RATE * 0.65)
    t = np.arange(n) / SAMPLE_RATE
    stamp = np.sin(2 * math.pi * 160.0 * t) * np.exp(-t * 55.0) * 0.25
    # Crisp hotel/counter bell ding (F6 + C7)
    bell = (
        0.75 * np.sin(2 * math.pi * 1396.9 * t) * np.exp(-t * 5.5)
        + 0.35 * np.sin(2 * math.pi * 2093.0 * t) * np.exp(-t * 9.0)
        + 0.18 * np.sin(2 * math.pi * 2793.8 * t) * np.exp(-t * 14.0)
    ) * 0.28
    return stamp + bell


def foley_scanner_beep():
    """Bright reassuring airport arch clearance double-beep (A5 -> E6)."""
    n = int(SAMPLE_RATE * 0.42)
    t = np.arange(n) / SAMPLE_RATE
    b1 = np.where((t >= 0.0) & (t < 0.11), np.sin(2 * math.pi * 880.0 * t) * np.exp(-t * 8.0), 0.0)
    b2 = np.where((t >= 0.13) & (t < 0.38), np.sin(2 * math.pi * 1318.5 * (t - 0.13)) * np.exp(-(t - 0.13) * 7.5), 0.0)
    harm = np.where((t >= 0.13) & (t < 0.38), 0.25 * np.sin(2 * math.pi * 2637.0 * (t - 0.13)) * np.exp(-(t - 0.13) * 12.0), 0.0)
    return (b1 + b2 + harm) * 0.30


def foley_pa_chime():
    """Warm classic 3-note airport terminal PA chime (D5 - F#5 - A5)."""
    n = int(SAMPLE_RATE * 1.45)
    out = np.zeros(n)
    for idx, hz in enumerate((587.33, 739.99, 880.00)):
        p = int(idx * 0.28 * SAMPLE_RATE)
        ln = n - p
        t = np.arange(ln) / SAMPLE_RATE
        tone = (
            np.sin(2 * math.pi * hz * t) * np.exp(-t * 3.2)
            + 0.30 * np.sin(2 * math.pi * hz * 2.0 * t) * np.exp(-t * 6.5)
            + 0.12 * np.sin(2 * math.pi * hz * 3.0 * t) * np.exp(-t * 11.0)
        ) * np.minimum(1.0, t / 0.006)
        out[p:] += tone * 0.22
    return out


def foley_jet_turbofan(dur_s, rev_up=True, rng=None):
    """High-bypass commercial turbofan spool whine (N1/N2 harmonics) + broadband jet roar
    matching the sleek fixed-wing Gotta Air tp_plane_05a jet!"""
    if rng is None:
        rng = np.random.default_rng(105)
    n = int(SAMPLE_RATE * dur_s)
    t = np.arange(n) / SAMPLE_RATE
    if rev_up:
        ramp = np.clip(t / max(0.5, dur_s * 0.58), 0.0, 1.0)
        n1_hz = 1120.0 + 1580.0 * (ramp ** 1.15)
        n2_hz = 2340.0 + 2650.0 * (ramp ** 1.15)
        low_hz = 95.0 + 85.0 * ramp
        gain_env = (0.38 + 0.62 * ramp) * np.minimum(1.0, (dur_s - t) / 0.35)
    else:
        n1_hz = np.full(n, 1080.0)
        n2_hz = np.full(n, 2240.0)
        low_hz = np.full(n, 92.0)
        gain_env = np.minimum(1.0, t / 0.15) * np.minimum(1.0, (dur_s - t) / 0.15) * 0.36

    ph1 = 2 * math.pi * np.cumsum(n1_hz) / SAMPLE_RATE
    ph2 = 2 * math.pi * np.cumsum(n2_hz) / SAMPLE_RATE
    ph_lo = 2 * math.pi * np.cumsum(low_hz) / SAMPLE_RATE
    spool = 0.045 * np.sin(ph1) + 0.024 * np.sin(ph2) + 0.075 * np.sin(ph_lo)

    # Smooth shaped broadband jet exhaust roar
    raw_noise = rng.normal(0.0, 1.0, n)
    roar = (
        0.38 * raw_noise
        + 0.32 * np.roll(raw_noise, 1)
        + 0.20 * np.roll(raw_noise, 2)
        + 0.10 * np.roll(raw_noise, 3)
    ) * (0.11 if rev_up else 0.05)
    return (spool + roar) * gain_env


def foley_logo_slam(rng):
    """Punchy cinematic sub-drop + elastic pop + bright sparkle shimmer!"""
    n = int(SAMPLE_RATE * 0.85)
    t = np.arange(n) / SAMPLE_RATE
    sub_f = 46.0 + 110.0 * np.exp(-t * 26.0)
    sub = np.sin(2 * math.pi * np.cumsum(sub_f) / SAMPLE_RATE) * np.exp(-t * 7.5) * 0.42
    pop = foley_pop(7)
    shimmer = sum(
        np.sin(2 * math.pi * hz * t) * np.exp(-t * (5.5 + i * 1.4))
        for i, hz in enumerate((1174.7, 1568.0, 1975.5, 2349.3, 3136.0))
    ) * 0.055
    whoosh = rng.normal(0, 1, n) * np.exp(-((t - 0.04) ** 2) / (2 * 0.035 ** 2)) * 0.15
    out = sub + shimmer + whoosh
    out[: len(pop)] += pop * 0.9
    return out


# ---------------------------------------------------------------- Score + Mix Builder


def _add_stereo_reverb(mix, wet=0.14):
    """Fast multi-tap Schroeder-style cozy room ambience."""
    out = mix.copy()
    taps = [
        (int(0.029 * SAMPLE_RATE), 0.42, True),
        (int(0.047 * SAMPLE_RATE), 0.31, False),
        (int(0.073 * SAMPLE_RATE), 0.22, True),
        (int(0.113 * SAMPLE_RATE), 0.14, False),
    ]
    rev = np.zeros_like(mix)
    for d, g, swap in taps:
        if d < mix.shape[0]:
            src = mix[:-d, ::-1] if swap else mix[:-d]
            rev[d:] += src * g
    return out + rev * wet


def build_score(mix, total_s, rng):
    """Compose a multi-section upbeat acoustic-jazz / marimba / walking-bass / guitar /
    brush-kit / big-band brass underscore tailored to the 6-shot story arc."""
    # Chord progressions: (bass_walk_4_notes, guitar_voicing, marimba_arpeggio)
    f_prog = [
        ([41, 45, 48, 47], [53, 57, 60, 64, 67], [65, 69, 72, 76]),  # Fmaj9
        ([38, 41, 45, 44], [50, 53, 57, 60, 64], [62, 65, 69, 74]),  # Dm9
        ([43, 46, 50, 49], [55, 58, 62, 65, 69], [67, 70, 74, 77]),  # Gm9
        ([48, 52, 55, 46], [52, 58, 62, 65, 69], [64, 67, 70, 76]),  # C13
    ]
    g_prog = [
        ([43, 47, 50, 49], [55, 59, 62, 66, 69], [67, 71, 74, 78]),  # Gmaj9 (Takeoff modulation!)
        ([40, 43, 47, 46], [52, 55, 59, 62, 66], [64, 67, 71, 76]),  # Em9
        ([48, 52, 55, 54], [52, 55, 59, 64, 67], [64, 67, 71, 74]),  # Cmaj9
        ([50, 54, 57, 48], [54, 60, 64, 67, 71], [66, 69, 72, 78]),  # D13
    ]

    # Section schedule: (t_start, t_end, bpm, prog, energy)
    sections = [
        (0.00, 5.50, 118.0, f_prog, 0.72),   # Shot 1: Curb arrival & board flip
        (5.50, 13.00, 130.0, f_prog, 0.92),  # Shot 2: Terminal snapping into place
        (13.00, 20.50, 136.0, f_prog, 0.96), # Shot 3: Security tray comedy
        (20.50, 27.00, 148.0, f_prog, 1.05), # Shot 4: Full-tilt concourse gate sprint!
        (27.00, 34.00, 152.0, g_prog, 1.12), # Shot 5: Key change to G Major + Takeoff soar!
    ]

    bar_counter = 0
    for s_start, s_end, bpm, prog, energy in sections:
        beat_s = 60.0 / bpm
        t = s_start
        beat_idx = 0
        while t < s_end - 0.05:
            bar_i = (bar_counter + beat_idx // 4) % len(prog)
            b_in_bar = beat_idx % 4
            bass_notes, gtr_chord, mar_notes = prog[bar_i]

            # 1. Upright Walking Bass on every quarter beat
            bn = synth_upright_bass(bass_notes[b_in_bar], dur=beat_s * 1.08, vel=energy)
            _add_clip(mix, _pan(bn, -0.08), t)

            # 2. Acoustic Jazz Guitar Freddie-Green / syncopated swing comping
            if b_in_bar in (1, 3) or (energy >= 0.95 and b_in_bar == 0):
                st = synth_guitar_strum(gtr_chord, dur=beat_s * 0.85, vel=energy * 0.95, upstroke=(b_in_bar == 3))
                _add_clip(mix, _pan(st, -0.35), t)
            if energy >= 0.90 and b_in_bar in (1, 3):
                # Swing off-beat upstroke ("uh" of beat!)
                st_off = synth_guitar_strum(gtr_chord[1:], dur=beat_s * 0.55, vel=energy * 0.72, upstroke=True)
                _add_clip(mix, _pan(st_off, -0.30), t + beat_s * 0.66)

            # 3. Playful Wooden Marimba syncopated melody & counter-arpeggio
            m1 = mar_notes[(b_in_bar * 2 + bar_i) % len(mar_notes)]
            _add_clip(mix, _pan(synth_marimba(m1, vel=energy * 0.95), 0.32), t)
            if (beat_idx + bar_i) % 2 == 0 or energy >= 1.0:
                m2 = mar_notes[(b_in_bar * 2 + 1) % len(mar_notes)] + (12 if energy > 1.0 and b_in_bar == 2 else 0)
                _add_clip(mix, _pan(synth_marimba(m2, vel=energy * 0.80), 0.38), t + beat_s * 0.66)

            # 4. Jazz Brush & Ride Kit ("ting - ting-a - ting - ting-a")
            if b_in_bar in (0, 2):
                _add_clip(mix, _pan(synth_drum("kick", rng), 0.0), t, gain=energy * 0.85)
            else:
                _add_clip(mix, _pan(synth_drum("brush", rng), 0.12), t, gain=energy)
            _add_clip(mix, _pan(synth_drum("ride", rng), -0.22), t, gain=energy * 0.85)
            if b_in_bar in (1, 3):
                _add_clip(mix, _pan(synth_drum("ride", rng), -0.22), t + beat_s * 0.66, gain=energy * 0.65)

            t += beat_s
            beat_idx += 1
        bar_counter += 2

    # Drum-fill buildup right before plane liftoff (t = 31.0 .. 31.8s) + Soaring Gmaj9 Brass Swell (31.6 .. 34.4s)!
    for fi in range(8):
        _add_clip(mix, _pan(synth_drum("tom" if fi >= 4 else "brush", rng), -0.25 + 0.07 * fi), 30.85 + fi * 0.11, gain=0.85 + 0.05 * fi)
    soar = synth_warm_brass_chord([55, 62, 66, 69, 74], dur=2.9, vel=1.05, swell=True)
    _add_clip(mix, _pan(soar, 0.0), 31.55)

    # Shot 6 (34.00 .. 39.50s): Heroic Gmaj9(#11) Big-Band Button on Logo Slam (f=1038) + Cozy Tail!
    slam_t = (1038 - 1) / float(FPS)
    btn = synth_warm_brass_chord([43, 55, 59, 62, 66, 69, 73, 74], dur=3.8, vel=1.18, swell=False)
    _add_clip(mix, _pan(btn, 0.0), slam_t)
    # Sparkling marimba flourish up Gmaj9 arpeggio right on logo reveal!
    for i, mn in enumerate((67, 71, 74, 78, 81, 86)):
        _add_clip(mix, _pan(synth_marimba(mn, dur=0.75, vel=1.05), -0.3 + 0.12 * i), slam_t + i * 0.055)
    _add_clip(mix, _pan(synth_guitar_strum([55, 59, 62, 66, 71, 74], dur=2.2, vel=1.1), -0.2), slam_t + 0.02)
    _add_clip(mix, _pan(synth_upright_bass(43, dur=2.4, vel=1.15), 0.0), slam_t)


def build_trailer_audio(out_wav_path, events, total_frames=1185):
    """Synthesize & mix the complete 48 kHz stereo soundtrack + frame-locked foley WAV."""
    total_s = total_frames / float(FPS)
    n_samples = int(round(total_s * SAMPLE_RATE))
    mix = np.zeros((n_samples, 2), dtype=np.float64)
    rng = np.random.default_rng(20261118)

    build_score(mix, total_s, rng)

    # Layer every frame-locked stereo foley event (fail loud on any unhandled event type per P5!)
    step_count = 0
    for ev in events:
        kind = ev["type"]
        t0 = max(0.0, (ev["frame"] - 1) / float(FPS))
        if kind == "car_arrive":
            _add_clip(mix, _pan(foley_car_arrive_and_brake(rng), -0.35), t0, gain=1.05)
        elif kind == "car_brake":
            pass  # Included seamlessly in car_arrive_and_brake
        elif kind == "car_door":
            _add_clip(mix, _pan(foley_car_door(rng), -0.15), t0, gain=1.10)
        elif kind == "board_flip":
            _add_clip(mix, _pan(foley_board_flips(ev.get("count", 9)), 0.05), t0, gain=1.15)
        elif kind == "startle_sting":
            st = synth_warm_brass_chord([59, 62, 65, 68], dur=0.45, vel=0.95, swell=False)
            _add_clip(mix, _pan(st, 0.0), t0, gain=0.90)
        elif kind == "pop":
            p_idx = int(ev.get("pitch", 0))
            pan_x = -0.35 + 0.70 * ((p_idx * 37) % 11) / 10.0
            _add_clip(mix, _pan(foley_pop(p_idx), pan_x), t0, gain=1.15)
        elif kind == "footstep":
            pan_x = -0.08 if (step_count % 2 == 0) else 0.08
            _add_clip(mix, _pan(foley_footstep(rng, step_count), pan_x), t0, gain=0.95)
            step_count += 1
        elif kind == "roller":
            dur_s = ev.get("dur", 30) / float(FPS)
            _add_clip(mix, _pan(foley_roller(dur_s, rng), 0.14), t0, gain=0.95)
        elif kind == "stamp_ding":
            _add_clip(mix, _pan(foley_stamp_ding(), 0.08), t0, gain=1.20)
        elif kind == "skid":
            n = int(SAMPLE_RATE * 0.18)
            st = np.arange(n) / SAMPLE_RATE
            sk = np.sin(2 * math.pi * (1520.0 - 380.0 * st) * st) * np.exp(-st * 18.0) * 0.22
            _add_clip(mix, _pan(sk, -0.1), t0)
        elif kind == "conveyor":
            dur_s = ev.get("dur", 60) / float(FPS)
            n = int(SAMPLE_RATE * dur_s)
            ct = np.arange(n) / SAMPLE_RATE
            wh = (np.sin(2 * math.pi * 142.0 * ct) + 0.4 * np.sin(2 * math.pi * 284.0 * ct)) * 0.055
            env = np.minimum(1.0, ct / 0.08) * np.minimum(1.0, (dur_s - ct) / 0.08)
            _add_clip(mix, _pan(wh * env, -0.28), t0)
        elif kind == "scanner_beep":
            _add_clip(mix, _pan(foley_scanner_beep(), 0.05), t0, gain=1.25)
        elif kind == "bag_snatch":
            _add_clip(mix, _pan(foley_pop(6), -0.15), t0, gain=0.95)
        elif kind == "pa_chime":
            _add_clip(mix, _pan(foley_pa_chime(), -0.18), t0, gain=1.15)
        elif kind == "door_whoosh":
            n = int(SAMPLE_RATE * 0.35)
            wt = np.arange(n) / SAMPLE_RATE
            wh = rng.normal(0, 1, n) * np.exp(-((wt - 0.16) ** 2) / (2 * 0.07 ** 2)) * 0.09
            _add_clip(mix, _pan(wh, 0.0), t0)
        elif kind in ("jet_idle", "prop_idle"):
            dur_s = ev.get("dur", 60) / float(FPS)
            _add_clip(mix, _pan(foley_jet_turbofan(dur_s, rev_up=False, rng=rng), -0.12), t0, gain=1.0)
        elif kind == "step_leap":
            _add_clip(mix, _pan(foley_pop(5), 0.18), t0, gain=0.85)
        elif kind == "door_seal":
            _add_clip(mix, _pan(foley_car_door(rng), -0.05), t0, gain=1.25)
        elif kind in ("jet_spool", "prop_rev"):
            dur_s = ev.get("dur", 120) / float(FPS)
            raw = foley_jet_turbofan(dur_s, rev_up=True, rng=rng)
            p_curve = np.linspace(-0.28, 0.32, len(raw))
            ang = (p_curve + 1.0) * (math.pi / 4.0)
            st_jet = np.column_stack((raw * np.cos(ang), raw * np.sin(ang)))
            _add_clip(mix, st_jet, t0, gain=1.25)
        elif kind == "takeoff_whoosh":
            n = int(SAMPLE_RATE * 1.4)
            wt = np.arange(n) / SAMPLE_RATE
            wh = (0.6 * rng.normal(0, 1, n) + 0.4 * np.roll(rng.normal(0, 1, n), 2)) * np.exp(-((wt - 0.55) ** 2) / (2 * 0.28 ** 2)) * 0.14
            _add_clip(mix, _pan(wh, -0.10), t0)
        elif kind == "sky_wind":
            dur_s = ev.get("dur", 165) / float(FPS)
            n = int(SAMPLE_RATE * dur_s)
            wt = np.arange(n) / SAMPLE_RATE
            air = rng.normal(0.0, 1.0, n)
            # Soft lowpass high-altitude sky breeze + distant cruising jet hum
            breeze = (0.45 * air + 0.35 * np.roll(air, 1) + 0.20 * np.roll(air, 2)) * 0.024
            hum = np.sin(2 * math.pi * 135.0 * wt) * 0.018
            env = np.minimum(1.0, wt / 0.25) * np.minimum(1.0, (dur_s - wt) / 0.8)
            _add_clip(mix, _pan((breeze + hum) * env, 0.0), t0, gain=1.0)
        elif kind == "logo_slam":
            _add_clip(mix, _pan(foley_logo_slam(rng), 0.0), t0, gain=1.20)
        elif kind == "badge_pop":
            _add_clip(mix, _pan(foley_pop(8), 0.0), t0, gain=1.05)
        else:
            raise ValueError(f"Unhandled audio event: {kind}")

    # Cozy stereo room glue + soft-knee master limiter + clean 1.2s tail fadeout
    mix = _add_stereo_reverb(mix, wet=0.14)
    fade_n = int(1.25 * SAMPLE_RATE)
    if fade_n < n_samples:
        fade_curve = 0.5 * (1.0 + np.cos(np.linspace(0.0, math.pi, fade_n)))
        mix[-fade_n:] *= fade_curve[:, None]
    # Gentle 25ms fade-in to eliminate any DC click at frame 1
    in_n = int(0.025 * SAMPLE_RATE)
    mix[:in_n] *= np.linspace(0.0, 1.0, in_n)[:, None]

    # Soft tanh saturation + normalize peak to -1.2 dBFS (0.87)
    mix = np.tanh(mix * 1.15)
    peak = float(np.abs(mix).max())
    if peak < 1e-4:
        raise RuntimeError("PROBE_INVALID audio mix is silent")
    mix = mix * (0.87 / peak)

    os.makedirs(os.path.dirname(out_wav_path), exist_ok=True)
    pcm16 = np.clip(mix * 32767.0, -32768, 32767).astype(np.int16)
    with wave.open(out_wav_path, "wb") as wf:
        wf.setnchannels(2)
        wf.setsampwidth(2)
        wf.setframerate(SAMPLE_RATE)
        wf.writeframes(pcm16.tobytes())

    metrics = verify_wav_windows(out_wav_path)
    return metrics


def verify_wav_windows(wav_path):
    """Read back WAV and verify non-zero peak & RMS across early, mid, and end windows."""
    with wave.open(wav_path, "rb") as wf:
        ch = wf.getnchannels()
        sr = wf.getframerate()
        n = wf.getnframes()
        raw = wf.readframes(n)
    if ch != 2 or sr != SAMPLE_RATE:
        raise RuntimeError("PROBE_INVALID WAV format %dch %dHz" % (ch, sr))
    arr = np.frombuffer(raw, dtype=np.int16).reshape(-1, 2).astype(np.float64) / 32768.0
    third = len(arr) // 3
    windows = {
        "early": arr[:third],
        "mid": arr[third : 2 * third],
        "end": arr[2 * third :],
    }
    stats = {"duration_s": round(len(arr) / float(sr), 3), "windows": {}}
    for wname, seg in windows.items():
        pk = float(np.abs(seg).max())
        rms = float(np.sqrt(np.mean(seg ** 2)))
        print("PROBE audio_window %s peak=%.4f rms=%.4f" % (wname, pk, rms), flush=True)
        if pk < 0.05 or rms < 0.01:
            raise RuntimeError("PROBE_INVALID audio window %s too quiet (peak=%.4f rms=%.4f)" % (wname, pk, rms))
        stats["windows"][wname] = {"peak": round(pk, 4), "rms": round(rms, 4)}
    return stats


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    out_root = os.path.abspath(os.path.join(here, "..", "..", "..", "tools", "blender", "out", "aaa-trailer"))
    ev_path = os.path.join(out_root, "shot_events.json")
    events = json.load(open(ev_path, "r", encoding="utf-8"))["events"] if os.path.isfile(ev_path) else []
    out_wav = os.path.join(out_root, "audio", "trailer_mix.wav")
    res = build_trailer_audio(out_wav, events, total_frames=1185)
    print("AUDIO_DONE", json.dumps(res), flush=True)
