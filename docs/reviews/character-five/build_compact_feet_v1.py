#!/usr/bin/env python3
"""Reproduce the compact-feet review candidate; existing approvals stay untouched.

No arguments verifies checked-in candidate bytes. --write writes only the new
candidate directory. --self-test exercises rejection of invalid pixel edits.
Uses the existing deterministic frame generators, without invoking their writers.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
from audit_frames import FRAME_NAMES, analyze_frame, frame_bytes, parse_rgba_png
from build_appearance import encode_png
from build_character_repairs import make_outputs as original_repairs
from build_quokka_v3 import build as original_quokka

ROOT = Path(__file__).resolve().parent
REPOSITORY = ROOT.parents[2]
# Keep the pending revision outside the recursively inventoried, approved package.
TARGET = ROOT.parent / "character-five-compact-feet-v1"
SOURCE_COMMIT = "d8188a529b54c61969d4a987b782976bcca2e45c"
CHARACTERS = ("shiba", "duck", "poop", "tteokbokki", "quokka")
SOURCE_HASHES = {
    "shiba": ("011ae19b2882a18869666641681a33c9dc41b42cf30d1404ecb08e20b9acb928", "a88e049275de5059d880cb7ff1c478a2e8204d9decc0c7bf461ff9255d6dc24f"),
    "duck": ("09c0c4160cf143dd4a1859fe20fdbab1167d08c5b072f6cd1b7906bed429b97c", "a8fab6aebc7f6260e8f470e26365a45cac1a493144da36ab0665d54a38d0fc67"),
    "poop": ("99ac0e9eb8c055f5663e3109d3e7cbbf95a0137f2920c8cde41fa265854188c1", "3611e29ca3a6b1efcd9533a9d56494eb8daee31bef973e7ae2c69c0f115f7e8b"),
    "tteokbokki": ("0a7400c8d7019602147994a75c8e0171441f7c151629cb0f5948bb75e1b7b655", "b5084af74609db432e21bea117da0253aac94197e2a2ded157f7cec04465851c"),
    "quokka": ("e301cb83b48761c1bb5b83f82a6525638d973eb7e337ebe378dea88d370e2a7c", "fc01c484c98651c5da3e32888122070af04091d57a514199da6019ca73b753a7"),
}
EMPTY = (0, 0, 0, 0)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def unpack(data):
    return [tuple(data[i:i + 4]) for i in range(0, len(data), 4)]


def pack(pixels):
    return bytes(channel for pixel in pixels for channel in pixel)


def row_runs(pixels, y):
    runs = []
    for x in range(24):
        if pixels[y * 24 + x][3]:
            if not runs or x != runs[-1][-1] + 1:
                runs.append([])
            runs[-1].append(x)
    return runs


def tucked(character, sheet, index):
    return character != "quokka" and sheet == "base" and index >= 7


def raised(character, sheet, index):
    return (sheet == "base" and index in ((3, 5) if character == "quokka" else (1, 3, 5))) or (sheet == "throw_hit" and index == 6)


def compact(character, sheet, index, before):
    pixels = unpack(before)
    if tucked(character, sheet, index):
        return before
    feet = row_runs(pixels, 20)
    require(len(feet) == 2 and all(len(run) == 3 for run in feet), "source must have two 3px feet")
    # Trim the outside toe: preserve each existing walk offset and foot color.
    pixels[20 * 24 + feet[0][0]] = EMPTY
    pixels[20 * 24 + feet[1][-1]] = EMPTY
    if raised(character, sheet, index):
        body = row_runs(pixels, 18)
        require(len(body) == 1, "raised lower outline must be continuous")
        left, right = body[0][0], body[0][-1]
        outline = pixels[18 * 24 + left]
        require(all(pixels[18 * 24 + x] == outline for x in body[0]), "expected solid lower outline")
        # Continue the existing fur/belly one row down, then put the shorter
        # lower outline directly on the feet. No isolated ankle-colored stem.
        for x in range(left + 1, right):
            require(pixels[17 * 24 + x][3] == 255, "belly continuation must use the pixel above")
            pixels[18 * 24 + x] = pixels[17 * 24 + x]
        for x in range(24):
            pixels[19 * 24 + x] = outline if left < x < right else EMPTY
    return pack(pixels)


def verify_frame(character, sheet, index, before, after):
    old, new = unpack(before), unpack(after)
    edits = [{"x": i % 24, "y": i // 24, "from": list(a), "to": list(b)}
             for i, (a, b) in enumerate(zip(old, new)) if a != b]
    require(len(before) == len(after) == 24 * 24 * 4, "frame size changed")
    require(set(new) <= set(old), "new palette color")
    if tucked(character, sheet, index):
        require(before == after, "tucked silhouette changed")
    else:
        original_feet = row_runs(old, 20)
        require(len(original_feet) == 2 and all(len(run) == 3 for run in original_feet), "source feet changed")
        allowed = {(original_feet[0][0], 20), (original_feet[1][-1], 20)}
        if raised(character, sheet, index):
            body = row_runs(old, 18)
            require(len(body) == 1, "source lower body changed")
            allowed |= {(x, y) for y in (18, 19) for x in body[0]}
        require(all((e["x"], e["y"]) in allowed for e in edits), "edit outside exact foot/lower-outline mask")
        feet = row_runs(new, 20)
        require(feet == [original_feet[0][1:], original_feet[1][:-1]], "compact foot width/offset changed")
        require(all(new[19 * 24 + x][3] == 255 for foot in feet for x in foot), "foot must directly touch body above")
        if raised(character, sheet, index):
            require(len(row_runs(new, 19)) == 1, "exposed ankle stems remain")
    audit = analyze_frame(after)
    require(audit["hard_alpha"] and audit["baseline_preserved"], "alpha or baseline changed")
    require(len(audit["alpha_component_sizes_8_connected"]) == 1, "disconnected foot/body")
    require(audit["cell_boundary_contacts"] == analyze_frame(before)["cell_boundary_contacts"], "cell boundary changed")
    return {"index": index, "state": FRAME_NAMES[sheet][index], "source_rgba_sha256": sha(before),
            "rgba_sha256": sha(after), "changed_pixels": len(edits), "edits": edits,
            "raised_outline_reconnected": raised(character, sheet, index),
            "tucked_silhouette_preserved": tucked(character, sheet, index),
            "baseline_row": 20, "body_components_8_connected": 1,
            "foot_runs": row_runs(new, 20), "outside_allowed_mask_unchanged": True,
            "palette_preserved": True}


# Small embedded bitmap labels make review PNGs reproducible without fonts,
# Pillow, a browser, or an OS image renderer. Character pixels use nearest-neighbor.
FONT = {
    "A":"01110/10001/10001/11111/10001/10001/10001", "B":"11110/10001/10001/11110/10001/10001/11110",
    "C":"01111/10000/10000/10000/10000/10000/01111", "D":"11110/10001/10001/10001/10001/10001/11110",
    "E":"11111/10000/10000/11110/10000/10000/11111", "F":"11111/10000/10000/11110/10000/10000/10000",
    "G":"01111/10000/10000/10111/10001/10001/01111", "H":"10001/10001/10001/11111/10001/10001/10001",
    "I":"11111/00100/00100/00100/00100/00100/11111", "J":"00111/00010/00010/00010/10010/10010/01100",
    "K":"10001/10010/10100/11000/10100/10010/10001", "L":"10000/10000/10000/10000/10000/10000/11111",
    "M":"10001/11011/10101/10101/10001/10001/10001", "N":"10001/11001/10101/10011/10001/10001/10001",
    "O":"01110/10001/10001/10001/10001/10001/01110", "P":"11110/10001/10001/11110/10000/10000/10000",
    "Q":"01110/10001/10001/10001/10101/10010/01101", "R":"11110/10001/10001/11110/10100/10010/10001",
    "S":"01111/10000/10000/01110/00001/00001/11110", "T":"11111/00100/00100/00100/00100/00100/00100",
    "U":"10001/10001/10001/10001/10001/10001/01110", "V":"10001/10001/10001/10001/10001/01010/00100",
    "W":"10001/10001/10001/10101/10101/10101/01010", "X":"10001/10001/01010/00100/01010/10001/10001",
    "Y":"10001/10001/01010/00100/00100/00100/00100", "Z":"11111/00001/00010/00100/01000/10000/11111",
    "0":"01110/10001/10011/10101/11001/10001/01110", "1":"00100/01100/00100/00100/00100/00100/01110",
    "2":"01110/10001/00001/00010/00100/01000/11111", "3":"11110/00001/00001/01110/00001/00001/11110",
    "4":"00010/00110/01010/10010/11111/00010/00010", "5":"11111/10000/10000/11110/00001/00001/11110",
    "6":"01110/10000/10000/11110/10001/10001/01110", "7":"11111/00001/00010/00100/01000/01000/01000",
    "8":"01110/10001/10001/01110/10001/10001/01110", "9":"01110/10001/10001/01111/00001/00001/01110",
    "-":"00000/00000/00000/11111/00000/00000/00000", " ":"00000/00000/00000/00000/00000/00000/00000",
}


class Board:
    def __init__(self, width, height):
        self.width, self.height = width, height
        self.data = bytearray(bytes((232, 235, 242, 255)) * width * height)

    def rect(self, x, y, width, height, color):
        require(0 <= x <= x + width <= self.width and 0 <= y <= y + height <= self.height, "review layout overflow")
        for row in range(y, y + height):
            start = (row * self.width + x) * 4
            self.data[start:start + width * 4] = bytes(color) * width

    def text(self, x, y, value, scale=1):
        for index, char in enumerate(value.upper()):
            for row, pattern in enumerate(FONT[char].split("/")):
                for column, pixel in enumerate(pattern):
                    if pixel == "1":
                        self.rect(x + (index * 6 + column) * scale, y + row * scale, scale, scale, (42, 48, 61, 255))

    def frame(self, x, y, frame, scale):
        for offset, color in enumerate(unpack(frame)):
            if color[3]:
                self.rect(x + offset % 24 * scale, y + offset // 24 * scale, scale, scale, color)

    def png(self):
        return encode_png(self.width, self.height, self.data)


def review_images(pairs):
    summary = Board(1020, 970)
    summary.text(16, 12, "COMPACT FEET V1 - BEFORE AND AFTER", 2)
    summary.text(16, 36, "USER REQUESTED REVISION - IMPLEMENTATION REVIEWED - 6X")
    for i, character in enumerate(CHARACTERS):
        y = 75 + i * 177
        summary.text(8, y + 65, character)
        raised_index = 3 if character == "quokka" else 1
        selected = [("base", 0), ("base", raised_index), ("throw_hit", 6)]
        for column, (sheet, index) in enumerate(selected):
            for side, label in enumerate(("BEFORE", "AFTER")):
                x = 102 + column * 304 + side * 150
                summary.text(x, y, f'{"BASE" if sheet == "base" else "HIT"} {index} {label}')
                summary.frame(x, y + 18, pairs[character, sheet][side][index], 6)
    output = {"review/summary.png": summary.png()}
    for character in CHARACTERS:
        board = Board(1140, 554)
        board.text(12, 12, character + " - ALL 18 FRAMES", 2)
        board.text(12, 34, "4X NEAREST NEIGHBOR - SAME TIMING AND FRAME ORDER")
        for group, sheet in enumerate(("base", "throw_hit")):
            before, after = pairs[character, sheet]
            for side, (frames, label) in enumerate(((before, "BEFORE"), (after, "AFTER"))):
                y = 66 + (group * 2 + side) * 120
                board.text(6, y + 40, ("BASE " if group == 0 else "ACTION ") + label)
                for index, frame in enumerate(frames):
                    x = 106 + index * 102
                    board.text(x, y, str(index))
                    board.frame(x, y + 15, frame, 4)
        output[f"review/pixel_{character}-all-frames.png"] = board.png()
    reference = Board(672, 222)
    reference.text(12, 12, "REFERENCE - UNCHANGED BASE 0 AND 3", 2)
    for character_index, character in enumerate(("guinea_pig", "monkey")):
        path = REPOSITORY / f"assets/v1/characters/pixel_{character}/base.png"
        width, _, rgba = parse_rgba_png(path)
        for column, index in enumerate((0, 3)):
            x = 16 + character_index * 332 + column * 158
            reference.text(x, 46, f"{character.replace('_', ' ')} {index}")
            reference.frame(x, 67, frame_bytes(rgba, width, index), 6)
    output["review/references.png"] = reference.png()
    return output


def build():
    four, _ = original_repairs()
    quokka = original_quokka()
    output, records, pairs = {}, [], {}
    for character in CHARACTERS:
        for sheet_index, (sheet, names) in enumerate(FRAME_NAMES.items()):
            source = ROOT / f"candidates/character-v{3 if character == 'quokka' else 2}/pixel_{character}/{sheet}.png"
            source_bytes = source.read_bytes()
            require(sha(source_bytes) == SOURCE_HASHES[character][sheet_index], f"pinned source changed: {source}")
            reproduced = quokka[source] if character == "quokka" else four[source.relative_to(ROOT).as_posix()]
            require(reproduced == source_bytes, f"source generator differs: {source}")
            width, height, rgba = parse_rgba_png(source)
            require((width, height) == (24 * len(names), 24), "source dimensions changed")
            before = [frame_bytes(rgba, width, index) for index in range(len(names))]
            after = [compact(character, sheet, index, frame) for index, frame in enumerate(before)]
            frames = [verify_frame(character, sheet, index, a, b) for index, (a, b) in enumerate(zip(before, after))]
            # Preserve existing per-state timing variety, including all four throw poses.
            groups = ((0, 2), (2, 6), (6, 8), (8, 10)) if sheet == "base" else ((0, 4), (4, 8))
            for start, end in groups:
                require(len(set(after[start:end])) == len(set(before[start:end])), "motion variety changed")
            joined = b"".join(frame[y * 24 * 4:(y + 1) * 24 * 4] for y in range(24) for frame in after)
            destination = f"pixel_{character}/{sheet}.png"
            output[destination] = encode_png(width, height, joined)
            if sheet == "base":
                output[f"pixel_{character}/appearance.png"] = encode_png(24, 24, after[0])
            records.append({"character_id": f"pixel_{character}", "sheet": sheet,
                            "source_path": source.relative_to(REPOSITORY).as_posix(),
                            "source_sha256": sha(source_bytes), "path": destination,
                            "sha256": sha(output[destination]), "dimensions": [width, height], "frames": frames})
            pairs[character, sheet] = before, after
    output.update(review_images(pairs))
    revision = {
        "schema_version": 1,
        "status": "user_requested_revision_implementation_reviewed",
        "authorization": {
            "kind": "user_requested_adjustment",
            "request_summary": "신규 5종의 발목이 길고 발이 커 보이므로 기니피그·원숭이를 참고해 모두 수정하도록 요청함.",
            "scope": "얼굴·의상·팔레트·그 외 픽셀은 보존하며 발과 배 밑 외곽만 제한적으로 수정",
            "new_pixels_explicitly_approved_by_user": False,
        },
        "visual_review": {
            "status": "reviewed_by_implementation_agent",
            "coordinating_agent_review": "정지·상승·피격 전후 summary PNG를 확인하고 사용자 요청 범위의 전체 반영을 진행함.",
            "implementing_agent_review": "5종의 전체 90프레임 전후 PNG와 summary를 확인함.",
            "user_visual_approval_claimed": False,
            "comparisons": [{"path": path, "sha256": sha(data)} for path, data in sorted(output.items()) if path.startswith("review/")],
        },
        "original_approval": {
            "path": "docs/reviews/character-five/approvals.json",
            "sha256": sha((ROOT / "approvals.json").read_bytes()),
            "meaning": "기존 입력 자산 승인만을 나타내며 새 파생 픽셀의 승인으로 재해석하지 않음",
        },
        "source_commit": SOURCE_COMMIT,
        "result_sheets": [{"path": sheet["path"], "sha256": sheet["sha256"]} for sheet in records],
    }
    output["revision.json"] = (json.dumps(revision, ensure_ascii=False, indent=2) + "\n").encode()
    frames = [frame for sheet in records for frame in sheet["frames"]]
    inputs = [ROOT / name for name in ("build_character_repairs.py", "build_quokka_v3.py", "audit_frames.py", "build_appearance.py")]
    inputs += [REPOSITORY / f"assets/v1/characters/pixel_{name}/base.png" for name in ("guinea_pig", "monkey")]
    report = {
        "schema_version": 1, "candidate_version": "compact-feet-v1", "status": revision["status"],
        "revision_metadata": "revision.json",
        "source_commit": SOURCE_COMMIT, "coordinates": "zero-based 24x24 cell, top-left origin",
        "scope": "발 y20 바깥쪽 1px씩 제거. 상승 프레임 y18-19 배 밑 외곽만 연결. 얼굴·의상·팔레트·나머지 픽셀 유지.",
        "authorship": "기존 정지유 원본과 승인된 Codex 보정 프레임의 발 주변 코드 보정. 기존 승인 기록은 변경하지 않음.",
        "source_inputs": [{"path": p.relative_to(REPOSITORY).as_posix(), "sha256": sha(p.read_bytes())} for p in inputs],
        "generator_sha256": sha(Path(__file__).read_bytes()),
        "summary": {"characters": 5, "sheets": 10, "frames": len(frames),
                    "changed_frames": sum(bool(f["edits"]) for f in frames),
                    "changed_pixels": sum(f["changed_pixels"] for f in frames),
                    "raised_frames": sum(f["raised_outline_reconnected"] for f in frames),
                    "preserved_tucked_frames": sum(f["tucked_silhouette_preserved"] for f in frames),
                    "connected_frames": len(frames), "baseline_row": 20},
        "sheets": records,
        "artifacts": [{"path": path, "sha256": sha(data)} for path, data in sorted(output.items())],
        "limitations": ["사용자의 수정 지시와 구현 담당자의 시각 검토를 구분하며 새 픽셀의 사용자 개별 승인을 주장하지 않음.",
                        "생성기는 파생 검토 패키지만 재현하며 공용·플랫폼 미러 승격이나 공개 릴리스는 수행하지 않음."],
    }
    require(report["summary"]["frames"] == 90 and report["summary"]["changed_frames"] == 78, "unexpected frame scope")
    output["report.json"] = (json.dumps(report, ensure_ascii=False, indent=2) + "\n").encode()
    output["README.md"] = review_markdown(report).encode()
    return output, report, pairs


def review_markdown(report):
    rows = []
    for character in CHARACTERS:
        sheets = [s for s in report["sheets"] if s["character_id"] == f"pixel_{character}"]
        changed = sum(bool(f["edits"]) for s in sheets for f in s["frames"])
        pixels = sum(f["changed_pixels"] for s in sheets for f in s["frames"])
        rows.append(f"| {character} | {changed}/18 | {pixels} | [전체 전후](review/pixel_{character}-all-frames.png) |")
    return "\n".join([
        "# 발목·발 비율 보정 v1", "", "상태: **사용자 요청에 따른 파생 수정·구현 담당자 시각 검토 완료**. 새 픽셀을 사용자가 개별 승인했다고 주장하지 않는다.", "",
        "별도 파생 패키지이며 기존 승인 패키지의 재귀 파일 목록에 포함하지 않는다. [revision.json](revision.json)에 수정 요청과 구현 담당자 검토 범위를 기록했다. [원작 기여·이용 조건](../character-five/LICENSE.md)과 [SIDEY Paid Asset License 1.0](../../../assets/PAID_ASSET_LICENSE.md)을 따른다.", "",
        f"원본 Git SHA: `{SOURCE_COMMIT}`. 각 원본·결과 SHA-256과 90프레임의 정확한 수정 좌표/RGBA는 [report.json](report.json)에 기록한다.", "",
        "## 전후 비교", "", "[정지 0·상승 1(쿼카 3)·피격 6 비교](review/summary.png) · [기니피그·원숭이 참고](review/references.png)", "",
        "각 쌍은 BEFORE → AFTER다. 확대는 정수 nearest-neighbor이며 PNG 안에 기재된 배율을 따른다.", "",
        "| 캐릭터 | 변경 프레임 | 변경 픽셀 | 비교표 |", "| --- | ---: | ---: | --- |", *rows, "",
        "## 수정 범위", "",
        "- 발바닥 y20을 3×1에서 2×1px로 줄인다. 왼발의 가장 왼쪽·오른발의 가장 오른쪽 픽셀만 없애며 기존 보폭과 발색을 유지한다.",
        "- 상승 프레임은 y18 배 밑 내부에 바로 위의 기존 색을 이어 놓고 y19에 한 칸 좁은 외곽선을 둔다. 두 발은 몸과 수직으로 직접 연결하며 별도의 발색 기둥은 남기지 않는다.",
        "- 시바·오리·똥·떡볶이 base 1/3/5와 throw_hit 6, 쿼카 base 3/5와 throw_hit 6의 발목을 조정한다.",
        "- 신규 4종 base 7~9의 졸기·잠 실루엣 12프레임은 전체 RGBA를 보존한다. 쿼카는 잠든 프레임에도 분리된 두 발이 있어 너비만 줄인다.",
        "- 모든 프레임에서 y0~17, 얼굴·눈·의상·팔·색과 셀 경계 접촉을 보존한다. 발 주변에서도 프레임별 허용 좌표 이외 변경을 거부한다.", "",
        "원숭이의 발은 실제로 4~5px 폭이며 일부 상승 프레임에는 발 위 투명 행이 있다. 그 결함을 복제하지 않고, 기니피그의 2px 너비와 짧은 노출 비율을 참고했다.", "",
        "## 재현·검증", "", "저장소 루트에서 실행한다. 기본 실행은 후보 파일을 쓰지 않는다.", "", "```sh",
        "python3 -B docs/reviews/character-five/build_compact_feet_v1.py --write",
        "python3 -B docs/reviews/character-five/build_compact_feet_v1.py",
        "python3 -B docs/reviews/character-five/build_compact_feet_v1.py --self-test", "```", "",
        "원본 생성기 재현 → 고정 원본 해시 확인 → 90프레임 허용 좌표/기준선/연결/기존 팔레트/동작 프레임 다양성 검사 → 결과 바이트 비교 순서로 검증한다.", "",
        "공용 원본과 웹 사본은 사용자 수정 지시에 따라 파생 출처를 기록해 승격한다. macOS 미러는 별도 플랫폼 작업에서 갱신한다. 기존 승인 JSON은 변경하지 않으며 새 픽셀의 사용자 승인 근거로 사용하지 않는다. 앱 공개 릴리스와는 별개다.", "",
    ])


def self_test(pairs):
    before, after = (frames[1] for frames in pairs["shiba", "base"])
    changes = [
        ("face", 10, 8, EMPTY),
        ("baseline", 6, 21, unpack(before)[20 * 24 + 6]),
        ("new color", 6, 20, (1, 2, 3, 255)),
        ("ankle gap", 6, 19, EMPTY),
        ("wide foot", 5, 20, unpack(before)[20 * 24 + 5]),
    ]
    for name, x, y, color in changes:
        pixels = unpack(after)
        require(pixels[y * 24 + x] != color, f"self-test did not mutate {name}")
        pixels[y * 24 + x] = color
        try:
            verify_frame("shiba", "base", 1, before, pack(pixels))
        except ValueError:
            continue
        raise ValueError(f"invalid {name} accepted")
    before, after = (frames[8] for frames in pairs["duck", "base"])
    pixels = unpack(after); pixels[20 * 24 + 6] = EMPTY
    try:
        verify_frame("duck", "base", 8, before, pack(pixels))
    except ValueError:
        return len(changes) + 1
    raise ValueError("changed sleeping silhouette accepted")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--write", action="store_true")
    mode.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    try:
        output, report, pairs = build()
        if args.self_test:
            print(f"PASS: {self_test(pairs)} invalid edits rejected; 90 valid frames verified")
            return 0
        for relative, encoded in output.items():
            target = TARGET / relative
            if args.write:
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(encoded)
            else:
                require(target.is_file() and target.read_bytes() == encoded, f"stale/missing candidate: {relative}")
        print(("WROTE" if args.write else "PASS (read-only)") + ": " + json.dumps(report["summary"]))
        print("User-requested derivative; implementation visually reviewed. Original approvals remain unchanged.")
        return 0
    except (ValueError, KeyError, OSError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
