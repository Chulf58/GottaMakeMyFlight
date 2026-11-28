#!/usr/bin/env python3
"""Deterministic procedural audio synthesizer for the D5 demo audio floor and PA cues.

Generates compact, click-free 16-bit PCM WAV SFX cues, a seamless 44100 Hz
stereo terminal ambience bed, and a 5-track 44100 Hz stereo Ogg Vorbis cozy
soundtrack playlist under game/assets/audio/:
  - terminal_ambience_bed.ogg (24.0 s seamless terminal room-air + murmur bed, 44100 Hz stereo)
  - terminal_lounge.ogg       (80.0 s, C major / A minor @ 96 BPM: Rhodes & vibraphone lounge)
  - music_morning_bossa.ogg   (88.9 s, F major @ 108 BPM: nylon guitar, flute & brushed shaker)
  - music_sunny_marimba.ogg   (88.4 s, G major @ 114 BPM: marimba, kalimba & woodblock)
  - music_breezy_stroll.ogg   (90.0 s, D major @ 88 BPM 3/4 waltz: celesta & soft clarinet)
  - music_sunset_acoustic.ogg (93.7 s, Eb/Bb major @ 82 BPM: evening Rhodes, acoustic & warm pad)
  - terminal_ambience.wav     (14.0 s seamless loop, 22050 Hz mono; kept for trailer mixer)
  - ui_click.wav          (45 ms soft wooden/cream tap, 44100 Hz mono)
  - build_place.wav       (90 ms cozy tactile placement pop, 44100 Hz mono)
  - build_remove.wav      (80 ms soft muted brush/pop, 44100 Hz mono)
  - build_refuse.wav      (115 ms gentle low marimba double-thud, 44100 Hz mono)
  - cash_chime.wav        (185 ms warm two-note bell chime, 44100 Hz mono)
  - security_beep.wav     (70 ms soft dual-tone marimba/bell pip, 44100 Hz mono)
  - pa_chime.wav          (520 ms warm 3-note airport bell chime, 44100 Hz mono)
  - pa_final_call.wav     (600 ms warm 4-note airport bell chime, 44100 Hz mono)
  - close_call_save.wav   (220 ms bright relief flourish glockenspiel, 44100 Hz mono)
  - joke_spill.wav        (210 ms soft bubbly splat + woody slide, 44100 Hz mono)
  - joke_fault.wav        (340 ms warm low marimba power-down, 44100 Hz mono)
  - joke_queue_horn.wav   (260 ms gentle detuned two-note cozy horn, 44100 Hz mono)
  - star_up.wav           (300 ms warm ascending chime C5-E5-G5-C6, 44100 Hz mono)
  - phone_ring.wav        (1920 ms two-ring double-trill desk/cellphone ring, 44100 Hz mono)
  - checkin_stamp.wav     (75 ms soft tactile desk stamp/thump, 44100 Hz mono)
  - security_alarm.wav    (210 ms short double-beep security alert, 44100 Hz mono)
  - security_clear.wav    (135 ms gentle positive security clear chime, 44100 Hz mono)
  - gate_chirp.wav        (85 ms crisp boarding-pass scanner chirp, 44100 Hz mono)
  - cafe_clink.wav        (125 ms soft ceramic cup/saucer clink, 44100 Hz mono)
  - staff_mumble.wav      (145 ms warm cozy two-syllable staff chat mumble, 44100 Hz mono)
  - staff_sip.wav         (140 ms soft ceramic mug tap and warm coffee sip, 44100 Hz mono)
  - staff_cheer.wav       (210 ms warm celebratory mini-cheer chime, 44100 Hz mono)
  - staff_wipe.wav        (155 ms soft two-stroke counter cloth wipe, 44100 Hz mono)
  - staff_yawn.wav        (280 ms gentle descending tired yawn-sigh hum, 44100 Hz mono)
"""

from __future__ import annotations

import math
import os
import random
import shutil
import struct
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

TAU = 2.0 * math.pi
REPO_ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = REPO_ROOT / "game" / "assets" / "audio"


def _clamp_pcm16(samples: list[float]) -> bytes:
    packed = bytearray(len(samples) * 2)
    for idx, val in enumerate(samples):
        clamped = max(-0.98, min(0.98, val))
        pcm = int(round(clamped * 32767.0))
        struct.pack_into("<h", packed, idx * 2, pcm)
    return bytes(packed)


def _write_wav(path: Path, sample_rate: int, samples: list[float]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    pcm_bytes = _clamp_pcm16(samples)
    with wave.open(str(path), "wb") as wav_file:
        wav_file.setnchannels(1)
        wav_file.setsampwidth(2)
        wav_file.setframerate(sample_rate)
        wav_file.writeframes(pcm_bytes)


def _write_stereo_wav(
    path: Path, sample_rate: int, left: list[float], right: list[float]
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    n = len(left)
    packed = bytearray(n * 4)
    for idx in range(n):
        lv = max(-0.98, min(0.98, left[idx]))
        rv = max(-0.98, min(0.98, right[idx]))
        struct.pack_into("<hh", packed, idx * 4, int(round(lv * 32767.0)), int(round(rv * 32767.0)))
    with wave.open(str(path), "wb") as wav_file:
        wav_file.setnchannels(2)
        wav_file.setsampwidth(2)
        wav_file.setframerate(sample_rate)
        wav_file.writeframes(bytes(packed))


def _one_pole_lowpass(samples: list[float], cutoff_hz: float, sr: int) -> list[float]:
    rc = 1.0 / (TAU * cutoff_hz)
    dt = 1.0 / sr
    alpha = dt / (rc + dt)
    out = [0.0] * len(samples)
    state = samples[0] if samples else 0.0
    for i, x in enumerate(samples):
        state = state + alpha * (x - state)
        out[i] = state
    return out


def _one_pole_highpass(samples: list[float], cutoff_hz: float, sr: int) -> list[float]:
    low = _one_pole_lowpass(samples, cutoff_hz, sr)
    return [x - lp for x, lp in zip(samples, low)]


def build_terminal_ambience(sr: int = 22050) -> tuple[int, list[float]]:
    """14.0 s seamless warm room air + distant concourse murmur + soft chord bed."""
    loop_s = 14.0
    xfade_s = 2.0
    total_s = loop_s + xfade_s
    loop_n = int(loop_s * sr)
    xfade_n = int(xfade_s * sr)
    total_n = loop_n + xfade_n

    rng = random.Random(20270614)
    white = [rng.uniform(-1.0, 1.0) for _ in range(total_n)]

    # Warm room air bed: band-limited soft air (65 Hz .. 340 Hz)
    air = _one_pole_lowpass(white, 340.0, sr)
    air = _one_pole_lowpass(air, 380.0, sr)
    air = _one_pole_highpass(air, 65.0, sr)

    # Distant concourse murmur texture: filtered mid band modulated by slow waves
    murmur_src = [rng.uniform(-1.0, 1.0) for _ in range(total_n)]
    murmur = _one_pole_lowpass(murmur_src, 780.0, sr)
    murmur = _one_pole_lowpass(murmur, 680.0, sr)
    murmur = _one_pole_highpass(murmur, 240.0, sr)

    # Exact integer-cycle warm Fmaj9 pad frequencies over loop_s so phase matches
    raw_freqs = [174.61, 220.0, 261.63, 329.63, 392.00]
    pad_amps = [0.015, 0.011, 0.012, 0.009, 0.007]
    snapped_freqs = [round(f * loop_s) / loop_s for f in raw_freqs]

    buf = [0.0] * total_n
    for i in range(total_n):
        t = i / sr
        # Slow breathing envelopes (integer cycles over 14.0 s)
        murmur_env = 0.55 + 0.25 * math.sin(TAU * (2.0 / loop_s) * t)
        murmur_env += 0.20 * math.sin(TAU * (3.0 / loop_s) * t + 1.1)
        air_env = 0.88 + 0.12 * math.sin(TAU * (1.0 / loop_s) * t + 0.4)

        pad = 0.0
        for idx, freq in enumerate(snapped_freqs):
            lfo = 0.82 + 0.18 * math.sin(TAU * ((idx + 1) / loop_s) * t + idx * 0.9)
            pad += pad_amps[idx] * lfo * math.sin(TAU * freq * t)

        buf[i] = 0.14 * air_env * air[i] + 0.065 * murmur_env * murmur[i] + pad

    # Seamless raised-cosine crossfade of tail [loop_n .. loop_n+xfade_n) into head [0 .. xfade_n).
    # At i=0: w=0 -> loop[0] = buf[loop_n], adjacent to loop[loop_n-1] = buf[loop_n-1]!
    # At i=xfade_n-1: w~1 -> loop[xfade_n-1] ~ buf[xfade_n-1], adjacent to loop[xfade_n]!
    loop = [0.0] * loop_n
    for i in range(xfade_n):
        w = 0.5 - 0.5 * math.cos( math.pi * i / xfade_n )
        loop[i] = buf[i] * w + buf[loop_n + i] * (1.0 - w)
    for i in range(xfade_n, loop_n):
        loop[i] = buf[i]

    return sr, loop


def _midi_to_hz(midi: float) -> float:
    return 440.0 * (2.0 ** ((midi - 69.0) / 12.0))


def _pan_gains(pan: float) -> tuple[float, float]:
    clamped = max(-1.0, min(1.0, pan))
    ang = (clamped + 1.0) * (math.pi * 0.25)
    return math.cos(ang), math.sin(ang)


def _add_epiano_note(
    left: list[float],
    right: list[float],
    sr: int,
    start_s: float,
    midi: float,
    dur_s: float,
    vel: float,
    pan: float = -0.10,
) -> None:
    start_idx = int(round(start_s * sr))
    n = int(round(dur_s * sr))
    if n <= 0 or start_idx >= len(left):
        return
    freq = _midi_to_hz(midi)
    dphase = TAU * freq / sr
    dt = 1.0 / sr
    lg, rg = _pan_gains(pan)
    att_s = 0.010
    rel_s = 0.065
    inv_att = 1.0 / att_s
    inv_rel = 1.0 / rel_s
    decay_2 = math.exp(-dt / 0.55)
    decay_3 = math.exp(-dt / 0.25)
    decay_4 = math.exp(-dt / 0.055)
    decay_env = math.exp(-dt / 1.45)
    sin = math.sin
    trem_step = TAU * 3.1 * dt
    e2 = 0.26
    e3 = 0.06
    e4 = 0.09
    env_decay = vel * 0.14
    phase = 0.0
    trem_ph = pan * 1.1
    end_idx = min(len(left), start_idx + n)
    for idx in range(start_idx, end_idx):
        i = idx - start_idx
        t = i * dt
        att = sin(0.5 * math.pi * (t * inv_att)) if t < att_s else 1.0
        rel = (
            0.5 + 0.5 * math.cos(math.pi * (t - (dur_s - rel_s)) * inv_rel)
            if t > dur_s - rel_s
            else 1.0
        )
        trem = 0.92 + 0.08 * sin(trem_ph)
        tone = (
            sin(phase)
            + e2 * sin(2.0 * phase)
            + e3 * sin(3.0 * phase)
            + e4 * sin(4.0 * phase)
        )
        amp = env_decay * att * rel * trem
        val = tone * amp
        left[idx] += val * lg
        right[idx] += val * rg
        phase += dphase
        trem_ph += trem_step
        e2 *= decay_2
        e3 *= decay_3
        e4 *= decay_4
        env_decay *= decay_env


def _add_marimba_note(
    left: list[float],
    right: list[float],
    sr: int,
    start_s: float,
    midi: float,
    dur_s: float,
    vel: float,
    pan: float = 0.12,
) -> None:
    start_idx = int(round(start_s * sr))
    n = int(round(dur_s * sr))
    if n <= 0 or start_idx >= len(left):
        return
    freq = _midi_to_hz(midi)
    dphase = TAU * freq / sr
    dt = 1.0 / sr
    lg, rg = _pan_gains(pan)
    att_s = 0.0025
    rel_s = 0.035
    inv_att = 1.0 / att_s
    inv_rel = 1.0 / rel_s
    decay_4 = math.exp(-dt / 0.042)
    decay_m = math.exp(-dt / 0.012)
    decay_env = math.exp(-dt / 0.27)
    sin = math.sin
    e4 = 0.24
    em = 0.07
    env_decay = vel * 0.17
    phase = 0.0
    end_idx = min(len(left), start_idx + n)
    for idx in range(start_idx, end_idx):
        i = idx - start_idx
        t = i * dt
        att = sin(0.5 * math.pi * (t * inv_att)) if t < att_s else 1.0
        rel = (
            0.5 + 0.5 * math.cos(math.pi * (t - (dur_s - rel_s)) * inv_rel)
            if t > dur_s - rel_s
            else 1.0
        )
        tone = sin(phase) + e4 * sin(3.99 * phase) + em * sin(2.4 * phase)
        val = tone * env_decay * att * rel
        left[idx] += val * lg
        right[idx] += val * rg
        phase += dphase
        e4 *= decay_4
        em *= decay_m
        env_decay *= decay_env


def _add_upright_bass_note(
    left: list[float],
    right: list[float],
    sr: int,
    start_s: float,
    midi: float,
    dur_s: float,
    vel: float,
) -> None:
    start_idx = int(round(start_s * sr))
    n = int(round(dur_s * sr))
    if n <= 0 or start_idx >= len(left):
        return
    freq = _midi_to_hz(midi)
    dt = 1.0 / sr
    att_s = 0.008
    rel_s = 0.040
    inv_att = 1.0 / att_s
    inv_rel = 1.0 / rel_s
    decay_2 = math.exp(-dt / 0.24)
    decay_3 = math.exp(-dt / 0.09)
    decay_env = math.exp(-dt / 0.68)
    decay_pitch = math.exp(-dt / 0.016)
    sin = math.sin
    e2 = 0.28
    e3 = 0.06
    p_lift = 0.015
    env_decay = vel * 0.22
    phase = 0.0
    base_dphase = TAU * freq * dt
    end_idx = min(len(left), start_idx + n)
    for idx in range(start_idx, end_idx):
        i = idx - start_idx
        t = i * dt
        att = sin(0.5 * math.pi * (t * inv_att)) if t < att_s else 1.0
        rel = (
            0.5 + 0.5 * math.cos(math.pi * (t - (dur_s - rel_s)) * inv_rel)
            if t > dur_s - rel_s
            else 1.0
        )
        tone = sin(phase) + e2 * sin(2.0 * phase) + e3 * sin(3.0 * phase)
        val = tone * env_decay * att * rel * 0.7071
        left[idx] += val
        right[idx] += val
        phase += base_dphase * (1.0 + p_lift)
        p_lift *= decay_pitch
        e2 *= decay_2
        e3 *= decay_3
        env_decay *= decay_env


def _add_vibraphone_note(
    left: list[float],
    right: list[float],
    sr: int,
    start_s: float,
    midi: float,
    dur_s: float,
    vel: float,
    pan: float = 0.14,
) -> None:
    start_idx = int(round(start_s * sr))
    n = int(round(dur_s * sr))
    if n <= 0 or start_idx >= len(left):
        return
    freq = _midi_to_hz(midi)
    dphase = TAU * freq / sr
    dt = 1.0 / sr
    lg, rg = _pan_gains(pan)
    att_s = 0.005
    rel_s = 0.055
    inv_att = 1.0 / att_s
    inv_rel = 1.0 / rel_s
    decay_4 = math.exp(-dt / 0.055)
    decay_env = math.exp(-dt / 1.15)
    trem_step = TAU * 5.2 * dt
    sin = math.sin
    e4 = 0.12
    env_decay = vel * 0.14
    phase = 0.0
    trem_ph = pan * 0.8
    end_idx = min(len(left), start_idx + n)
    for idx in range(start_idx, end_idx):
        t = (idx - start_idx) * dt
        att = sin(0.5 * math.pi * (t * inv_att)) if t < att_s else 1.0
        rel = (
            0.5 + 0.5 * math.cos(math.pi * (t - (dur_s - rel_s)) * inv_rel)
            if t > dur_s - rel_s
            else 1.0
        )
        trem = 0.86 + 0.14 * sin(trem_ph)
        tone = sin(phase) + e4 * sin(3.98 * phase)
        val = tone * env_decay * att * rel * trem
        left[idx] += val * lg
        right[idx] += val * rg
        phase += dphase
        trem_ph += trem_step
        e4 *= decay_4
        env_decay *= decay_env


def _add_nylon_guitar_note(
    left: list[float],
    right: list[float],
    sr: int,
    start_s: float,
    midi: float,
    dur_s: float,
    vel: float,
    pan: float = -0.18,
) -> None:
    start_idx = int(round(start_s * sr))
    n = int(round(dur_s * sr))
    if n <= 0 or start_idx >= len(left):
        return
    freq = _midi_to_hz(midi)
    dphase = TAU * freq / sr
    dt = 1.0 / sr
    lg, rg = _pan_gains(pan)
    att_s = 0.004
    rel_s = 0.045
    inv_att = 1.0 / att_s
    inv_rel = 1.0 / rel_s
    decay_2 = math.exp(-dt / 0.34)
    decay_3 = math.exp(-dt / 0.14)
    decay_4 = math.exp(-dt / 0.055)
    decay_env = math.exp(-dt / 0.85)
    sin = math.sin
    e2 = 0.42
    e3 = 0.18
    e4 = 0.09
    env_decay = vel * 0.14
    phase = 0.0
    end_idx = min(len(left), start_idx + n)
    for idx in range(start_idx, end_idx):
        t = (idx - start_idx) * dt
        att = sin(0.5 * math.pi * (t * inv_att)) if t < att_s else 1.0
        rel = (
            0.5 + 0.5 * math.cos(math.pi * (t - (dur_s - rel_s)) * inv_rel)
            if t > dur_s - rel_s
            else 1.0
        )
        tone = sin(phase) + e2 * sin(2.0 * phase) + e3 * sin(3.0 * phase) + e4 * sin(4.0 * phase)
        val = tone * env_decay * att * rel
        left[idx] += val * lg
        right[idx] += val * rg
        phase += dphase
        e2 *= decay_2
        e3 *= decay_3
        e4 *= decay_4
        env_decay *= decay_env


def _add_soft_flute_note(
    left: list[float],
    right: list[float],
    sr: int,
    start_s: float,
    midi: float,
    dur_s: float,
    vel: float,
    pan: float = 0.16,
) -> None:
    start_idx = int(round(start_s * sr))
    n = int(round(dur_s * sr))
    if n <= 0 or start_idx >= len(left):
        return
    freq = _midi_to_hz(midi)
    base_dphase = TAU * freq / sr
    dt = 1.0 / sr
    lg, rg = _pan_gains(pan)
    att_s = min(0.065, dur_s * 0.25)
    rel_s = min(0.090, dur_s * 0.30)
    inv_att = 1.0 / max(att_s, 1e-4)
    inv_rel = 1.0 / max(rel_s, 1e-4)
    vib_step = TAU * 5.0 * dt
    sin = math.sin
    phase = 0.0
    vib_ph = 0.0
    rng = random.Random(int(round(start_s * 1000)) + int(midi))
    breath_state = 0.0
    end_idx = min(len(left), start_idx + n)
    for idx in range(start_idx, end_idx):
        t = (idx - start_idx) * dt
        att = sin(0.5 * math.pi * (t * inv_att)) if t < att_s else 1.0
        rel = (
            0.5 + 0.5 * math.cos(math.pi * (t - (dur_s - rel_s)) * inv_rel)
            if t > dur_s - rel_s
            else 1.0
        )
        vib_depth = 0.0035 * min(1.0, max(0.0, (t - 0.09) / 0.18))
        vib = 1.0 + vib_depth * sin(vib_ph)
        breath_state = breath_state * 0.86 + rng.uniform(-1.0, 1.0) * 0.14
        tone = sin(phase) + 0.18 * sin(2.0 * phase) + 0.03 * breath_state * math.exp(-t / 0.08)
        val = tone * (vel * 0.12) * att * rel
        left[idx] += val * lg
        right[idx] += val * rg
        phase += base_dphase * vib
        vib_ph += vib_step


def _add_kalimba_note(
    left: list[float],
    right: list[float],
    sr: int,
    start_s: float,
    midi: float,
    dur_s: float,
    vel: float,
    pan: float = -0.22,
) -> None:
    start_idx = int(round(start_s * sr))
    n = int(round(dur_s * sr))
    if n <= 0 or start_idx >= len(left):
        return
    freq = _midi_to_hz(midi)
    dphase = TAU * freq / sr
    dt = 1.0 / sr
    lg, rg = _pan_gains(pan)
    att_s = 0.0020
    rel_s = 0.030
    inv_att = 1.0 / att_s
    inv_rel = 1.0 / rel_s
    decay_tine = math.exp(-dt / 0.018)
    decay_env = math.exp(-dt / 0.36)
    sin = math.sin
    e_tine = 0.32
    env_decay = vel * 0.13
    phase = 0.0
    end_idx = min(len(left), start_idx + n)
    for idx in range(start_idx, end_idx):
        t = (idx - start_idx) * dt
        att = sin(0.5 * math.pi * (t * inv_att)) if t < att_s else 1.0
        rel = (
            0.5 + 0.5 * math.cos(math.pi * (t - (dur_s - rel_s)) * inv_rel)
            if t > dur_s - rel_s
            else 1.0
        )
        tone = sin(phase) + 0.16 * sin(2.0 * phase) + e_tine * sin(5.4 * phase)
        val = tone * env_decay * att * rel
        left[idx] += val * lg
        right[idx] += val * rg
        phase += dphase
        e_tine *= decay_tine
        env_decay *= decay_env


def _add_celesta_note(
    left: list[float],
    right: list[float],
    sr: int,
    start_s: float,
    midi: float,
    dur_s: float,
    vel: float,
    pan: float = -0.14,
) -> None:
    start_idx = int(round(start_s * sr))
    n = int(round(dur_s * sr))
    if n <= 0 or start_idx >= len(left):
        return
    freq = _midi_to_hz(midi)
    dphase = TAU * freq / sr
    dt = 1.0 / sr
    lg, rg = _pan_gains(pan)
    att_s = 0.004
    rel_s = 0.045
    inv_att = 1.0 / att_s
    inv_rel = 1.0 / rel_s
    decay_2 = math.exp(-dt / 0.22)
    decay_3 = math.exp(-dt / 0.06)
    decay_env = math.exp(-dt / 0.90)
    sin = math.sin
    e2 = 0.24
    e3 = 0.08
    env_decay = vel * 0.12
    phase = 0.0
    end_idx = min(len(left), start_idx + n)
    for idx in range(start_idx, end_idx):
        t = (idx - start_idx) * dt
        att = sin(0.5 * math.pi * (t * inv_att)) if t < att_s else 1.0
        rel = (
            0.5 + 0.5 * math.cos(math.pi * (t - (dur_s - rel_s)) * inv_rel)
            if t > dur_s - rel_s
            else 1.0
        )
        tone = sin(phase) + e2 * sin(2.0 * phase) + e3 * sin(3.01 * phase)
        val = tone * env_decay * att * rel
        left[idx] += val * lg
        right[idx] += val * rg
        phase += dphase
        e2 *= decay_2
        e3 *= decay_3
        env_decay *= decay_env


def _add_clarinet_note(
    left: list[float],
    right: list[float],
    sr: int,
    start_s: float,
    midi: float,
    dur_s: float,
    vel: float,
    pan: float = 0.10,
) -> None:
    start_idx = int(round(start_s * sr))
    n = int(round(dur_s * sr))
    if n <= 0 or start_idx >= len(left):
        return
    freq = _midi_to_hz(midi)
    base_dphase = TAU * freq / sr
    dt = 1.0 / sr
    lg, rg = _pan_gains(pan)
    att_s = min(0.055, dur_s * 0.22)
    rel_s = min(0.085, dur_s * 0.28)
    inv_att = 1.0 / max(att_s, 1e-4)
    inv_rel = 1.0 / max(rel_s, 1e-4)
    vib_step = TAU * 4.6 * dt
    sin = math.sin
    phase = 0.0
    vib_ph = 0.0
    end_idx = min(len(left), start_idx + n)
    for idx in range(start_idx, end_idx):
        t = (idx - start_idx) * dt
        att = sin(0.5 * math.pi * (t * inv_att)) if t < att_s else 1.0
        rel = (
            0.5 + 0.5 * math.cos(math.pi * (t - (dur_s - rel_s)) * inv_rel)
            if t > dur_s - rel_s
            else 1.0
        )
        vib_depth = 0.0028 * min(1.0, max(0.0, (t - 0.12) / 0.22))
        vib = 1.0 + vib_depth * sin(vib_ph)
        # Warm woody odd-harmonic clarinet blend (mellowed so it never sounds reedy/harsh)
        tone = sin(phase) + 0.22 * sin(3.0 * phase) + 0.06 * sin(5.0 * phase)
        val = tone * (vel * 0.11) * att * rel
        left[idx] += val * lg
        right[idx] += val * rg
        phase += base_dphase * vib
        vib_ph += vib_step


def _add_warm_pad_note(
    left: list[float],
    right: list[float],
    sr: int,
    start_s: float,
    midi: float,
    dur_s: float,
    vel: float,
    pan: float = 0.0,
) -> None:
    start_idx = int(round(start_s * sr))
    n = int(round(dur_s * sr))
    if n <= 0 or start_idx >= len(left):
        return
    freq = _midi_to_hz(midi)
    dp1 = TAU * (freq * 0.9985) / sr
    dp2 = TAU * (freq * 1.0015) / sr
    dt = 1.0 / sr
    lg, rg = _pan_gains(pan)
    att_s = min(0.55, dur_s * 0.30)
    rel_s = min(0.65, dur_s * 0.32)
    inv_att = 1.0 / max(att_s, 1e-4)
    inv_rel = 1.0 / max(rel_s, 1e-4)
    sin = math.sin
    ph1 = 0.0
    ph2 = 0.7
    end_idx = min(len(left), start_idx + n)
    for idx in range(start_idx, end_idx):
        t = (idx - start_idx) * dt
        att = sin(0.5 * math.pi * (t * inv_att)) if t < att_s else 1.0
        rel = (
            0.5 + 0.5 * math.cos(math.pi * (t - (dur_s - rel_s)) * inv_rel)
            if t > dur_s - rel_s
            else 1.0
        )
        tone = 0.55 * (sin(ph1) + sin(ph2)) + 0.12 * sin(2.0 * ph1)
        val = tone * (vel * 0.065) * att * rel
        left[idx] += val * lg
        right[idx] += val * rg
        ph1 += dp1
        ph2 += dp2


def _add_shaker_hit(
    left: list[float],
    right: list[float],
    sr: int,
    start_s: float,
    vel: float,
    seed_val: int,
    pan: float = 0.28,
) -> None:
    start_idx = int(round(start_s * sr))
    dur_s = 0.050
    n = int(round(dur_s * sr))
    if n <= 0 or start_idx >= len(left):
        return
    rng = random.Random(seed_val)
    lg, rg = _pan_gains(pan)
    dt = 1.0 / sr
    lp = 0.0
    hp = 0.0
    prev_lp = 0.0
    end_idx = min(len(left), start_idx + n)
    for idx in range(start_idx, end_idx):
        t = (idx - start_idx) * dt
        lp = lp * 0.62 + rng.uniform(-1.0, 1.0) * 0.38
        hp = 0.78 * (hp + lp - prev_lp)
        prev_lp = lp
        env = math.sin(math.pi * min(1.0, t / dur_s)) * math.exp(-t / 0.016)
        val = hp * env * vel * 0.055
        left[idx] += val * lg
        right[idx] += val * rg


def _add_woodblock_hit(
    left: list[float],
    right: list[float],
    sr: int,
    start_s: float,
    freq: float,
    vel: float,
    pan: float = -0.26,
) -> None:
    start_idx = int(round(start_s * sr))
    dur_s = 0.042
    n = int(round(dur_s * sr))
    if n <= 0 or start_idx >= len(left):
        return
    lg, rg = _pan_gains(pan)
    dt = 1.0 / sr
    dphase = TAU * freq * dt
    phase = 0.0
    sin = math.sin
    end_idx = min(len(left), start_idx + n)
    for idx in range(start_idx, end_idx):
        t = (idx - start_idx) * dt
        att = sin(0.5 * math.pi * min(1.0, t / 0.0015))
        env = att * math.exp(-t / 0.009)
        tone = sin(phase) + 0.25 * sin(2.4 * phase) * math.exp(-t / 0.004)
        val = tone * env * vel * 0.065
        left[idx] += val * lg
        right[idx] += val * rg
        phase += dphase


def _apply_stereo_reverb(left: list[float], right: list[float], sr: int) -> None:
    taps = (
        (int(0.029 * sr), 0.16, 0.05),
        (int(0.043 * sr), 0.05, 0.14),
        (int(0.067 * sr), 0.12, 0.08),
        (int(0.097 * sr), 0.07, 0.11),
        (int(0.137 * sr), 0.09, 0.06),
        (int(0.181 * sr), 0.05, 0.08),
    )
    n = len(left)
    wet_l = [0.0] * n
    wet_r = [0.0] * n
    for delay_n, gl, gr in taps:
        gl_half = gl * 0.5
        gr_half = gr * 0.5
        for i in range(n - delay_n):
            dry_l = left[i]
            dry_r = right[i]
            j = i + delay_n
            wet_l[j] += dry_l * gl + dry_r * gr_half
            wet_r[j] += dry_r * gr + dry_l * gl_half
    wet_l = _one_pole_lowpass(wet_l, 1650.0, sr)
    wet_r = _one_pole_lowpass(wet_r, 1650.0, sr)
    for i in range(n):
        left[i] += 0.22 * wet_l[i]
        right[i] += 0.22 * wet_r[i]


def _finalize_music_track(
    left: list[float],
    right: list[float],
    sr: int,
    track_n: int,
    target_peak_db: float = -12.0,
    fade_in_s: float = 0.18,
    fade_out_s: float = 2.6,
) -> tuple[int, list[float], list[float], dict]:
    _apply_stereo_reverb(left, right, sr)
    left = left[:track_n]
    right = right[:track_n]

    fade_in_n = min(track_n // 4, int(round(fade_in_s * sr)))
    fade_out_n = min(track_n // 3, int(round(fade_out_s * sr)))
    for i in range(fade_in_n):
        w = 0.5 - 0.5 * math.cos(math.pi * i / max(1, fade_in_n))
        left[i] *= w
        right[i] *= w
    fade_start = track_n - fade_out_n
    for k in range(fade_out_n):
        w = 0.5 + 0.5 * math.cos(math.pi * k / max(1, fade_out_n))
        idx = fade_start + k
        left[idx] *= w
        right[idx] *= w
    left[-1] = 0.0
    right[-1] = 0.0

    dc_l_raw = sum(left) / track_n
    dc_r_raw = sum(right) / track_n
    for i in range(track_n):
        left[i] -= dc_l_raw
        right[i] -= dc_r_raw

    raw_peak = max(max(abs(x) for x in left), max(abs(x) for x in right), 1e-9)
    target_peak = 10.0 ** (target_peak_db / 20.0)
    gain = target_peak / raw_peak
    for i in range(track_n):
        left[i] *= gain
        right[i] *= gain

    has_nan = any(not math.isfinite(x) for x in left) or any(not math.isfinite(x) for x in right)
    peak = max(max(abs(x) for x in left), max(abs(x) for x in right))
    peak_db = 20.0 * math.log10(max(peak, 1e-12))
    rms_sq = (sum(x * x for x in left) + sum(x * x for x in right)) / (2.0 * track_n)
    rms_db = 10.0 * math.log10(max(rms_sq, 1e-12))
    dc_l = sum(left) / track_n
    dc_r = sum(right) / track_n
    end_amp = max(abs(left[0]), abs(right[0]), abs(left[-1]), abs(right[-1]))

    stats = {
        "duration_s": track_n / sr,
        "sample_rate": sr,
        "channels": 2,
        "samples": track_n,
        "peak": peak,
        "peak_db": peak_db,
        "rms_db": rms_db,
        "dc_l": dc_l,
        "dc_r": dc_r,
        "end_amp": end_amp,
        "has_nan": has_nan,
    }
    return sr, left, right, stats


def build_terminal_ambience_bed(sr: int = 44100) -> tuple[int, list[float], list[float], dict]:
    """24.0 s seamless stereo terminal room-air & distant concourse murmur bed (no music)."""
    loop_s = 24.0
    xfade_s = 3.0
    loop_n = int(round(loop_s * sr))
    xfade_n = int(round(xfade_s * sr))
    bed_n = loop_n + xfade_n

    rng_l = random.Random(20270701)
    rng_r = random.Random(20270702)
    air_l = _one_pole_highpass(
        _one_pole_lowpass(
            _one_pole_lowpass([rng_l.uniform(-1.0, 1.0) for _ in range(bed_n)], 310.0, sr),
            330.0,
            sr,
        ),
        62.0,
        sr,
    )
    air_r = _one_pole_highpass(
        _one_pole_lowpass(
            _one_pole_lowpass([rng_r.uniform(-1.0, 1.0) for _ in range(bed_n)], 310.0, sr),
            330.0,
            sr,
        ),
        62.0,
        sr,
    )
    mur_l = _one_pole_highpass(
        _one_pole_lowpass(
            _one_pole_lowpass([rng_l.uniform(-1.0, 1.0) for _ in range(bed_n)], 580.0, sr),
            520.0,
            sr,
        ),
        210.0,
        sr,
    )
    mur_r = _one_pole_highpass(
        _one_pole_lowpass(
            _one_pole_lowpass([rng_r.uniform(-1.0, 1.0) for _ in range(bed_n)], 580.0, sr),
            520.0,
            sr,
        ),
        210.0,
        sr,
    )

    buf_l = [0.0] * bed_n
    buf_r = [0.0] * bed_n
    for i in range(bed_n):
        t = i / sr
        air_env = 0.88 + 0.12 * math.sin(TAU * (1.0 / loop_s) * t + 0.3)
        mur_env = 0.62 + 0.24 * math.sin(TAU * (2.0 / loop_s) * t + 0.9) + 0.14 * math.sin(
            TAU * (3.0 / loop_s) * t + 2.1
        )
        buf_l[i] = 0.14 * air_env * air_l[i] + 0.055 * mur_env * mur_l[i]
        buf_r[i] = 0.14 * air_env * air_r[i] + 0.055 * mur_env * mur_r[i]

    left = [0.0] * loop_n
    right = [0.0] * loop_n
    for i in range(xfade_n):
        w = 0.5 - 0.5 * math.cos(math.pi * i / xfade_n)
        left[i] = buf_l[i] * w + buf_l[loop_n + i] * (1.0 - w)
        right[i] = buf_r[i] * w + buf_r[loop_n + i] * (1.0 - w)
    for i in range(xfade_n, loop_n):
        left[i] = buf_l[i]
        right[i] = buf_r[i]

    dc_l_raw = sum(left) / loop_n
    dc_r_raw = sum(right) / loop_n
    for i in range(loop_n):
        left[i] -= dc_l_raw
        right[i] -= dc_r_raw

    raw_peak = max(max(abs(x) for x in left), max(abs(x) for x in right), 1e-9)
    target_peak = 10.0 ** (-20.0 / 20.0)
    gain = target_peak / raw_peak
    for i in range(loop_n):
        left[i] *= gain
        right[i] *= gain

    has_nan = any(not math.isfinite(x) for x in left) or any(not math.isfinite(x) for x in right)
    peak = max(max(abs(x) for x in left), max(abs(x) for x in right))
    peak_db = 20.0 * math.log10(max(peak, 1e-12))
    rms_sq = (sum(x * x for x in left) + sum(x * x for x in right)) / (2.0 * loop_n)
    rms_db = 10.0 * math.log10(max(rms_sq, 1e-12))
    seam_diff = max(abs(left[0] - left[-1]), abs(right[0] - right[-1]))
    stats = {
        "duration_s": loop_s,
        "sample_rate": sr,
        "channels": 2,
        "samples": loop_n,
        "peak": peak,
        "peak_db": peak_db,
        "rms_db": rms_db,
        "dc_l": sum(left) / loop_n,
        "dc_r": sum(right) / loop_n,
        "end_amp": seam_diff,
        "has_nan": has_nan,
    }
    return sr, left, right, stats


def build_terminal_lounge_music(sr: int = 44100) -> tuple[int, list[float], list[float], dict]:
    """Track 1: 80.0 s (32 bars @ 96 BPM, C major / A minor) Warm Rhodes & Vibraphone Lounge."""
    bpm = 96.0
    beat_s = 60.0 / bpm
    bar_s = 4.0 * beat_s
    bars = 32
    track_s = bars * bar_s  # 80.00 s
    track_n = int(round(track_s * sr))
    buf_n = track_n + int(round(3.0 * sr))

    left = [0.0] * buf_n
    right = [0.0] * buf_n

    # C major / A minor warm jazz-lounge progression: (bar, chord_midis, bass_root, bass_alt)
    progression = [
        # Section A (bars 0..7)
        (0, (48, 55, 59, 62, 64), 36, 43),  # Cmaj9
        (1, (45, 52, 55, 59, 60), 33, 40),  # Am9
        (2, (53, 57, 60, 64, 67), 41, 48),  # Fmaj9
        (3, (43, 53, 57, 60, 62), 43, 36),  # G13sus4
        (4, (48, 55, 59, 62, 64), 36, 43),  # Cmaj9
        (5, (52, 55, 59, 62), 40, 47),  # Em7
        (6, (50, 57, 60, 64, 65), 38, 45),  # Dm9
        (7, (43, 53, 57, 59, 64), 43, 38),  # G13
        # Section A' (bars 8..15)
        (8, (48, 55, 59, 62, 64), 36, 43),  # Cmaj9
        (9, (45, 52, 55, 59, 60), 33, 40),  # Am9
        (10, (50, 57, 60, 64, 65), 38, 45),  # Dm9
        (11, (43, 53, 57, 60, 62), 43, 36),  # G13sus4
        (12, (52, 55, 59, 62), 40, 47),  # Em7
        (13, (45, 52, 55, 59, 60), 33, 40),  # Am9
        (14, (53, 57, 60, 64, 67), 41, 48),  # Fmaj9
        (15, (43, 53, 57, 59, 64), 43, 36),  # G13
        # Section B (bars 16..23)
        (16, (53, 57, 60, 64, 67), 41, 48),  # Fmaj9
        (17, (55, 59, 62, 64, 67), 43, 41),  # G6/F bass feel
        (18, (52, 55, 59, 62), 40, 47),  # Em7
        (19, (45, 52, 55, 59, 60), 33, 40),  # Am9
        (20, (50, 57, 60, 64, 65), 38, 45),  # Dm9
        (21, (52, 55, 59, 62), 40, 45),  # Em7
        (22, (53, 57, 60, 64, 67), 41, 48),  # Fmaj9
        (23, (43, 53, 57, 60, 62), 43, 36),  # G9sus4
        # Section C (bars 24..31): Calm final resolution to Cmaj9
        (24, (48, 55, 59, 62, 64), 36, 43),  # Cmaj9
        (25, (47, 55, 59, 62, 67), 47, 43),  # G/B
        (26, (45, 52, 55, 59, 60), 33, 40),  # Am9
        (27, (55, 58, 60, 64), 43, 36),  # C7/G
        (28, (53, 57, 60, 64), 41, 48),  # Fmaj7
        (29, (50, 57, 60, 64, 65), 38, 45),  # Dm9
        (30, (43, 53, 57, 59, 64), 43, 36),  # G13
        (31, (48, 55, 59, 62, 64), 36, 43),  # Cmaj9 home resolve
    ]

    for bar_idx, chord, bass_root, bass_alt in progression:
        t0 = bar_idx * bar_s
        is_final = bar_idx == bars - 1
        hold_beats = 3.85 if not is_final else 3.2
        for v_idx, note in enumerate(chord):
            _add_epiano_note(
                left,
                right,
                sr,
                t0 + v_idx * 0.018,
                note,
                hold_beats * beat_s,
                0.76,
                pan=-0.16 + 0.08 * (v_idx % 3),
            )
        if 8 <= bar_idx <= 29 and bar_idx % 2 == 1:
            push_t = t0 + 2.5 * beat_s
            for v_idx, note in enumerate(chord[1:4]):
                _add_epiano_note(
                    left,
                    right,
                    sr,
                    push_t + v_idx * 0.014,
                    note,
                    1.35 * beat_s,
                    0.46,
                    pan=0.14 - 0.07 * v_idx,
                )
        _add_upright_bass_note(left, right, sr, t0, bass_root, 1.85 * beat_s, 0.84)
        if not is_final:
            _add_upright_bass_note(left, right, sr, t0 + 2.0 * beat_s, bass_alt, 1.65 * beat_s, 0.70)
        if 16 <= bar_idx <= 23 and bar_idx % 2 == 0:
            _add_upright_bass_note(
                left, right, sr, t0 + 3.5 * beat_s, bass_root + 2, 0.55 * beat_s, 0.50
            )

    # Soft vibraphone lounge melody (C major / A minor)
    vibe_phrases = [
        (2, 0.0, 69, 1.2, 0.72),  # A4
        (2, 1.5, 72, 1.1, 0.76),  # C5
        (2, 2.5, 76, 1.4, 0.80),  # E5
        (3, 0.0, 74, 1.7, 0.72),  # D5
        (3, 2.0, 71, 1.3, 0.65),  # B4
        (6, 0.5, 69, 1.0, 0.72),
        (6, 1.5, 72, 1.0, 0.72),
        (6, 2.5, 74, 1.2, 0.76),
        (7, 0.0, 71, 1.8, 0.74),
        # Section A'
        (8, 0.0, 72, 0.9, 0.76),
        (8, 1.0, 74, 0.9, 0.78),
        (8, 2.0, 76, 0.9, 0.80),
        (8, 3.0, 79, 1.3, 0.84),
        (9, 0.5, 76, 1.3, 0.78),
        (9, 2.0, 74, 1.2, 0.74),
        (9, 3.0, 72, 1.3, 0.70),
        (10, 0.0, 69, 1.8, 0.72),
        (12, 0.0, 76, 1.0, 0.78),
        (12, 1.5, 74, 0.9, 0.74),
        (12, 2.5, 72, 1.2, 0.72),
        (13, 0.0, 71, 1.4, 0.72),
        (13, 2.0, 69, 1.2, 0.72),
        (14, 0.0, 72, 1.6, 0.76),
        (14, 2.0, 74, 1.5, 0.70),
        # Section B
        (16, 0.0, 76, 1.2, 0.78),
        (16, 1.5, 79, 1.1, 0.82),
        (16, 2.5, 81, 1.3, 0.84),
        (17, 0.0, 79, 1.5, 0.80),
        (17, 2.0, 76, 1.3, 0.74),
        (18, 0.5, 74, 1.1, 0.76),
        (18, 2.0, 76, 1.3, 0.78),
        (19, 0.0, 72, 1.9, 0.74),
        (20, 0.0, 69, 0.9, 0.74),
        (20, 1.0, 72, 0.9, 0.76),
        (20, 2.0, 74, 1.2, 0.80),
        (21, 0.0, 76, 1.4, 0.76),
        (21, 2.0, 74, 1.3, 0.72),
        (22, 0.0, 72, 1.6, 0.76),
        # Section C
        (24, 0.0, 76, 1.2, 0.76),
        (24, 1.5, 74, 1.1, 0.74),
        (24, 2.5, 72, 1.4, 0.76),
        (25, 0.0, 71, 1.5, 0.72),
        (26, 0.5, 69, 1.1, 0.72),
        (26, 2.0, 72, 1.4, 0.72),
        (27, 0.0, 76, 1.7, 0.74),
        (28, 0.0, 74, 1.2, 0.70),
        (28, 1.5, 72, 1.2, 0.70),
        (29, 0.0, 69, 1.5, 0.68),
        (30, 0.0, 71, 1.4, 0.66),
        (31, 0.0, 72, 2.6, 0.68),
    ]
    for bar_idx, beat_off, midi, dur_beats, vel in vibe_phrases:
        pan = max(-0.28, min(0.28, (midi - 72.0) * 0.025))
        _add_vibraphone_note(
            left,
            right,
            sr,
            bar_idx * bar_s + beat_off * beat_s,
            midi,
            dur_beats * beat_s,
            vel,
            pan=pan,
        )

    return _finalize_music_track(left, right, sr, track_n)


def build_morning_bossa_music(sr: int = 44100) -> tuple[int, list[float], list[float], dict]:
    """Track 2: 88.9 s (40 bars @ 108 BPM, F major) Morning Bossa Nova."""
    bpm = 108.0
    beat_s = 60.0 / bpm
    bar_s = 4.0 * beat_s
    bars = 40
    track_n = int(round(bars * bar_s * sr))
    buf_n = track_n + int(round(3.0 * sr))

    left = [0.0] * buf_n
    right = [0.0] * buf_n

    # F major cozy bossa nova progression
    prog_cycle = [
        ((53, 57, 60, 64), 41, 48),  # Fmaj7
        ((55, 59, 62, 65), 43, 50),  # G7
        ((55, 58, 62, 65), 43, 50),  # Gm7
        ((48, 55, 58, 62, 64), 36, 43),  # C9
        ((57, 60, 64, 67), 45, 52),  # Am7
        ((50, 54, 57, 60), 38, 45),  # D7
        ((55, 58, 62, 65), 43, 50),  # Gm7
        ((48, 55, 58, 64, 69), 36, 43),  # C13
    ]
    bridge_cycle = [
        ((58, 62, 65, 69), 46, 41),  # Bbmaj7
        ((58, 61, 65, 68), 46, 41),  # Bbm7
        ((57, 60, 64, 67), 45, 52),  # Am7
        ((50, 54, 57, 60), 38, 45),  # D7
        ((55, 58, 62, 65), 43, 50),  # Gm7
        ((48, 55, 58, 62, 64), 36, 43),  # C9
        ((53, 57, 60, 64), 41, 48),  # Fmaj7
        ((48, 55, 58, 62, 64), 36, 43),  # C9
    ]
    bossa_hits = (0.0, 0.75, 1.5, 2.5, 3.25)

    for bar_idx in range(bars):
        is_bridge = 16 <= bar_idx <= 23
        chord, bass_root, bass_alt = (
            bridge_cycle[bar_idx - 16] if is_bridge else prog_cycle[bar_idx % 8]
        )
        if bar_idx == bars - 1:
            chord, bass_root, bass_alt = prog_cycle[0]
        t0 = bar_idx * bar_s
        is_final = bar_idx == bars - 1

        # Syncopated bossa nylon guitar comping
        if is_final:
            for v_idx, note in enumerate(chord):
                _add_nylon_guitar_note(
                    left, right, sr, t0 + v_idx * 0.022, note, 3.0 * beat_s, 0.72, pan=-0.18
                )
        else:
            for hit_idx, beat_off in enumerate(bossa_hits):
                if hit_idx % 2 == 0:
                    for v_idx, note in enumerate(chord):
                        _add_nylon_guitar_note(
                            left,
                            right,
                            sr,
                            t0 + beat_off * beat_s + v_idx * 0.010,
                            note,
                            0.65 * beat_s,
                            0.68 if hit_idx == 0 else 0.56,
                            pan=-0.20 + 0.06 * v_idx,
                        )
                else:
                    for note in chord[1:3]:
                        _add_nylon_guitar_note(
                            left,
                            right,
                            sr,
                            t0 + beat_off * beat_s,
                            note,
                            0.45 * beat_s,
                            0.48,
                            pan=-0.12,
                        )

        # Classic dotted-quarter bossa bass pattern
        _add_upright_bass_note(left, right, sr, t0, bass_root, 1.35 * beat_s, 0.82)
        if not is_final:
            _add_upright_bass_note(left, right, sr, t0 + 1.5 * beat_s, bass_alt, 0.50 * beat_s, 0.62)
            _add_upright_bass_note(left, right, sr, t0 + 2.0 * beat_s, bass_alt, 1.35 * beat_s, 0.74)
            _add_upright_bass_note(left, right, sr, t0 + 3.5 * beat_s, bass_root, 0.50 * beat_s, 0.60)

        # Gentle brushed shaker 8ths (bars 2..37)
        if 2 <= bar_idx <= bars - 3:
            for step in range(8):
                vel = 0.65 if step % 2 == 0 else 0.36
                _add_shaker_hit(
                    left,
                    right,
                    sr,
                    t0 + step * 0.5 * beat_s,
                    vel,
                    seed_val=9100 + bar_idx * 16 + step,
                    pan=0.28,
                )

    # Soft mellow flute melody over the bossa groove
    flute_phrases = [
        (2, 0.5, 69, 1.0, 0.74),  # A4
        (2, 1.5, 72, 1.0, 0.76),  # C5
        (2, 2.5, 76, 1.4, 0.80),  # E5
        (3, 0.0, 74, 1.6, 0.74),  # D5
        (4, 0.5, 72, 1.0, 0.74),  # C5
        (4, 1.5, 74, 0.9, 0.76),  # D5
        (4, 2.5, 77, 1.3, 0.80),  # F5
        (5, 0.0, 76, 1.5, 0.76),  # E5
        (6, 0.5, 74, 1.0, 0.74),
        (6, 1.5, 72, 1.0, 0.74),
        (6, 2.5, 70, 1.2, 0.72),
        (7, 0.0, 69, 1.8, 0.72),
        # Repeat / variation bars 10..15
        (10, 0.0, 72, 0.9, 0.78),
        (10, 1.0, 74, 0.9, 0.80),
        (10, 2.0, 77, 1.2, 0.82),
        (11, 0.0, 79, 1.5, 0.82),
        (11, 2.0, 76, 1.2, 0.74),
        (12, 0.5, 74, 1.1, 0.74),
        (12, 2.0, 72, 1.4, 0.74),
        (13, 0.0, 69, 1.7, 0.72),
        (14, 0.5, 70, 1.0, 0.74),
        (14, 1.5, 72, 1.0, 0.74),
        (14, 2.5, 74, 1.2, 0.76),
        (15, 0.0, 72, 1.7, 0.72),
        # Bridge bars 16..23
        (16, 0.0, 77, 1.2, 0.80),
        (16, 1.5, 79, 1.0, 0.82),
        (16, 2.5, 81, 1.4, 0.84),
        (17, 0.0, 77, 1.6, 0.78),
        (18, 0.5, 76, 1.0, 0.76),
        (18, 1.5, 74, 1.0, 0.74),
        (18, 2.5, 72, 1.3, 0.74),
        (19, 0.0, 74, 1.7, 0.74),
        (20, 0.5, 72, 1.0, 0.74),
        (20, 1.5, 74, 1.0, 0.76),
        (20, 2.5, 76, 1.2, 0.78),
        (21, 0.0, 77, 1.5, 0.76),
        (22, 0.0, 76, 1.3, 0.74),
        (22, 1.5, 74, 1.3, 0.72),
        # Return bars 26..38
        (26, 0.0, 72, 1.0, 0.76),
        (26, 1.5, 74, 1.0, 0.78),
        (26, 2.5, 76, 1.2, 0.80),
        (27, 0.0, 74, 1.6, 0.74),
        (28, 0.5, 69, 1.0, 0.72),
        (28, 1.5, 72, 1.0, 0.74),
        (28, 2.5, 74, 1.3, 0.76),
        (29, 0.0, 72, 1.6, 0.72),
        (32, 0.0, 77, 1.1, 0.78),
        (32, 1.5, 76, 1.0, 0.76),
        (32, 2.5, 74, 1.2, 0.74),
        (33, 0.0, 72, 1.6, 0.74),
        (34, 0.5, 70, 1.1, 0.72),
        (34, 2.0, 69, 1.3, 0.70),
        (36, 0.0, 72, 1.4, 0.72),
        (37, 0.0, 69, 2.0, 0.68),
        (39, 0.0, 69, 2.4, 0.64),
    ]
    for bar_idx, beat_off, midi, dur_beats, vel in flute_phrases:
        _add_soft_flute_note(
            left, right, sr, bar_idx * bar_s + beat_off * beat_s, midi, dur_beats * beat_s, vel, pan=0.16
        )

    return _finalize_music_track(left, right, sr, track_n)


def build_sunny_marimba_music(sr: int = 44100) -> tuple[int, list[float], list[float], dict]:
    """Track 3: 88.4 s (42 bars @ 114 BPM, G major) Playful Marimba & Kalimba."""
    bpm = 114.0
    beat_s = 60.0 / bpm
    bar_s = 4.0 * beat_s
    bars = 42
    track_n = int(round(bars * bar_s * sr))
    buf_n = track_n + int(round(3.0 * sr))

    left = [0.0] * buf_n
    right = [0.0] * buf_n

    # G major sunlit progression
    section_a = [
        ((55, 59, 62, 66), 43, 50),  # Gmaj7
        ((52, 55, 59, 62, 66), 40, 47),  # Em9
        ((48, 55, 59, 64), 36, 43),  # Cmaj7
        ((50, 57, 60, 64), 38, 45),  # D9sus4
        ((55, 59, 62, 66), 43, 50),  # Gmaj7
        ((59, 62, 66, 69), 47, 42),  # Bm7
        ((57, 60, 64, 67), 45, 52),  # Am7
        ((50, 57, 60, 66), 38, 45),  # D9
    ]
    section_b = [
        ((59, 62, 66, 69), 47, 54),  # Bm7
        ((52, 55, 59, 62), 40, 47),  # Em7
        ((57, 60, 64, 67, 71), 45, 52),  # Am9
        ((50, 57, 60, 64, 66), 38, 45),  # D13
        ((48, 55, 59, 62), 36, 43),  # Cmaj9
        ((55, 59, 62, 66), 43, 50),  # Gmaj7
        ((57, 60, 64, 67), 45, 52),  # Am7
        ((50, 57, 60, 64), 38, 45),  # D9sus4
    ]

    for bar_idx in range(bars):
        if 16 <= bar_idx <= 23:
            chord, bass_root, bass_alt = section_b[bar_idx - 16]
        else:
            chord, bass_root, bass_alt = section_a[bar_idx % 8]
        if bar_idx == bars - 1:
            chord, bass_root, bass_alt = section_a[0]
        t0 = bar_idx * bar_s
        is_final = bar_idx == bars - 1

        # Bouncy kalimba arpeggios across the 4 beats
        if is_final:
            for v_idx, note in enumerate(chord):
                _add_kalimba_note(
                    left, right, sr, t0 + v_idx * 0.04, note, 1.6 * beat_s, 0.72, pan=-0.18 + 0.09 * v_idx
                )
        else:
            arp_order = (0, 1, 2, 3, 2, 1, 3, 2)
            for step in range(8):
                note = chord[arp_order[step] % len(chord)] + (12 if step in (3, 6) else 0)
                vel = 0.66 if step % 2 == 0 else 0.50
                _add_kalimba_note(
                    left,
                    right,
                    sr,
                    t0 + step * 0.5 * beat_s,
                    note,
                    0.48 * beat_s,
                    vel,
                    pan=-0.24 + 0.06 * (step % 4),
                )

        # Light pizzicato upright bass + sunny offbeat woodblock
        _add_upright_bass_note(left, right, sr, t0, bass_root, 0.9 * beat_s, 0.80)
        if not is_final:
            _add_upright_bass_note(left, right, sr, t0 + 1.5 * beat_s, bass_alt, 0.6 * beat_s, 0.64)
            _add_upright_bass_note(left, right, sr, t0 + 2.0 * beat_s, bass_root, 0.9 * beat_s, 0.72)
            _add_upright_bass_note(left, right, sr, t0 + 3.0 * beat_s, bass_alt, 0.6 * beat_s, 0.60)
            if 4 <= bar_idx <= bars - 3:
                _add_woodblock_hit(left, right, sr, t0 + 1.0 * beat_s, 920.0, 0.62, pan=-0.28)
                _add_woodblock_hit(left, right, sr, t0 + 3.0 * beat_s, 780.0, 0.56, pan=0.28)

    # Bright cheerful marimba lead phrases (G major)
    marimba_lead = [
        (2, 0.0, 71, 0.8, 0.76),  # B4
        (2, 1.0, 74, 0.8, 0.78),  # D5
        (2, 2.0, 79, 1.0, 0.82),  # G5
        (2, 3.0, 78, 0.8, 0.76),  # F#5
        (3, 0.0, 76, 1.3, 0.76),  # E5
        (3, 2.0, 74, 1.2, 0.72),  # D5
        (6, 0.0, 72, 0.8, 0.74),  # C5
        (6, 1.0, 74, 0.8, 0.76),  # D5
        (6, 2.0, 76, 1.0, 0.80),  # E5
        (7, 0.0, 74, 1.5, 0.76),  # D5
        # Section A' (bars 8..15)
        (8, 0.0, 79, 0.8, 0.82),
        (8, 1.0, 78, 0.8, 0.78),
        (8, 2.0, 76, 0.8, 0.78),
        (8, 3.0, 74, 0.9, 0.76),
        (9, 0.5, 71, 1.1, 0.76),
        (9, 2.0, 74, 1.2, 0.74),
        (10, 0.0, 76, 1.4, 0.78),
        (10, 2.0, 79, 1.1, 0.80),
        (11, 0.0, 78, 1.5, 0.74),
        (12, 0.0, 74, 0.8, 0.76),
        (12, 1.0, 76, 0.8, 0.78),
        (12, 2.0, 79, 1.0, 0.82),
        (13, 0.0, 81, 1.2, 0.82),
        (13, 2.0, 79, 1.0, 0.76),
        (14, 0.0, 76, 1.3, 0.76),
        (15, 0.0, 74, 1.6, 0.74),
        # Section B (bars 16..23)
        (16, 0.0, 78, 0.9, 0.80),
        (16, 1.5, 79, 0.9, 0.82),
        (16, 2.5, 83, 1.2, 0.84),
        (17, 0.0, 81, 1.4, 0.80),
        (17, 2.0, 79, 1.2, 0.76),
        (18, 0.0, 76, 0.9, 0.76),
        (18, 1.0, 79, 0.9, 0.78),
        (18, 2.0, 81, 1.1, 0.80),
        (19, 0.0, 78, 1.6, 0.76),
        (20, 0.0, 76, 0.9, 0.76),
        (20, 1.5, 79, 1.0, 0.80),
        (21, 0.0, 78, 1.2, 0.76),
        (21, 2.0, 74, 1.1, 0.72),
        (22, 0.0, 76, 1.4, 0.74),
        (23, 0.0, 74, 1.6, 0.72),
        # Final return (bars 26..40)
        (26, 0.0, 71, 0.8, 0.76),
        (26, 1.0, 74, 0.8, 0.78),
        (26, 2.0, 79, 1.1, 0.82),
        (27, 0.0, 76, 1.4, 0.76),
        (28, 0.5, 74, 1.0, 0.74),
        (28, 2.0, 71, 1.2, 0.72),
        (30, 0.0, 76, 1.0, 0.76),
        (30, 1.5, 78, 1.0, 0.76),
        (31, 0.0, 79, 1.6, 0.80),
        (34, 0.0, 74, 0.9, 0.74),
        (34, 1.5, 76, 0.9, 0.76),
        (35, 0.0, 79, 1.4, 0.78),
        (36, 0.0, 78, 1.2, 0.74),
        (36, 2.0, 74, 1.2, 0.70),
        (38, 0.0, 76, 1.2, 0.72),
        (39, 0.0, 74, 1.5, 0.70),
        (41, 0.0, 79, 2.0, 0.72),
    ]
    for bar_idx, beat_off, midi, dur_beats, vel in marimba_lead:
        _add_marimba_note(
            left,
            right,
            sr,
            bar_idx * bar_s + beat_off * beat_s,
            midi,
            dur_beats * beat_s,
            vel,
            pan=0.14,
        )

    return _finalize_music_track(left, right, sr, track_n)


def build_breezy_stroll_music(sr: int = 44100) -> tuple[int, list[float], list[float], dict]:
    """Track 4: 90.0 s (44 bars in 3/4 waltz @ 88 BPM, D major) Celesta & Soft Clarinet."""
    bpm = 88.0
    beat_s = 60.0 / bpm
    bar_s = 3.0 * beat_s  # 3/4 waltz time!
    bars = 44
    track_n = int(round(bars * bar_s * sr))  # 90.00 s exact
    buf_n = track_n + int(round(3.0 * sr))

    left = [0.0] * buf_n
    right = [0.0] * buf_n

    # D major 3/4 cozy waltz progression
    waltz_a = [
        ((50, 57, 61, 66), 38),  # Dmaj7
        ((59, 62, 66, 69), 47),  # Bm7
        ((55, 59, 62, 66), 43),  # Gmaj7
        ((57, 62, 64, 67), 45),  # A7sus4
        ((54, 57, 61, 64), 42),  # F#m7
        ((59, 62, 66, 69), 47),  # Bm7
        ((52, 55, 59, 64), 40),  # Em7
        ((57, 61, 64, 67), 45),  # A7
    ]
    waltz_b = [
        ((55, 59, 62, 66), 43),  # Gmaj7
        ((57, 61, 64, 67), 43),  # A/G
        ((54, 57, 61, 64), 42),  # F#m7
        ((59, 62, 66, 69), 47),  # Bm7
        ((52, 55, 59, 62), 40),  # Em7
        ((57, 61, 64, 67), 45),  # A7
        ((50, 57, 61, 66), 38),  # Dmaj7
        ((57, 62, 64, 67), 45),  # A7sus4
    ]

    for bar_idx in range(bars):
        if 16 <= bar_idx <= 23:
            chord, bass_root = waltz_b[bar_idx - 16]
        else:
            chord, bass_root = waltz_a[bar_idx % 8]
        if bar_idx == bars - 1:
            chord, bass_root = waltz_a[0]
        t0 = bar_idx * bar_s
        is_final = bar_idx == bars - 1

        # 3/4 waltz bass on beat 1 + celesta chord sparkle on beats 2 & 3
        _add_upright_bass_note(left, right, sr, t0, bass_root, 1.9 * beat_s, 0.80)
        if is_final:
            for v_idx, note in enumerate(chord):
                _add_celesta_note(
                    left, right, sr, t0 + v_idx * 0.045, note, 2.2 * beat_s, 0.72, pan=-0.16 + 0.1 * v_idx
                )
        else:
            for beat in (1.0, 2.0):
                vel = 0.64 if beat == 1.0 else 0.54
                for v_idx, note in enumerate(chord[1:]):
                    _add_celesta_note(
                        left,
                        right,
                        sr,
                        t0 + beat * beat_s + v_idx * 0.012,
                        note,
                        0.95 * beat_s,
                        vel,
                        pan=-0.22 + 0.12 * v_idx,
                    )
            # Gentle Rhodes pad accent on beat 1 every second bar
            if bar_idx % 2 == 0:
                for note in chord[:3]:
                    _add_epiano_note(left, right, sr, t0, note, 2.5 * beat_s, 0.44, pan=-0.10)

    # Relaxed strolling soft-clarinet melody in 3/4 (D major)
    clarinet_phrases = [
        (2, 0.0, 66, 2.0, 0.72),  # F#4
        (2, 2.0, 69, 1.0, 0.74),  # A4
        (3, 0.0, 74, 2.2, 0.78),  # D5
        (4, 0.0, 73, 1.5, 0.74),  # C#5
        (4, 1.5, 71, 1.5, 0.72),  # B4
        (5, 0.0, 69, 2.4, 0.72),  # A4
        (6, 0.0, 67, 1.5, 0.72),  # G4
        (6, 1.5, 69, 1.5, 0.74),  # A4
        (7, 0.0, 66, 2.5, 0.72),  # F#4
        # A' (bars 8..15)
        (8, 0.0, 69, 1.5, 0.74),
        (8, 1.5, 71, 1.5, 0.76),
        (9, 0.0, 74, 2.0, 0.80),
        (9, 2.0, 76, 1.0, 0.80),
        (10, 0.0, 78, 2.2, 0.82),  # F#5
        (11, 0.0, 76, 1.5, 0.76),
        (11, 1.5, 74, 1.5, 0.74),
        (12, 0.0, 73, 2.4, 0.74),
        (14, 0.0, 71, 1.5, 0.74),
        (14, 1.5, 69, 1.5, 0.72),
        (15, 0.0, 66, 2.4, 0.70),
        # B (bars 16..23)
        (16, 0.0, 71, 2.0, 0.76),
        (16, 2.0, 74, 1.0, 0.78),
        (17, 0.0, 73, 2.2, 0.78),
        (18, 0.0, 69, 1.5, 0.74),
        (18, 1.5, 73, 1.5, 0.76),
        (19, 0.0, 74, 2.4, 0.78),
        (20, 0.0, 76, 1.5, 0.78),
        (20, 1.5, 74, 1.5, 0.74),
        (21, 0.0, 73, 2.4, 0.74),
        (22, 0.0, 74, 2.6, 0.76),
        # Return (bars 26..42)
        (26, 0.0, 66, 1.5, 0.74),
        (26, 1.5, 69, 1.5, 0.76),
        (27, 0.0, 74, 2.4, 0.78),
        (28, 0.0, 73, 1.5, 0.74),
        (28, 1.5, 71, 1.5, 0.72),
        (29, 0.0, 69, 2.4, 0.72),
        (32, 0.0, 74, 2.0, 0.76),
        (32, 2.0, 73, 1.0, 0.74),
        (33, 0.0, 71, 2.2, 0.74),
        (34, 0.0, 69, 1.5, 0.72),
        (34, 1.5, 67, 1.5, 0.70),
        (35, 0.0, 66, 2.5, 0.70),
        (38, 0.0, 69, 1.8, 0.70),
        (39, 0.0, 67, 1.8, 0.68),
        (40, 0.0, 66, 2.0, 0.68),
        (42, 0.0, 62, 2.8, 0.64),
    ]
    for bar_idx, beat_off, midi, dur_beats, vel in clarinet_phrases:
        _add_clarinet_note(
            left, right, sr, bar_idx * bar_s + beat_off * beat_s, midi, dur_beats * beat_s, vel, pan=0.12
        )

    return _finalize_music_track(left, right, sr, track_n)


def build_sunset_acoustic_music(sr: int = 44100) -> tuple[int, list[float], list[float], dict]:
    """Track 5: 93.7 s (32 bars @ 82 BPM, Eb / Bb major) Evening Rhodes, Acoustic & Warm Pad."""
    bpm = 82.0
    beat_s = 60.0 / bpm
    bar_s = 4.0 * beat_s
    bars = 32
    track_n = int(round(bars * bar_s * sr))  # ~93.66 s
    buf_n = track_n + int(round(3.0 * sr))

    left = [0.0] * buf_n
    right = [0.0] * buf_n

    # Eb major / Bb major warm evening progression
    prog_eb = [
        ((51, 55, 58, 62, 65), 39, 46),  # Ebmaj9
        ((48, 55, 58, 62, 63), 36, 43),  # Cm9
        ((56, 60, 63, 67), 44, 51),  # Abmaj7
        ((46, 53, 56, 60, 63), 34, 41),  # Bb9sus4
        ((55, 58, 62, 65), 43, 50),  # Gm7
        ((48, 55, 58, 62, 63), 36, 43),  # Cm9
        ((53, 56, 60, 63, 67), 41, 48),  # Fm9
        ((46, 53, 56, 62, 67), 34, 41),  # Bb13
    ]
    prog_bb = [
        ((58, 62, 65, 69), 46, 41),  # Bbmaj7
        ((51, 55, 58, 62), 46, 39),  # Ebmaj7/Bb
        ((57, 60, 63, 67), 45, 53),  # Am7b5 -> F9/A
        ((50, 57, 60, 65), 38, 45),  # Dm7
        ((55, 58, 62, 65), 43, 50),  # Gm7
        ((48, 55, 58, 62), 36, 43),  # Cm9
        ((56, 60, 63, 67), 44, 51),  # Abmaj7
        ((46, 53, 56, 60, 63), 34, 41),  # Bb9sus4
    ]

    for bar_idx in range(bars):
        if 16 <= bar_idx <= 23:
            chord, bass_root, bass_alt = prog_bb[bar_idx - 16]
        else:
            chord, bass_root, bass_alt = prog_eb[bar_idx % 8]
        if bar_idx == bars - 1:
            chord, bass_root, bass_alt = prog_eb[0]
        t0 = bar_idx * bar_s
        is_final = bar_idx == bars - 1

        # Warm slow pad bed on chord tones
        for v_idx, note in enumerate(chord[:4]):
            _add_warm_pad_note(
                left,
                right,
                sr,
                t0,
                note,
                bar_s * (0.85 if is_final else 1.02),
                0.70,
                pan=-0.20 + 0.13 * v_idx,
            )

        # Gentle fingerpicked nylon acoustic arpeggio across the bar
        if not is_final:
            pick_steps = (0, 1, 2, 3, 2, 1, 2, 3)
            for step in range(8):
                note = chord[pick_steps[step] % len(chord)]
                _add_nylon_guitar_note(
                    left,
                    right,
                    sr,
                    t0 + step * 0.5 * beat_s,
                    note,
                    1.1 * beat_s,
                    0.56 if step % 2 == 0 else 0.44,
                    pan=-0.22 + 0.06 * (step % 4),
                )

        # Mellow evening Rhodes chord shimmer on beat 1 of even bars
        if bar_idx % 2 == 0:
            for v_idx, note in enumerate(chord):
                _add_epiano_note(
                    left,
                    right,
                    sr,
                    t0 + v_idx * 0.025,
                    note,
                    3.2 * beat_s,
                    0.52,
                    pan=0.12 - 0.06 * v_idx,
                )

        # Deep warm bass
        _add_upright_bass_note(left, right, sr, t0, bass_root, 2.2 * beat_s, 0.84)
        if not is_final:
            _add_upright_bass_note(left, right, sr, t0 + 2.5 * beat_s, bass_alt, 1.4 * beat_s, 0.66)

    # Mellow evening acoustic + Rhodes lead melody (Eb / Bb major)
    lead_notes = [
        (1, 2.0, 67, 1.5, 0.72),  # G4
        (2, 0.0, 70, 1.8, 0.76),  # Bb4
        (2, 2.0, 74, 1.6, 0.78),  # D5
        (3, 0.0, 72, 2.2, 0.74),  # C5
        (5, 2.0, 70, 1.4, 0.72),  # Bb4
        (6, 0.0, 75, 1.6, 0.78),  # Eb5
        (6, 2.0, 74, 1.4, 0.74),  # D5
        (7, 0.0, 70, 2.4, 0.72),  # Bb4
        # Bars 8..15
        (8, 0.0, 74, 1.5, 0.76),  # D5
        (8, 2.0, 75, 1.5, 0.78),  # Eb5
        (9, 0.0, 77, 1.8, 0.80),  # F5
        (9, 2.0, 75, 1.4, 0.74),  # Eb5
        (10, 0.0, 74, 2.0, 0.74),
        (11, 0.0, 70, 2.2, 0.72),
        (12, 1.0, 72, 1.4, 0.72),
        (12, 2.5, 74, 1.4, 0.74),
        (13, 0.0, 75, 2.0, 0.76),
        (14, 0.0, 72, 1.6, 0.72),
        (15, 0.0, 70, 2.2, 0.70),
        # Bridge bars 16..23 (Bb major glow)
        (16, 0.0, 74, 1.5, 0.76),
        (16, 2.0, 77, 1.6, 0.80),
        (17, 0.0, 79, 2.0, 0.82),  # G5
        (18, 0.0, 77, 1.8, 0.76),
        (19, 0.0, 74, 2.2, 0.74),
        (20, 1.0, 75, 1.4, 0.74),
        (20, 2.5, 74, 1.3, 0.72),
        (21, 0.0, 72, 2.0, 0.72),
        (22, 0.0, 70, 2.4, 0.70),
        # Final return (bars 24..31)
        (24, 0.0, 75, 1.6, 0.76),
        (24, 2.0, 74, 1.5, 0.74),
        (25, 0.0, 72, 2.0, 0.72),
        (26, 1.0, 70, 1.5, 0.70),
        (27, 0.0, 67, 2.2, 0.70),
        (28, 0.0, 70, 1.8, 0.70),
        (29, 0.0, 67, 2.0, 0.66),
        (31, 0.0, 67, 2.6, 0.64),
    ]
    for bar_idx, beat_off, midi, dur_beats, vel in lead_notes:
        _add_epiano_note(
            left, right, sr, bar_idx * bar_s + beat_off * beat_s, midi, dur_beats * beat_s, vel, pan=0.16
        )

    return _finalize_music_track(left, right, sr, track_n)


def _find_blender_bin() -> str | None:
    env_bin = os.environ.get("BLENDER_BIN")
    if env_bin and Path(env_bin).is_file():
        return env_bin
    on_path = shutil.which("blender")
    if on_path:
        return on_path
    default_win = Path("/mnt/c/Program Files/Blender Foundation/Blender 5.2/blender.exe")
    if default_win.is_file():
        return str(default_win)
    return None


def _to_win_path(path: Path) -> str:
    if shutil.which("wslpath"):
        return subprocess.check_output(["wslpath", "-w", str(path)], text=True).strip()
    return str(path)


def _encode_ogg_from_stereo(
    out_ogg: Path, sr: int, left: list[float], right: list[float], bitrate_kbps: int = 160
) -> str:
    out_ogg.parent.mkdir(parents=True, exist_ok=True)
    ffmpeg_bin = shutil.which("ffmpeg")
    oggenc_bin = shutil.which("oggenc")
    blender_bin = _find_blender_bin()

    with tempfile.TemporaryDirectory() as tmp_dir:
        tmp_wav = Path(tmp_dir) / "lounge_master.wav"
        _write_stereo_wav(tmp_wav, sr, left, right)
        if ffmpeg_bin:
            subprocess.run(
                [
                    ffmpeg_bin,
                    "-y",
                    "-i",
                    str(tmp_wav),
                    "-c:a",
                    "libvorbis",
                    "-b:a",
                    f"{bitrate_kbps}k",
                    str(out_ogg),
                ],
                stdin=subprocess.DEVNULL,
                timeout=120,
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            return "ffmpeg"
        if oggenc_bin:
            subprocess.run(
                [
                    oggenc_bin,
                    "-b",
                    str(bitrate_kbps),
                    "-o",
                    str(out_ogg),
                    str(tmp_wav),
                ],
                stdin=subprocess.DEVNULL,
                timeout=120,
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            return "oggenc"
        if blender_bin:
            win_in = _to_win_path(tmp_wav)
            win_out = _to_win_path(out_ogg)
            expr = (
                "import aud; "
                f"s=aud.Sound.file({win_in!r}); "
                f"s.write({win_out!r}, {sr}, aud.CHANNELS_STEREO, aud.FORMAT_FLOAT32, "
                f"aud.CONTAINER_OGG, aud.CODEC_VORBIS, {bitrate_kbps * 1000}, 4096); "
                f"r=aud.Sound.file({win_out!r}); "
                "assert r.length == s.length, f'length mismatch {r.length} != {s.length}'"
            )
            subprocess.run(
                [blender_bin, "--background", "--factory-startup", "--python-expr", expr],
                stdin=subprocess.DEVNULL,
                timeout=120,
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            return "blender-aud"
        raise RuntimeError(
            "No Ogg Vorbis encoder found (checked ffmpeg, oggenc, and Blender 5.2)."
        )


def _env_attack_exp(t: float, duration: float, attack: float, tau: float) -> float:
    if t < 0.0 or t >= duration:
        return 0.0
    att = math.sin(0.5 * math.pi * (t / attack)) if t < attack else 1.0
    tail_fade = 1.0
    fade_len = 0.008
    if t > duration - fade_len:
        tail_fade = 0.5 + 0.5 * math.cos(math.pi * (t - (duration - fade_len)) / fade_len)
    return att * math.exp(-t / tau) * tail_fade


def build_ui_click(sr: int = 44100) -> tuple[int, list[float]]:
    """45 ms warm wooden/cream button tap."""
    dur = 0.045
    n = int(dur * sr)
    rng = random.Random(101)
    velvet = _one_pole_lowpass([rng.uniform(-1.0, 1.0) for _ in range(n)], 1800.0, sr)
    out = [0.0] * n
    phase = 0.0
    for i in range(n):
        t = i / sr
        freq = 430.0 + 210.0 * math.exp(-t / 0.009)
        phase += TAU * freq / sr
        body = math.sin(phase) + 0.28 * math.sin(2.3 * phase) * math.exp(-t / 0.008)
        tap = velvet[i] * math.exp(-t / 0.0035) * 0.25
        env = _env_attack_exp(t, dur, 0.0018, 0.011)
        out[i] = 0.34 * (body * env + tap * env)
    out[-1] = 0.0
    return sr, out


def build_place_sfx(sr: int = 44100) -> tuple[int, list[float]]:
    """90 ms cozy tactile architectural model placement pop."""
    dur = 0.090
    n = int(dur * sr)
    out = [0.0] * n
    phase = 0.0
    sub_phase = 0.0
    for i in range(n):
        t = i / sr
        # Gentle upward bloom 280 -> 510 Hz
        freq = 510.0 - 230.0 * math.exp(-t / 0.016)
        phase += TAU * freq / sr
        sub_phase += TAU * 165.0 / sr
        tone = math.sin(phase) + 0.32 * math.sin(1.5 * phase) * math.exp(-t / 0.028)
        thump = 0.40 * math.sin(sub_phase) * math.exp(-t / 0.018)
        env = _env_attack_exp(t, dur, 0.0022, 0.024)
        out[i] = 0.42 * (tone + thump) * env
    out[-1] = 0.0
    return sr, out


def build_remove_sfx(sr: int = 44100) -> tuple[int, list[float]]:
    """80 ms soft muted brush/pop release."""
    dur = 0.080
    n = int(dur * sr)
    rng = random.Random(202)
    brush = _one_pole_lowpass([rng.uniform(-1.0, 1.0) for _ in range(n)], 1100.0, sr)
    brush = _one_pole_highpass(brush, 300.0, sr)
    out = [0.0] * n
    phase = 0.0
    for i in range(n):
        t = i / sr
        # Gentle downward release 420 -> 215 Hz
        freq = 215.0 + 205.0 * math.exp(-t / 0.022)
        phase += TAU * freq / sr
        env = _env_attack_exp(t, dur, 0.0025, 0.021)
        out[i] = 0.35 * (0.78 * math.sin(phase) + 0.35 * brush[i]) * env
    out[-1] = 0.0
    return sr, out


def build_refuse_sfx(sr: int = 44100) -> tuple[int, list[float]]:
    """115 ms gentle low marimba double-thud (never harsh)."""
    dur = 0.115
    n = int(dur * sr)
    out = [0.0] * n
    notes = [(0.0, 220.0, 0.34), (0.052, 174.61, 0.30)]
    for start_t, freq, amp in notes:
        for i in range(n):
            t = i / sr - start_t
            if t < 0.0:
                continue
            note_dur = dur - start_t
            env = _env_attack_exp(t, note_dur, 0.0022, 0.020)
            # Marimba-like fundamental + fast-decaying 4th harmonic
            sample = math.sin(TAU * freq * t) + 0.18 * math.sin(TAU * (freq * 3.98) * t) * math.exp(
                -t / 0.007
            )
            out[i] += amp * sample * env
    out[-1] = 0.0
    return sr, out


def build_cash_chime(sr: int = 44100) -> tuple[int, list[float]]:
    """185 ms warm two-note cozy bell/register chime (C5 -> G5)."""
    dur = 0.185
    n = int(dur * sr)
    out = [0.0] * n
    notes = [
        (0.000, 523.25, 0.28, 0.045),
        (0.062, 783.99, 0.30, 0.055),
        (0.062, 1046.50, 0.09, 0.038),
    ]
    for start_t, freq, amp, tau in notes:
        for i in range(n):
            t = i / sr - start_t
            if t < 0.0:
                continue
            note_dur = dur - start_t
            env = _env_attack_exp(t, note_dur, 0.0020, tau)
            bell = math.sin(TAU * freq * t) + 0.22 * math.sin(TAU * (freq * 2.0) * t) * math.exp(
                -t / 0.022
            )
            out[i] += amp * bell * env
    out[-1] = 0.0
    return sr, out


def _render_bell_notes(
    dur: float, notes: list[tuple[float, float, float, float]], sr: int = 44100
) -> tuple[int, list[float]]:
    n = int(dur * sr)
    out = [0.0] * n
    for start_t, freq, amp, tau in notes:
        for i in range(n):
            t = i / sr - start_t
            if t < 0.0:
                continue
            note_dur = dur - start_t
            env = _env_attack_exp(t, note_dur, 0.0025, tau)
            bell = (
                math.sin(TAU * freq * t)
                + 0.22 * math.sin(TAU * (freq * 2.0) * t) * math.exp(-t / 0.032)
                + 0.06 * math.sin(TAU * (freq * 3.0) * t) * math.exp(-t / 0.016)
            )
            out[i] += amp * bell * env
    out[-1] = 0.0
    return sr, out


def build_security_beep(sr: int = 44100) -> tuple[int, list[float]]:
    """70 ms soft dual-tone ~880 -> 1175 Hz marimba/bell pip."""
    return _render_bell_notes(
        0.070,
        [
            (0.000, 880.00, 0.20, 0.014),
            (0.030, 1174.66, 0.22, 0.018),
        ],
        sr,
    )


def build_pa_chime(sr: int = 44100) -> tuple[int, list[float]]:
    """520 ms warm 3-note airport bell chime (C5-E5-G5)."""
    return _render_bell_notes(
        0.520,
        [
            (0.000, 523.25, 0.24, 0.110),
            (0.130, 659.25, 0.24, 0.110),
            (0.260, 783.99, 0.26, 0.150),
        ],
        sr,
    )


def build_pa_final_call(sr: int = 44100) -> tuple[int, list[float]]:
    """600 ms warm 4-note airport chime (G4-C5-E5-G5)."""
    return _render_bell_notes(
        0.600,
        [
            (0.000, 392.00, 0.22, 0.095),
            (0.115, 523.25, 0.23, 0.095),
            (0.230, 659.25, 0.24, 0.105),
            (0.345, 783.99, 0.27, 0.155),
        ],
        sr,
    )


def build_close_call_save(sr: int = 44100) -> tuple[int, list[float]]:
    """220 ms bright relief flourish glockenspiel (F5-A5-C6)."""
    return _render_bell_notes(
        0.220,
        [
            (0.000, 698.46, 0.22, 0.045),
            (0.055, 880.00, 0.23, 0.045),
            (0.110, 1046.50, 0.26, 0.065),
        ],
        sr,
    )


def build_joke_spill(sr: int = 44100) -> tuple[int, list[float]]:
    """210 ms soft bubbly splat + gentle descending woody slide."""
    dur = 0.210
    n = int(dur * sr)
    rng = random.Random(303)
    splash = _one_pole_lowpass([rng.uniform(-1.0, 1.0) for _ in range(n)], 1200.0, sr)
    splash = _one_pole_highpass(splash, 260.0, sr)
    out = [0.0] * n
    slide_phase = 0.0
    b1_phase = 0.0
    b2_phase = 0.0
    for i in range(n):
        t = i / sr
        slide_freq = 175.0 + 265.0 * math.exp(-t / 0.055)
        slide_phase += TAU * slide_freq / sr
        slide_env = _env_attack_exp(t, dur, 0.003, 0.065)
        splat = splash[i] * math.exp(-t / 0.022) * 0.28 * _env_attack_exp(t, dur, 0.002, 0.040)

        b1 = 0.0
        if t >= 0.020:
            bt1 = t - 0.020
            b1_freq = 640.0 - 260.0 * math.exp(-bt1 / 0.015)
            b1_phase += TAU * b1_freq / sr
            b1 = 0.20 * math.sin(b1_phase) * _env_attack_exp(bt1, dur - 0.020, 0.002, 0.018)

        b2 = 0.0
        if t >= 0.075:
            bt2 = t - 0.075
            b2_freq = 820.0 - 300.0 * math.exp(-bt2 / 0.014)
            b2_phase += TAU * b2_freq / sr
            b2 = 0.18 * math.sin(b2_phase) * _env_attack_exp(bt2, dur - 0.075, 0.002, 0.018)

        wood = 0.26 * (math.sin(slide_phase) + 0.15 * math.sin(3.9 * slide_phase)) * slide_env
        out[i] = wood + splat + b1 + b2
    out[-1] = 0.0
    return sr, out


def build_joke_fault(sr: int = 44100) -> tuple[int, list[float]]:
    """340 ms warm low marimba/brass power-down 'wah-wah-wah'."""
    dur = 0.340
    n = int(dur * sr)
    out = [0.0] * n
    steps = [
        (0.000, 0.095, 246.94, 0.28),
        (0.105, 0.095, 220.00, 0.28),
        (0.210, 0.130, 185.00, 0.30),
    ]
    for start_t, note_dur, freq, amp in steps:
        phase = 0.0
        for i in range(n):
            t = i / sr - start_t
            if t < 0.0 or t >= note_dur:
                continue
            sag_freq = freq * (1.0 - 0.055 * (t / note_dur))
            phase += TAU * sag_freq / sr
            env = _env_attack_exp(t, note_dur, 0.004, note_dur * 0.45)
            tone = (
                math.sin(phase)
                + 0.30 * math.sin(2.0 * phase) * math.exp(-t / 0.04)
                + 0.12 * math.sin(3.0 * phase) * math.exp(-t / 0.02)
            )
            out[i] += amp * tone * env
    out[-1] = 0.0
    return sr, out


def build_joke_queue_horn(sr: int = 44100) -> tuple[int, list[float]]:
    """260 ms gentle slightly detuned two-note Mini-Motorways-style cozy horn."""
    dur = 0.260
    n = int(dur * sr)
    out = [0.0] * n
    honks = [
        (0.000, 0.095, 329.63, 332.8, 0.22),
        (0.125, 0.135, 293.66, 296.4, 0.24),
    ]
    for start_t, note_dur, f1, f2, amp in honks:
        for i in range(n):
            t = i / sr - start_t
            if t < 0.0 or t >= note_dur:
                continue
            att = math.sin(0.5 * math.pi * min(1.0, t / 0.010))
            rel = 1.0
            rel_len = 0.024
            if t > note_dur - rel_len:
                rel = 0.5 + 0.5 * math.cos(math.pi * (t - (note_dur - rel_len)) / rel_len)
            env = att * rel
            horn = 0.55 * (
                math.sin(TAU * f1 * t)
                + math.sin(TAU * f2 * t)
                + 0.22 * math.sin(TAU * (f1 * 2.0) * t)
                + 0.12 * math.sin(TAU * (f2 * 3.0) * t)
            )
            out[i] += amp * horn * env
    out[-1] = 0.0
    return sr, out


def build_star_up(sr: int = 44100) -> tuple[int, list[float]]:
    """300 ms warm ascending chime (C5-E5-G5-C6)."""
    return _render_bell_notes(
        0.300,
        [
            (0.000, 523.25, 0.21, 0.050),
            (0.058, 659.25, 0.22, 0.050),
            (0.116, 783.99, 0.23, 0.055),
            (0.174, 1046.50, 0.26, 0.085),
        ],
        sr,
    )


def build_phone_ring(sr: int = 44100) -> tuple[int, list[float]]:
    """1920 ms two-ring double-trill desk/cellphone ring (G5 + C6 cozy dual-tone)."""
    dur = 1.920
    n = int(dur * sr)
    out = [0.0] * n
    bursts = [
        (0.000, 0.280, 0.018),
        (0.380, 0.340, 0.055),
        (1.150, 0.280, 0.018),
        (1.530, 0.340, 0.055),
    ]
    f1 = 783.99
    f2 = 1046.50
    for start_t, burst_dur, rel_len in bursts:
        for i in range(n):
            t = i / sr - start_t
            if t < 0.0 or t >= burst_dur:
                continue
            att = math.sin(0.5 * math.pi * min(1.0, t / 0.006))
            rel = 1.0
            if t > burst_dur - rel_len:
                rel = 0.5 + 0.5 * math.cos(math.pi * (t - (burst_dur - rel_len)) / rel_len)
            trill = 0.58 + 0.42 * math.sin(TAU * 20.0 * t)
            tone = (
                0.52 * math.sin(TAU * f1 * t)
                + 0.48 * math.sin(TAU * f2 * t)
                + 0.12 * math.sin(TAU * (f1 * 2.0) * t) * math.exp(-t / 0.07)
            )
            out[i] += 0.36 * tone * trill * att * rel
    out[-1] = 0.0
    return sr, out


def build_checkin_stamp(sr: int = 44100) -> tuple[int, list[float]]:
    """75 ms soft tactile desk stamp/thump."""
    dur = 0.075
    n = int(dur * sr)
    rng = random.Random(404)
    felt = _one_pole_lowpass([rng.uniform(-1.0, 1.0) for _ in range(n)], 1100.0, sr)
    out = [0.0] * n
    thump_phase = 0.0
    wood_phase = 0.0
    for i in range(n):
        t = i / sr
        thump_freq = 105.0 + 115.0 * math.exp(-t / 0.008)
        thump_phase += TAU * thump_freq / sr
        wood_phase += TAU * 315.0 / sr
        thump = math.sin(thump_phase) * math.exp(-t / 0.015)
        wood = 0.38 * math.sin(wood_phase) * math.exp(-t / 0.012)
        tap = 0.22 * felt[i] * math.exp(-t / 0.004)
        env = _env_attack_exp(t, dur, 0.0018, 0.022)
        out[i] = 0.28 * (thump + wood + tap) * env
    out[-1] = 0.0
    return sr, out


def build_security_alarm(sr: int = 44100) -> tuple[int, list[float]]:
    """210 ms unmistakable short double-beep security alert (distinct from clear chime)."""
    dur = 0.210
    n = int(dur * sr)
    out = [0.0] * n
    pips = [
        (0.000, 0.070, 740.0),
        (0.110, 0.075, 740.0),
    ]
    for start_t, pip_dur, freq in pips:
        for i in range(n):
            t = i / sr - start_t
            if t < 0.0 or t >= pip_dur:
                continue
            att = math.sin(0.5 * math.pi * min(1.0, t / 0.003))
            rel = 1.0
            rel_len = 0.010
            if t > pip_dur - rel_len:
                rel = 0.5 + 0.5 * math.cos(math.pi * (t - (pip_dur - rel_len)) / rel_len)
            tone = (
                math.sin(TAU * freq * t)
                + 0.12 * math.sin(TAU * (freq * 2.0) * t)
                + 0.18 * math.sin(TAU * (freq * 3.0) * t) * math.exp(-t / 0.030)
            )
            out[i] += 0.20 * tone * att * rel
    out[-1] = 0.0
    return sr, out


def build_security_clear(sr: int = 44100) -> tuple[int, list[float]]:
    """135 ms gentle positive two-note security clear chime (G5 -> C6)."""
    return _render_bell_notes(
        0.135,
        [
            (0.000, 783.99, 0.17, 0.024),
            (0.042, 1046.50, 0.19, 0.038),
        ],
        sr,
    )


def build_gate_chirp(sr: int = 44100) -> tuple[int, list[float]]:
    """85 ms crisp boarding-pass barcode-scanner chirp."""
    dur = 0.085
    n = int(dur * sr)
    out = [0.0] * n
    phase = 0.0
    for i in range(n):
        t = i / sr
        freq = 1661.22 - 486.56 * math.exp(-t / 0.014)
        phase += TAU * freq / sr
        tone = math.sin(phase) + 0.10 * math.sin(2.0 * phase) * math.exp(-t / 0.018)
        env = _env_attack_exp(t, dur, 0.0020, 0.022)
        out[i] = 0.18 * tone * env
    out[-1] = 0.0
    return sr, out


def build_cafe_clink(sr: int = 44100) -> tuple[int, list[float]]:
    """125 ms soft ceramic cup/saucer clink."""
    dur = 0.125
    n = int(dur * sr)
    out = [0.0] * n
    taps = [
        (0.000, 1.00),
        (0.034, 0.45),
    ]
    for start_t, weight in taps:
        for i in range(n):
            t = i / sr - start_t
            if t < 0.0:
                continue
            tap_dur = dur - start_t
            env = _env_attack_exp(t, tap_dur, 0.0012, 0.020)
            ceramic = (
                0.46 * math.sin(TAU * 1860.0 * t) * math.exp(-t / 0.015)
                + 0.34 * math.sin(TAU * 2790.0 * t) * math.exp(-t / 0.011)
                + 0.18 * math.sin(TAU * 3740.0 * t) * math.exp(-t / 0.007)
                + 0.26 * math.sin(TAU * 890.0 * t) * math.exp(-t / 0.006)
            )
            out[i] += 0.22 * weight * ceramic * env
    out[-1] = 0.0
    return sr, out


def build_staff_mumble(sr: int = 44100) -> tuple[int, list[float]]:
    """145 ms warm cozy two-syllable conversational staff mumble."""
    dur = 0.145
    n = int(dur * sr)
    rng = random.Random(505)
    breath = _one_pole_lowpass([rng.uniform(-1.0, 1.0) for _ in range(n)], 900.0, sr)
    breath = _one_pole_highpass(breath, 240.0, sr)
    out = [0.0] * n
    syllables = [
        (0.000, 0.058, 225.0, 265.0, 0.24),
        (0.072, 0.068, 250.0, 215.0, 0.20),
    ]
    for start_t, syl_dur, f0, f1, amp in syllables:
        phase = 0.0
        for i in range(n):
            t = i / sr - start_t
            if t < 0.0 or t >= syl_dur:
                continue
            u = t / syl_dur
            freq = f0 + (f1 - f0) * (0.5 - 0.5 * math.cos(math.pi * u))
            phase += TAU * freq / sr
            formant = (
                0.68 * math.sin(phase)
                + 0.28 * math.sin(2.0 * phase)
                + 0.12 * math.sin(3.0 * phase)
            )
            env = math.sin(math.pi * min(1.0, max(0.0, u))) ** 1.15
            out[i] += amp * (formant + 0.12 * breath[i]) * env
    out[-1] = 0.0
    return sr, out


def build_staff_sip(sr: int = 44100) -> tuple[int, list[float]]:
    """140 ms soft ceramic mug tap and warm coffee sip."""
    dur = 0.140
    n = int(dur * sr)
    rng = random.Random(606)
    sip_air = _one_pole_lowpass([rng.uniform(-1.0, 1.0) for _ in range(n)], 1700.0, sr)
    sip_air = _one_pole_highpass(sip_air, 520.0, sr)
    out = [0.0] * n
    sip_phase = 0.0
    for i in range(n):
        t = i / sr
        sip_freq = 440.0 + 170.0 * (1.0 - math.exp(-t / 0.045))
        sip_phase += TAU * sip_freq / sr
        sip_env = _env_attack_exp(t, dur, 0.014, 0.042)
        sip = (0.20 * sip_air[i] + 0.10 * math.sin(sip_phase)) * sip_env
        clink = 0.0
        if t >= 0.075:
            ct = t - 0.075
            c_env = _env_attack_exp(ct, dur - 0.075, 0.0015, 0.016)
            clink = 0.14 * (
                0.60 * math.sin(TAU * 1680.0 * ct) + 0.40 * math.sin(TAU * 2520.0 * ct)
            ) * c_env
        out[i] = sip + clink
    out[-1] = 0.0
    return sr, out


def build_staff_cheer(sr: int = 44100) -> tuple[int, list[float]]:
    """210 ms warm upbeat celebratory mini-cheer chime (E5 -> G#5 -> B5)."""
    return _render_bell_notes(
        0.210,
        [
            (0.000, 659.25, 0.19, 0.032),
            (0.055, 830.61, 0.21, 0.038),
            (0.110, 987.77, 0.24, 0.056),
        ],
        sr,
    )


def build_staff_wipe(sr: int = 44100) -> tuple[int, list[float]]:
    """155 ms soft two-stroke counter cloth wipe."""
    dur = 0.155
    n = int(dur * sr)
    rng = random.Random(707)
    cloth = _one_pole_lowpass([rng.uniform(-1.0, 1.0) for _ in range(n)], 1850.0, sr)
    cloth = _one_pole_highpass(cloth, 420.0, sr)
    out = [0.0] * n
    strokes = [
        (0.000, 0.068, 0.30),
        (0.078, 0.072, 0.25),
    ]
    for start_t, st_dur, amp in strokes:
        for i in range(n):
            t = i / sr - start_t
            if t < 0.0 or t >= st_dur:
                continue
            u = t / st_dur
            env = math.sin(math.pi * min(1.0, max(0.0, u)))
            out[i] += amp * cloth[i] * env
    out[-1] = 0.0
    return sr, out


def build_staff_yawn(sr: int = 44100) -> tuple[int, list[float]]:
    """280 ms gentle descending cozy tired yawn-sigh hum."""
    dur = 0.280
    n = int(dur * sr)
    rng = random.Random(808)
    sigh = _one_pole_lowpass([rng.uniform(-1.0, 1.0) for _ in range(n)], 950.0, sr)
    sigh = _one_pole_highpass(sigh, 210.0, sr)
    out = [0.0] * n
    phase = 0.0
    for i in range(n):
        t = i / sr
        u = t / dur
        freq = 330.0 - 135.0 * (0.5 - 0.5 * math.cos(math.pi * u))
        phase += TAU * freq / sr
        hum = 0.65 * math.sin(phase) + 0.24 * math.sin(2.0 * phase)
        env = math.sin(math.pi * min(1.0, max(0.0, u))) ** 1.3
        out[i] = 0.22 * (hum + 0.18 * sigh[i]) * env
    out[-1] = 0.0
    return sr, out


def main() -> None:
    builders = {
        "terminal_ambience.wav": build_terminal_ambience,
        "ui_click.wav": build_ui_click,
        "build_place.wav": build_place_sfx,
        "build_remove.wav": build_remove_sfx,
        "build_refuse.wav": build_refuse_sfx,
        "cash_chime.wav": build_cash_chime,
        "security_beep.wav": build_security_beep,
        "pa_chime.wav": build_pa_chime,
        "pa_final_call.wav": build_pa_final_call,
        "close_call_save.wav": build_close_call_save,
        "joke_spill.wav": build_joke_spill,
        "joke_fault.wav": build_joke_fault,
        "joke_queue_horn.wav": build_joke_queue_horn,
        "star_up.wav": build_star_up,
        "phone_ring.wav": build_phone_ring,
        "checkin_stamp.wav": build_checkin_stamp,
        "security_alarm.wav": build_security_alarm,
        "security_clear.wav": build_security_clear,
        "gate_chirp.wav": build_gate_chirp,
        "cafe_clink.wav": build_cafe_clink,
        "staff_mumble.wav": build_staff_mumble,
        "staff_sip.wav": build_staff_sip,
        "staff_cheer.wav": build_staff_cheer,
        "staff_wipe.wav": build_staff_wipe,
        "staff_yawn.wav": build_staff_yawn,
    }
    ogg_builders = {
        "terminal_ambience_bed.ogg": build_terminal_ambience_bed,
        "terminal_lounge.ogg": build_terminal_lounge_music,
        "music_morning_bossa.ogg": build_morning_bossa_music,
        "music_sunny_marimba.ogg": build_sunny_marimba_music,
        "music_breezy_stroll.ogg": build_breezy_stroll_music,
        "music_sunset_acoustic.ogg": build_sunset_acoustic_music,
    }
    only: str | None = None
    if "--only" in sys.argv:
        idx = sys.argv.index("--only")
        if idx + 1 >= len(sys.argv):
            raise SystemExit("--only requires a filename")
        only = sys.argv[idx + 1]
    for filename, fn in builders.items():
        if only is not None and filename != only:
            continue
        sr, samples = fn()
        target = OUT_DIR / filename
        _write_wav(target, sr, samples)
        boundary_delta = abs(samples[0] - samples[-1]) if samples else 0.0
        size_kb = target.stat().st_size / 1024.0
        print(
            f"wrote {target.relative_to(REPO_ROOT)} "
            f"({len(samples)} samples @ {sr} Hz, {size_kb:.1f} KB, boundary_delta={boundary_delta:.5f})"
        )
    for filename, fn in ogg_builders.items():
        if only is not None and filename != only:
            continue
        track_sr, track_l, track_r, stats = fn()
        if stats["has_nan"]:
            raise RuntimeError(f"{filename}: generated audio contains NaN/Inf")
        if stats["peak_db"] > -1.0:
            raise RuntimeError(f"{filename}: peak {stats['peak_db']:.2f} dBFS exceeds -1.0 dBFS")
        target = OUT_DIR / filename
        encoder = _encode_ogg_from_stereo(target, track_sr, track_l, track_r, bitrate_kbps=160)
        size_kb = target.stat().st_size / 1024.0
        if size_kb <= 1.0:
            raise RuntimeError(f"{filename}: encoded file unexpectedly tiny ({size_kb:.1f} KB)")
        print(
            f"wrote {target.relative_to(REPO_ROOT)} "
            f"({stats['samples']} samples @ {stats['sample_rate']} Hz stereo, "
            f"{stats['duration_s']:.2f} s, {size_kb:.1f} KB, encoder={encoder}, "
            f"peak={stats['peak_db']:.2f} dBFS, rms={stats['rms_db']:.2f} dBFS, "
            f"dc=({stats['dc_l']:.6f}, {stats['dc_r']:.6f}), "
            f"end_amp={stats['end_amp']:.6f})"
        )


if __name__ == "__main__":
    main()
