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


def synth(kind, variant, duration):
    rng = random.Random(20260909 + variant + (100 if kind == "grow" else 0))
    phase = 0.0
    filtered_noise = 0.0
    samples = []
    count = round(RATE * duration)
    for index in range(count):
        t = index / RATE
        u = t / duration
        attack = min(1.0, t / 0.004)
        tail = min(1.0, max(0.0, (duration - t - 1 / RATE) / 0.018))
        filtered_noise += 0.065 * (rng.uniform(-1, 1) - filtered_noise)
        if kind == "hit":
            initial, end, decay = [(620, 155, 32), (430, 125, 23), (810, 245, 28)][variant]
            hz = end + (initial - end) * math.exp(-decay * t)
            phase += TAU * hz / RATE
            body = math.sin(phase) + 0.12 * math.sin(2 * phase) * math.exp(-35 * t)
            body += (0.12 if variant == 1 else 0.055) * filtered_noise * math.exp(-45 * t)
            envelope = math.exp(-[19, 17, 22][variant] * t)
        else:
            initial, end = [(210, 790), (250, 960), (175, 660)][variant]
            rise = min(1.0, u / 0.66)
            ease = rise * rise * (3 - 2 * rise)
            hz = initial + (end - initial) * ease
            hz *= 1 + (0.028 if variant != 2 else 0.015) * math.sin(TAU * 11 * t)
            phase += TAU * hz / RATE
            body = math.sin(phase + 0.18 * math.sin(phase / 2))
            body += [0.1, 0.18, 0.04][variant] * math.sin(2 * phase)
            body += 0.03 * filtered_noise
            envelope = math.sin(math.pi * u) ** 0.85 * math.exp(-1.7 * u)
        samples.append(body * envelope * attack * tail)
    rms = math.sqrt(sum(x * x for x in samples) / count)
    gain = min(0.073 / rms, PEAK_LIMIT / max(abs(x) for x in samples))
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
        ("hit", 0, .19, "말랑공 A", "둥근 뽁 · 가볍고 짧은 탄성"),
        ("hit", 1, .22, "말랑공 B", "낮은 푹 · 조금 더 푹신한 질감"),
        ("hit", 2, .18, "말랑공 C", "작은 뿍 · 조금 더 또렷한 탄성"),
        ("grow", 0, .32, "확대 A", "둥근 뿅 · 부드럽게 올라가는 음"),
        ("grow", 1, .28, "확대 B", "밝은 뾰용 · 조금 더 빠른 상승"),
        ("grow", 2, .34, "확대 C", "낮은 부웅 · 차분하게 부푸는 음"),
    ]
    records = []
    for kind, variant, duration, title, description in specs:
        name = f"{kind}-{chr(97 + variant)}-v1"
        samples = synth(kind, variant, duration)
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
        })
    manifest = {"review_round": 1, "approval": "pending", "sounds": records}
    (ROOT / "audio-manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    (ROOT / "review-data.js").write_text("globalThis.sideyAudioCandidates = " + json.dumps(manifest, ensure_ascii=False, indent=2) + ";\n")
    print(f"Created {len(records)} candidates and 0.5-second-interval repeat clips.")


if __name__ == "__main__":
    main()
