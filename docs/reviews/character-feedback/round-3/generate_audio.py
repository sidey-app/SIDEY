#!/usr/bin/env python3
"""Original synthesis for review: longer arcade growth + all seven remaining objects."""
import array
import hashlib
import json
import math
from pathlib import Path
import random
import shutil
import sys
import wave

ROOT = Path(__file__).resolve().parent
RATE = 48000
TAU = 2 * math.pi
PEAK_LIMIT = 10 ** (-14 / 20)
NOTES = [392, 523.25, 783.99, 1046.50]
GROW_HOLDS = [[.09, .09, .09, .09], [.12, .12, .12, .12], [.11, .11, .11, .29]]

GROUPS = [
    {"id": "grow", "label": "확대 · C를 더 길게", "description": "같은 8비트 음색과 네 음을 유지하고, 음 하나하나의 길이와 마지막 음의 여운을 비교합니다.", "kind": "grow", "object_id": None,
     "candidates": [("C-1", .36, "또렷하게 · 각 음 90ms, 기존보다 1.5배 길게"), ("C-2", .48, "여유 있게 · 각 음 120ms, 기존보다 2배 길게"), ("C-3", .62, "끝음을 길게 · 앞 세 음 110ms, 마지막 음 290ms")]},
    {"id": "patch_soft_ball", "label": "말랑공 · 선택한 C", "description": "2차에서 고른 C를 파일·음량 그대로 유지했습니다. 다른 투척물의 기준 소리입니다.", "kind": "hit", "object_id": "patch_soft_ball", "candidates": []},
    {"id": "mini_paprika", "label": "미니 파프리카", "description": "작고 단단한 장난감 채소가 닿는 가벼운 타격감.", "kind": "hit", "object_id": "mini_paprika",
     "candidates": [("A", .14, "또각 · 짧고 맑은 나무 장난감 질감"), ("B", .20, "톡톡 · 가볍게 두 번 튕기는 질감"), ("C", .16, "탁! · 조금 더 선명하고 바삭한 접촉")]},
    {"id": "banana", "label": "바나나", "description": "말랑공보다 조금 더 눌리고 찰진 고무 질감.", "kind": "hit", "object_id": "banana",
     "candidates": [("A", .20, "뿍 · 부드럽게 눌렸다 튀는 소리"), ("B", .24, "뿌잉 · 탄성이 한 번 더 살아나는 소리"), ("C", .17, "찹! · 짧고 찰진 말랑 장난감")]},
    {"id": "dust_bath_pouch", "label": "먼지목욕 모래주머니", "description": "높은 전자음보다 짧고 보송한 모래·천의 질감.", "kind": "hit", "object_id": "dust_bath_pouch",
     "candidates": [("A", .23, "푸슥 · 폭신한 모래주머니"), ("B", .28, "푸슈슥 · 작은 모래가 두 번 흩어지는 느낌"), ("C", .18, "사삭 · 더 가볍고 입자가 또렷한 느낌")]},
    {"id": "starlight_orb", "label": "별빛 구슬", "description": "작은 구슬의 둥근 충격 뒤에 짧은 빛의 여운.", "kind": "hit", "object_id": "starlight_orb",
     "candidates": [("A", .28, "똑띵 · 둥근 충격과 한 번의 반짝임"), ("B", .32, "띠링 · 맑은 유리 구슬 느낌"), ("C", .26, "또롱 · 부드럽고 따뜻한 작은 차임")]},
    {"id": "throwable_bouncy_heart", "label": "통통 하트", "description": "말랑한 탄성과 두근거리는 리듬을 가볍게.", "kind": "hit", "object_id": "throwable_bouncy_heart",
     "candidates": [("A", .23, "뽀잉 · 부드러운 젤리 탄성"), ("B", .27, "뽁뿅 · 두근두근 두 번 튀는 하트"), ("C", .20, "뾰옹 · 조금 더 밝게 튀는 하트")]},
    {"id": "throwable_toy_cannon", "label": "미니 대포", "description": "위협적인 폭발 대신 낮고 둥근 장난감 대포의 충돌음. 발사음은 아닙니다.", "kind": "hit", "object_id": "throwable_toy_cannon",
     "candidates": [("A", .22, "퐁 · 둥근 공기 대포"), ("B", .28, "뽕 · 조금 더 낮고 푹신한 충격"), ("C", .18, "팡! · 짧고 경쾌한 장난감 충격")]},
    {"id": "throwable_squeaky_duck", "label": "삑삑 오리", "description": "짧게 눌리는 고무 오리 특유의 코맹맹이 질감.", "kind": "hit", "object_id": "throwable_squeaky_duck",
     "candidates": [("A", .18, "삑 · 짧고 또렷한 고무 오리"), ("B", .26, "삑삑 · 높이가 달라지는 두 번의 소리"), ("C", .23, "뀩 · 고무가 눌렸다 풀리는 탄성")]},
]


def finish(samples, soften_transients=False):
    count = len(samples)
    for i in range(count):
        samples[i] *= min(1, i / (RATE * .003)) * min(1, (count - 1 - i) / (RATE * .012))
    if soften_transients:
        # Tame short peaks so cloth/wood/air candidates remain audible at the same review level.
        peak = max(abs(x) for x in samples)
        samples = [math.tanh(3 * x / peak) for x in samples]
    rms = math.sqrt(sum(x * x for x in samples) / count)
    gain = min(.073 / rms, PEAK_LIMIT / max(abs(x) for x in samples))
    return [x * gain for x in samples]


def synth_grow(variant):
    holds = GROW_HOLDS[variant]
    phase = 0.0
    samples = []
    for note, (hz, duration) in enumerate(zip(NOTES, holds)):
        count = round(duration * RATE)
        for i in range(count):
            phase += TAU * hz / RATE
            square = sum(math.sin(phase * h) / h for h in (1, 3, 5, 7))
            # Full sustained notes with 3ms edge smoothing, not a long silent gate.
            gate = min(1, i / (RATE * .003)) * min(1, (count - 1 - i) / (RATE * .004))
            tail = 1.0
            if variant == 2 and note == 3:
                tail = .68 + .32 * math.exp(-5 * i / RATE)
            samples.append(square * gate * tail * (.86 if note < 3 else 1))
    return finish(samples)


def synth_object(object_id, variant, duration):
    seed = int.from_bytes(hashlib.sha256(f"{object_id}:{variant}".encode()).digest()[:8], "big")
    rng = random.Random(seed)
    phase = 0.0
    noise_low = 0.0
    noise_slow = 0.0
    samples = []
    for i in range(round(duration * RATE)):
        t = i / RATE
        u = t / duration
        noise_low += .13 * (rng.uniform(-1, 1) - noise_low)
        noise_slow += .025 * (noise_low - noise_slow)
        value = 0.0
        if object_id == "mini_paprika":
            offsets = [(0, 690, 1)] if variant != 1 else [(0, 620, 1), (.085, 880, .80)]
            for offset, hz, gain in offsets:
                age = t - offset
                if age >= 0:
                    env = min(1, age / .002) * math.exp(-[32, 37, 40][variant] * age)
                    wood = math.sin(TAU * hz * age) + .3 * math.sin(TAU * hz * 2.63 * age)
                    value += gain * env * wood
            value += [1.3, .45, 2.8][variant] * noise_low * math.exp(-65 * t)
        elif object_id == "banana":
            hz = [260, 310, 390][variant] + [260, 410, 310][variant] * u ** .65
            phase += TAU * hz / RATE
            squish = math.sin(phase + [.38, .72, .28][variant] * math.sin(phase))
            envelope = math.sin(math.pi * u) ** .65 * math.exp(-.65 * u)
            if variant == 1:
                envelope *= .72 + .28 * math.cos(TAU * 7 * t)
            value = squish * envelope + [1, .35, 2.8][variant] * noise_low * math.exp(-30 * t)
        elif object_id == "dust_bath_pouch":
            env = (1 - math.exp(-t * 130)) * math.exp(-[20, 15, 28][variant] * t)
            texture = noise_slow * 5 if variant == 0 else noise_low * [0, 3.8, 5.0][variant]
            if variant == 1:
                env *= .30 + .70 * math.sin(math.pi * u * 2) ** 2
            if variant == 2:
                texture *= .55 + .45 * math.sin(TAU * 43 * t) ** 2
            thud = .14 * math.sin(TAU * 240 * t) * math.exp(-35 * t)
            value = texture * env + thud
        elif object_id == "starlight_orb":
            sets = [[(0, 620, 1), (.035, 1240, .35)], [(0, 1046.5, .85), (.06, 1568, .55)], [(0, 740, 1), (.065, 987.8, .65)]]
            for offset, hz, gain in sets[variant]:
                age = t - offset
                if age >= 0:
                    bell = math.sin(TAU * hz * age) + [.12, .26, .045][variant] * math.sin(TAU * hz * 2.76 * age)
                    value += gain * bell * min(1, age / .002) * math.exp(-[15, 12, 17][variant] * age)
            value += .18 * math.sin(TAU * 350 * t) * math.exp(-55 * t)
        elif object_id == "throwable_bouncy_heart":
            offsets = [0, .105] if variant == 1 else [0]
            for n, offset in enumerate(offsets):
                age = t - offset
                length = duration - offset if len(offsets) == 1 else (.10 if n == 0 else duration - offset)
                if not 0 <= age < length:
                    continue
                local = age / length
                start = [440, 420, 610][variant] + 260 * n
                end = start + [320, 250, 400][variant]
                p = TAU * (start * age + (end - start) * age * age / (2 * length))
                rubber = math.sin(p) + .09 * math.sin(2 * p)
                value += rubber * math.sin(math.pi * local) ** .6 * math.exp(-.5 * local)
        elif object_id == "throwable_toy_cannon":
            start, end = [(130, 210), (92, 145), (190, 280)][variant]
            p = TAU * (start * t + (end - start) * t * t / (2 * duration))
            air = (noise_slow * 8 + noise_low * .4) * math.exp(-[19, 16, 27][variant] * t)
            pop = math.sin(p) * math.exp(-[16, 13, 21][variant] * t)
            tick = .10 * math.sin(TAU * 900 * t) * math.exp(-80 * t)
            value = pop + [.45, .6, 1.0][variant] * air + tick
        elif object_id == "throwable_squeaky_duck":
            offset = .13 if variant == 1 and t >= .13 else 0
            age = t - offset
            length = .12 if variant == 1 else duration
            local = min(1, age / length)
            hz = [740, 630, 530][variant] + [180, 180, 430][variant] * local + (160 if offset else 0)
            if variant == 2:
                hz += 32 * math.sin(TAU * 17 * t)
            phase += TAU * hz / RATE
            nasal = math.sin(phase) + .29 * math.sin(3 * phase) + .12 * math.sin(5 * phase)
            envelope = math.sin(math.pi * local) ** [.5, .65, .85][variant]
            value = nasal * envelope
        else:
            raise ValueError(object_id)
        samples.append(value)
    return finish(samples, soften_transients=True)


def save_wav(path, samples):
    values = array.array("h", (round(max(-1, min(1, x)) * 32767) for x in samples))
    if sys.byteorder != "little":
        values.byteswap()
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(values.tobytes())


def read_wav(path):
    with wave.open(str(path), "rb") as source:
        values = array.array("h", source.readframes(source.getnframes()))
    if sys.byteorder != "little":
        values.byteswap()
    return [value / 32767 for value in values]


def repeated(samples, interval):
    count = max(RATE * 2, round((.15 + 2 * interval + len(samples) / RATE + .15) * RATE))
    output = [0.0] * count
    for n in range(3):
        offset = round((.15 + interval * n) * RATE)
        output[offset:offset + len(samples)] = samples
    return output


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    output = ROOT / "audio"
    output.mkdir(exist_ok=True)
    records = []
    groups = []
    for definition in GROUPS:
        group = {key: value for key, value in definition.items() if key != "candidates"}
        group_samples = []
        if group["id"] == "patch_soft_ball":
            previous = ROOT.parent / "round-2/audio/hit-c-v2.wav"
            single = output / "hit-c-v2.wav"
            shutil.copyfile(previous, single)
            specs = [("C", .18, "선택한 2차 C · 파일과 음량 그대로", "hit-c-v2", read_wav(single))]
        else:
            specs = []
            for variant, (label, duration, description) in enumerate(definition["candidates"]):
                samples = synth_grow(variant) if group["kind"] == "grow" else synth_object(group["id"], variant, duration)
                identifier = f"{group['id']}-{label.lower()}-v3"
                specs.append((label, duration, description, identifier, samples))
        for variant, (label, duration, description, identifier, samples) in enumerate(specs):
            single = output / f"{identifier}.wav"
            if group["id"] != "patch_soft_ball":
                save_wav(single, samples)
            quantized = read_wav(single)
            interval = 1.0 if group["kind"] == "grow" else .5
            repeat = output / f"{identifier}-repeat.wav"
            save_wav(repeat, repeated(quantized, interval))
            title = "확대 " + label if group["kind"] == "grow" else group["label"].split(" · ")[0] + " " + label
            item = {"id": identifier, "group_id": group["id"], "kind": group["kind"], "object_id": group["object_id"],
                    "label": title, "option": label, "description": description, "duration_seconds": duration,
                    "sample_rate": RATE, "channels": 1, "bit_depth": 16, "file": f"audio/{single.name}",
                    "repeat_file": f"audio/{repeat.name}", "repeat_interval_seconds": interval,
                    "sha256": sha(single), "repeat_sha256": sha(repeat),
                    "approval": "approved" if group["id"] == "patch_soft_ball" else "pending",
                    "selection": "chosen_round_2" if group["id"] == "patch_soft_ball" else "pending",
                    "peak_dbfs": round(20 * math.log10(max(abs(x) for x in quantized)), 2),
                    "rms_dbfs": round(20 * math.log10(math.sqrt(sum(x*x for x in quantized) / len(quantized))), 2),
                    "provenance": "Original deterministic synthesis; no external recordings."}
            if group["kind"] == "grow":
                item.update({"parent_candidate": "grow-c-v2", "note_frequencies_hz": NOTES, "note_durations_seconds": GROW_HOLDS[variant]})
            if group["id"] == "patch_soft_ball":
                item["approval_evidence"] = "2026-09-09: 사용자가 2차 말랑공·확대 모두 C를 선택하고 확대만 추가 수정을 요청함. 말랑공 파일은 변경하지 않음."
            records.append(item)
            group_samples.append(quantized)
        if len(group_samples) > 1:
            sequence = [0.0] * round(.15 * RATE)
            for samples in group_samples:
                sequence.extend(samples)
                sequence.extend([0.0] * round(.55 * RATE))
            comparison = output / f"{group['id']}-comparison-v3.wav"
            save_wav(comparison, sequence)
            group.update({"comparison_file": f"audio/{comparison.name}", "comparison_sha256": sha(comparison)})
        groups.append(group)
    manifest = {"review_round": 3, "approval": "pending", "groups": groups, "sounds": records,
                "visual_review": "../round-2/index.html#visual-heading", "visual_status": "unchanged_pending_approval"}
    (ROOT / "audio-manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    (ROOT / "review-data.js").write_text("globalThis.sideyAudioCandidates = " + json.dumps(manifest, ensure_ascii=False, indent=2) + ";\n")
    print(f"Created {len(records)} candidates across {len(groups)} groups (24 new, selected ball C preserved).")


if __name__ == "__main__":
    main()
