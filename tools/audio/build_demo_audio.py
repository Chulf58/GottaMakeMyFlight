#!/usr/bin/env python3
"""Deterministic procedural WAV synthesizer for the D5 demo audio floor and PA cues.

Generates compact, click-free 16-bit PCM WAV assets under game/assets/audio/:
  - terminal_ambience.wav (14.0 s seamless loop, 22050 Hz mono)
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
"""

from __future__ import annotations

import math
import random
import struct
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
    }
    for filename, fn in builders.items():
        sr, samples = fn()
        target = OUT_DIR / filename
        _write_wav(target, sr, samples)
        boundary_delta = abs(samples[0] - samples[-1]) if samples else 0.0
        size_kb = target.stat().st_size / 1024.0
        print(
            f"wrote {target.relative_to(REPO_ROOT)} "
            f"({len(samples)} samples @ {sr} Hz, {size_kb:.1f} KB, boundary_delta={boundary_delta:.5f})"
        )


if __name__ == "__main__":
    main()
