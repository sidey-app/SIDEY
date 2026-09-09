#!/usr/bin/env python3
"""Deterministic, original synthesis for review only; no app resources are touched."""
import array
import hashlib
import json
import math
from pathlib import Path
import random
import sys
import wave

ROOT = Path(__file__).resolve().parent
RATE = 48_000
TAU = 2 * math.pi
PEAK_LIMIT = 10 ** (-14 / 20)


def synth_hit(variant, duration):
    """Upward rubber pops; amplitude fades, but pitch never drops into a low tail."""
    phase = 0.0
    samples = []
    count = round(RATE * duration)
    for index in range(count):
        t = index / RATE
        u = t / duration
        attack = min(1.0, t / 0.003)
        tail = min(1.0, max(0.0, (duration - t - 1 / RATE) / 0.010))
        if variant == 0:
            # One compact, ascending elastic pop, without a drawn-out whistle.
            hz = 340 + 460 * min(1.0, u / .80) ** .70
            envelope = math.exp(-9 * t)
            harmonic = .14
        elif variant == 1:
            # Two rebounds: the second is shorter and higher, never a downward boing.
            second = t >= .095
            local = (t - .095) / (duration - .095) if second else t / .095
            hz = (630 + 240 * local) if second else (330 + 220 * local)
            envelope = math.sin(math.pi * local) ** .8 * (0.92 if second else 1.0)
            harmonic = .12
        else:
            # A softer bubble with a bright, brief finish; no subharmonic or falling vibrato.
            hz = 440 + 390 * (u * u * (3 - 2 * u))
            envelope = math.sin(math.pi * u) ** .55 * math.exp(-.6 * u)
            harmonic = .07
        phase += TAU * hz / RATE
        body = math.sin(phase) + harmonic * math.sin(2 * phase) + .035 * math.sin(3 * phase)
        samples.append(body * envelope * attack * tail)
    rms = math.sqrt(sum(x * x for x in samples) / count)
    gain = min(0.073 / rms, PEAK_LIMIT / max(abs(x) for x in samples))
    return [x * gain for x in samples]


def synth_grow(variant, duration):
    """Three separate palettes: rubber toy, bell magic, and a square-wave arcade cue."""
    rng = random.Random(20260909)
    phase = 0.0
    smooth_noise = 0.0
    samples = []
    for index in range(round(RATE * duration)):
        t = index / RATE
        u = t / duration
        tail = min(1.0, max(0.0, (duration - t - 1 / RATE) / .014))
        attack = min(1.0, t / .003)
        if variant == 0:
            # A resonant balloon squeak with airy rubber texture and a pronounced swell.
            hz = 180 + 510 * u ** .75
            phase += TAU * hz / RATE
            smooth_noise += .09 * (rng.uniform(-1, 1) - smooth_noise)
            body = math.sin(phase + .55 * math.sin(phase)) + .15 * math.sin(phase * 2)
            body += .32 * smooth_noise
            value = body * math.sin(math.pi * u) ** .7
        elif variant == 1:
            # Inharmonic bell partials, three ascending notes, naturally overlapping decays.
            value = 0.0
            for offset, hz, strength in [(0.0, 660, .9), (.085, 880, .8), (.17, 1320, .72)]:
                age = t - offset
                if age < 0:
                    continue
                envelope = min(1.0, age / .002) * math.exp(-11 * age)
                bell = math.sin(TAU * hz * age)
                bell += .22 * math.sin(TAU * hz * 2.76 * age) * math.exp(-15 * age)
                bell += .06 * math.sin(TAU * hz * 5.4 * age) * math.exp(-24 * age)
                value += strength * envelope * bell
        else:
            # Discrete arcade steps with silent gaps; no smooth glissando or bell tail.
            note_length = duration / 4
            note = min(3, int(t / note_length))
            local = (t - note * note_length) / note_length
            hz = [392, 523.25, 783.99, 1046.50][note]
            phase += TAU * hz / RATE
            square = sum(math.sin(phase * harmonic) / harmonic for harmonic in (1, 3, 5, 7))
            gate = min(1.0, local / .07) * max(0.0, min(1.0, (.86 - local) / .13))
            value = square * gate * (.86 if note < 3 else 1.0)
        samples.append(value * attack * tail)
    rms = math.sqrt(sum(x * x for x in samples) / len(samples))
    gain = min(.073 / rms, PEAK_LIMIT / max(abs(x) for x in samples))
    return [x * gain for x in samples]


def save_wav(path, samples):
    pcm = array.array("h", (round(max(-1, min(1, x)) * 32767) for x in samples))
    if sys.byteorder != "little":
        pcm.byteswap()
    with wave.open(str(path), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(pcm.tobytes())


def repeated(samples):
    result = [0.0] * (RATE * 2)
    for start in (0.15, 0.65, 1.15):
        index = round(start * RATE)
        result[index:index + len(samples)] = samples
    return result


def main():
    output = ROOT / "audio"
    output.mkdir(exist_ok=True)
    specs = [
        ("hit", 0, .15, "말랑공 A · V2", "통! · 짧고 밝게 튀어 오르는 한 번의 탄성"),
        ("hit", 1, .20, "말랑공 B · V2", "뽀뿅! · 두 번째 음이 더 높아지는 두 번의 탄성"),
        ("hit", 2, .18, "말랑공 C · V2", "뽁! · 부드럽게 부풀고 밝게 마무리"),
        ("grow", 0, .38, "확대 A · 풍선 장난감", "뽀요옹 · 공기가 차오르는 말랑한 고무 질감"),
        ("grow", 1, .42, "확대 B · 반짝 마법", "띠리링 · 세 음이 겹치며 반짝이는 작은 종소리"),
        ("grow", 2, .24, "확대 C · 8비트 레벨업", "또로롱! · 짧게 끊어 올라가는 픽셀 게임 소리"),
    ]
    records = []
    for kind, variant, duration, title, description in specs:
        name = f"{kind}-{chr(97 + variant)}-v2"
        samples = synth_hit(variant, duration) if kind == "hit" else synth_grow(variant, duration)
        single = output / f"{name}.wav"
        repeat = output / f"{name}-repeat.wav"
        save_wav(single, samples)
        save_wav(repeat, repeated(samples))
        records.append({
            "id": name, "kind": kind, "label": title, "description": description,
            "duration_seconds": duration, "sample_rate": RATE, "channels": 1,
            "bit_depth": 16, "file": f"audio/{single.name}",
            "repeat_file": f"audio/{repeat.name}", "approval": "pending",
            "sha256": hashlib.sha256(single.read_bytes()).hexdigest(),
            "repeat_sha256": hashlib.sha256(repeat.read_bytes()).hexdigest(),
            "peak_dbfs": round(20 * math.log10(max(abs(x) for x in samples)), 2),
            "rms_dbfs": round(20 * math.log10(math.sqrt(sum(x*x for x in samples)/len(samples))), 2),
            "provenance": "Original deterministic oscillator/noise synthesis; no sampled recordings.",
            "pitch_direction": "ascending",
            "sound_palette": "rubber_pop" if kind == "hit" else ["inflating_rubber_toy", "inharmonic_magic_bells", "stepped_arcade_square"][variant],
        })
    manifest = {"review_round": 2, "approval": "pending", "sounds": records}
    (ROOT / "audio-manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    (ROOT / "review-data.js").write_text("globalThis.sideyAudioCandidates = " + json.dumps(manifest, ensure_ascii=False, indent=2) + ";\n")
    print(f"Created {len(records)} candidates and 0.5-second-interval repeat clips.")


if __name__ == "__main__":
    main()
