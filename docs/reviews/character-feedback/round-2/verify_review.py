#!/usr/bin/env python3
"""Check candidate integrity, PCM constraints and offline review references."""
import array
import hashlib
from html.parser import HTMLParser
import json
import math
from pathlib import Path
import sys
import wave

ROOT = Path(__file__).resolve().parent


def pcm(path):
    with wave.open(str(path), "rb") as audio:
        assert (audio.getnchannels(), audio.getsampwidth(), audio.getframerate()) == (1, 2, 48000), path
        values = array.array("h", audio.readframes(audio.getnframes()))
    if sys.byteorder != "little":
        values.byteswap()
    return values


def main():
    audio = json.loads((ROOT / "audio-manifest.json").read_text())
    visual = json.loads((ROOT / "visual-manifest.json").read_text())
    assert audio["approval"] == visual["approval"] == "pending"
    assert audio["review_round"] == visual["review_round"] == 2
    assert len(audio["sounds"]) == 6
    for item in audio["sounds"]:
        single, repeated = ROOT / item["file"], ROOT / item["repeat_file"]
        assert item["approval"] == "pending"
        assert hashlib.sha256(single.read_bytes()).hexdigest() == item["sha256"]
        assert hashlib.sha256(repeated.read_bytes()).hexdigest() == item["repeat_sha256"]
        samples, repetitions = pcm(single), pcm(repeated)
        assert len(samples) == round(item["duration_seconds"] * 48000)
        assert samples[0] == samples[-1] == 0
        peak = max(abs(x) for x in samples) / 32767
        rms = math.sqrt(sum((x / 32767) ** 2 for x in samples) / len(samples))
        assert 0.04 < rms < 0.08
        assert peak <= 10 ** (-14 / 20) + 1 / 32767
        assert abs(sum(samples) / len(samples) / 32767) < .01
        if item["kind"] == "hit":
            # Check the rendered audio, not just declared metadata, for an upward finish.
            def estimated_pitch(start, end):
                segment = samples[round(start * len(samples)):round(end * len(samples))]
                crossings = [i for i in range(1, len(segment)) if segment[i-1] < 0 <= segment[i]]
                assert len(crossings) >= 3
                return 48000 * (len(crossings) - 1) / (crossings[-1] - crossings[0])
            early = estimated_pitch(.10, .35)
            late = estimated_pitch(.68, .88)
            assert late > early * 1.15, (item["id"], early, late)
            print(f"PASS: {item['id']} rendered pitch rises {early:.0f} → {late:.0f} Hz")
        assert len(repetitions) == 96000
        for start in (7200, 31200, 55200):
            assert repetitions[start:start + len(samples)] == samples
    assert visual["stun_seconds"] == 6 and visual["recovery_protection_seconds"] == 0
    assert visual["source_frames"] == [8, 9] and visual["star_count"] == 3
    previous = json.loads((ROOT.parent / "round-1/visual-manifest.json").read_text())
    for key in ("source_character_sha256", "source_frames", "body_frame_seconds", "orbit_seconds", "star_count", "star_size_logical_pixels", "orbit_radius_logical_pixels", "orbit_center_logical_pixels", "fps", "stun_seconds"):
        assert visual[key] == previous[key], key
    assert (ROOT / "visual/star-v1.png").read_bytes() == (ROOT.parent / "round-1/visual/star-v1.png").read_bytes()
    assert visual["ring"]["width_logical_pixels"] == 1
    grow_palettes = {item["sound_palette"] for item in audio["sounds"] if item["kind"] == "grow"}
    assert len(grow_palettes) == 3
    for item in visual["assets"]:
        assert item["approval"] == "pending"
        assert hashlib.sha256((ROOT / item["file"]).read_bytes()).hexdigest() == item["sha256"]
    source = ROOT.parents[3] / "assets/v1/characters/pixel_hamster/base.png"
    assert hashlib.sha256(source.read_bytes()).hexdigest() == visual["source_character_sha256"]

    class References(HTMLParser):
        def handle_starttag(self, tag, attrs):
            for key, value in attrs:
                if key in ("src", "href") and value and not value.startswith(("#", "http")):
                    assert (ROOT / value).is_file(), value

    References().feed((ROOT / "index.html").read_text())
    print("PASS: six PCM candidates, repeat timing, levels, endpoints, pending approvals, all hashes and HTML references.")


if __name__ == "__main__":
    main()
