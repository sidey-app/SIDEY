#!/usr/bin/env python3
"""Verify the delivered PCM, selected source bytes, coverage, holds and review links."""
import array
from collections import Counter
import hashlib
from html.parser import HTMLParser
import json
import math
from pathlib import Path
import sys
import wave

ROOT = Path(__file__).resolve().parent
RATE = 48000


def pcm(path):
    with wave.open(str(path), "rb") as audio:
        assert (audio.getnchannels(), audio.getsampwidth(), audio.getframerate()) == (1, 2, RATE), path
        values = array.array("h", audio.readframes(audio.getnframes()))
    if sys.byteorder != "little":
        values.byteswap()
    return values


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    manifest = json.loads((ROOT / "audio-manifest.json").read_text())
    assert manifest["review_round"] == 3 and manifest["approval"] == "pending"
    sounds = manifest["sounds"]
    assert len(sounds) == 25 and len({item["sha256"] for item in sounds}) == 25
    assert len(list((ROOT / "audio").glob("*.wav"))) == 58
    expected = {"grow", "patch_soft_ball", "mini_paprika", "banana", "dust_bath_pouch", "starlight_orb", "throwable_bouncy_heart", "throwable_toy_cannon", "throwable_squeaky_duck"}
    counts = Counter(item["group_id"] for item in sounds)
    assert set(counts) == expected
    assert all(count == (1 if group == "patch_soft_ball" else 3) for group, count in counts.items())
    catalogue = json.loads((ROOT.parents[3] / "assets/v1/manifest.json").read_text())
    assert {item["object_id"] for item in sounds if item["kind"] == "hit"} == {item["id"] for item in catalogue["throwables"]}
    minimum_rms = 1.0
    for item in sounds:
        single, repeat = ROOT / item["file"], ROOT / item["repeat_file"]
        assert sha(single) == item["sha256"] and sha(repeat) == item["repeat_sha256"]
        samples, repetitions = pcm(single), pcm(repeat)
        assert len(samples) == round(item["duration_seconds"] * RATE), item["id"]
        assert samples[0] == samples[-1] == 0, item["id"]
        peak = max(abs(x) for x in samples) / 32767
        rms = math.sqrt(sum((x / 32767) ** 2 for x in samples) / len(samples))
        minimum_rms = min(minimum_rms, rms)
        assert .05 < rms < .075, (item["id"], rms)
        assert peak <= 10 ** (-14 / 20) + 1 / 32767, item["id"]
        assert abs(sum(samples) / len(samples) / 32767) < .01, item["id"]
        interval = item["repeat_interval_seconds"]
        assert interval == (1.0 if item["kind"] == "grow" else .5)
        assert interval > item["duration_seconds"]
        expected_repeat = array.array("h", [0]) * max(RATE * 2, round((.15 + interval * 2 + len(samples) / RATE + .15) * RATE))
        for n in range(3):
            offset = round((.15 + interval * n) * RATE)
            expected_repeat[offset:offset + len(samples)] = samples
        assert repetitions == expected_repeat, item["id"]
        if item["group_id"] == "patch_soft_ball":
            assert item["approval"] == "approved" and item["selection"] == "chosen_round_2"
            assert single.read_bytes() == (ROOT.parent / "round-2/audio/hit-c-v2.wav").read_bytes()
        else:
            assert item["approval"] == "pending"
        if item["kind"] == "grow":
            holds = item["note_durations_seconds"]
            assert all(hold >= .09 for hold in holds)
            assert abs(sum(holds) - item["duration_seconds"]) < .00001
            assert item["note_frequencies_hz"] == [392, 523.25, 783.99, 1046.50]
            start = 0
            for hold, frequency in zip(holds, item["note_frequencies_hz"]):
                count = round(hold * RATE)
                note = samples[start:start + count]
                assert sum(abs(x) > 100 for x in note) / len(note) > .93
                middle = note[round(count * .2):round(count * .8)]
                crossings = [i for i in range(1, len(middle)) if middle[i-1] < 0 <= middle[i]]
                measured = RATE * (len(crossings)-1) / (crossings[-1]-crossings[0])
                assert abs(measured - frequency) / frequency < .02
                start += count
            print(f"PASS: {item['label']} holds {[round(x*1000) for x in holds]} ms, original C notes retained")
    for group in manifest["groups"]:
        if "comparison_file" not in group:
            continue
        path = ROOT / group["comparison_file"]
        assert sha(path) == group["comparison_sha256"]
        expected_comparison = array.array("h", [0]) * round(.15 * RATE)
        for item in sounds:
            if item["group_id"] == group["id"]:
                expected_comparison.extend(pcm(ROOT / item["file"]))
                expected_comparison.extend(array.array("h", [0]) * round(.55 * RATE))
        assert pcm(path) == expected_comparison

    class References(HTMLParser):
        def handle_starttag(self, tag, attrs):
            for key, value in attrs:
                if key in ("href", "src") and value and not value.startswith(("#", "http")):
                    assert (ROOT / value.split("#", 1)[0]).is_file(), value

    References().feed((ROOT / "index.html").read_text())
    assert not any(ROOT.glob("visual/*")), "V2 visual bytes are reused, not regenerated"
    print(f"PASS: 25 candidates, all 8 object IDs, source preservation, 58 WAV files, repetitions/comparisons, hashes, PCM levels (minimum RMS {20*math.log10(minimum_rms):.1f} dBFS), HTML references")


if __name__ == "__main__":
    main()
