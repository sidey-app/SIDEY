#!/usr/bin/env python3

import hashlib
import json
import struct
import sys
import zlib
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
ASSET_ROOT = REPOSITORY_ROOT / "assets" / "v1"
MANIFEST_PATH = ASSET_ROOT / "manifest.json"
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def fail(message: str) -> None:
    raise AssertionError(message)


def parse_rgba_png(path: Path) -> tuple[int, int, bytes]:
    data = path.read_bytes()
    if not data.startswith(PNG_SIGNATURE):
        fail(f"{path}: invalid PNG signature")

    offset = len(PNG_SIGNATURE)
    width = height = None
    idat = bytearray()
    has_srgb = False
    while offset < len(data):
        length = struct.unpack(">I", data[offset : offset + 4])[0]
        kind = data[offset + 4 : offset + 8]
        payload = data[offset + 8 : offset + 8 + length]
        expected_crc = struct.unpack(">I", data[offset + 8 + length : offset + 12 + length])[0]
        actual_crc = zlib.crc32(kind + payload) & 0xFFFFFFFF
        if actual_crc != expected_crc:
            fail(f"{path}: corrupt {kind.decode('ascii', errors='replace')} chunk")
        offset += 12 + length

        if kind == b"IHDR":
            width, height, depth, color_type, compression, filtering, interlace = struct.unpack(
                ">IIBBBBB", payload
            )
            if (depth, color_type, compression, filtering, interlace) != (8, 6, 0, 0, 0):
                fail(f"{path}: expected 8-bit non-interlaced RGBA PNG")
        elif kind == b"sRGB":
            has_srgb = True
        elif kind == b"IDAT":
            idat.extend(payload)
        elif kind == b"IEND":
            break

    if width is None or height is None or not idat:
        fail(f"{path}: incomplete PNG")
    if not has_srgb:
        fail(f"{path}: missing sRGB chunk")

    encoded = zlib.decompress(idat)
    row_bytes = width * 4
    expected_size = height * (row_bytes + 1)
    if len(encoded) != expected_size:
        fail(f"{path}: unexpected decompressed byte count")

    decoded = bytearray(height * row_bytes)
    previous = bytearray(row_bytes)
    source_offset = 0
    for y in range(height):
        filter_type = encoded[source_offset]
        source_offset += 1
        current = bytearray(encoded[source_offset : source_offset + row_bytes])
        source_offset += row_bytes
        apply_filter(filter_type, current, previous, 4, path)
        decoded[y * row_bytes : (y + 1) * row_bytes] = current
        previous = current
    return width, height, bytes(decoded)


def apply_filter(filter_type: int, row: bytearray, previous: bytearray, bpp: int, path: Path) -> None:
    for index in range(len(row)):
        left = row[index - bpp] if index >= bpp else 0
        up = previous[index]
        upper_left = previous[index - bpp] if index >= bpp else 0
        if filter_type == 0:
            value = row[index]
        elif filter_type == 1:
            value = row[index] + left
        elif filter_type == 2:
            value = row[index] + up
        elif filter_type == 3:
            value = row[index] + ((left + up) // 2)
        elif filter_type == 4:
            value = row[index] + paeth(left, up, upper_left)
        else:
            fail(f"{path}: unsupported PNG filter {filter_type}")
        row[index] = value & 0xFF


def paeth(left: int, up: int, upper_left: int) -> int:
    estimate = left + up - upper_left
    left_distance = abs(estimate - left)
    up_distance = abs(estimate - up)
    upper_left_distance = abs(estimate - upper_left)
    if left_distance <= up_distance and left_distance <= upper_left_distance:
        return left
    if up_distance <= upper_left_distance:
        return up
    return upper_left


def validate_entry(entry: dict, expected_size: tuple[int, int], frame_width: int, frame_count: int) -> None:
    relative_path = Path(entry["path"])
    if relative_path.is_absolute() or ".." in relative_path.parts:
        fail(f"unsafe manifest path: {relative_path}")
    path = ASSET_ROOT / relative_path
    if not path.is_file():
        fail(f"missing asset: {path}")

    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    if digest != entry["sha256"]:
        fail(f"{path}: SHA-256 mismatch")

    width, height, rgba = parse_rgba_png(path)
    if (width, height) != expected_size:
        fail(f"{path}: expected {expected_size}, got {(width, height)}")
    if width != frame_width * frame_count:
        fail(f"{path}: frame geometry mismatch")

    alpha = rgba[3::4]
    if set(alpha) != {0, 255}:
        fail(f"{path}: alpha must be hard and contain transparent and opaque pixels")


def validate_action_baselines(entries: list[dict], baseline_pixels: int) -> None:
    baseline_row = 24 - baseline_pixels - 1
    for entry in entries:
        path = ASSET_ROOT / entry["path"]
        width, _, rgba = parse_rgba_png(path)
        row_bytes = width * 4
        for frame in range(8):
            frame_x = frame * 24
            opaque_rows = []
            for y in range(24):
                start = y * row_bytes + frame_x * 4
                alpha = rgba[start + 3 : start + 24 * 4 : 4]
                if any(value == 255 for value in alpha):
                    opaque_rows.append(y)
            if not opaque_rows or max(opaque_rows) != baseline_row:
                fail(f"{path}: frame {frame} does not preserve the {baseline_pixels}px baseline")


def validate_sheet(
    entry: dict,
    expected_size: tuple[int, int],
    frame_width: int,
    frame_count: int,
    baseline_pixels: int | None = None,
) -> tuple[Path, bytes]:
    validate_entry(entry, expected_size, frame_width, frame_count)
    path = ASSET_ROOT / entry["path"]
    _, height, rgba = parse_rgba_png(path)
    if baseline_pixels is not None:
        expected_row = height - baseline_pixels - 1
        width = expected_size[0]
        row_bytes = width * 4
        for frame in range(frame_count):
            opaque_rows = []
            for y in range(height):
                start = y * row_bytes + frame * frame_width * 4
                alpha = rgba[start + 3 : start + frame_width * 4 : 4]
                if any(value == 255 for value in alpha):
                    opaque_rows.append(y)
            if not opaque_rows or max(opaque_rows) != expected_row:
                fail(f"{path}: frame {frame} does not preserve the {baseline_pixels}px baseline")
    return path, rgba


def mirror_path(pattern: str, entry: dict) -> Path:
    return REPOSITORY_ROOT / pattern.format(**entry)


def validate_png_mirror(source: Path, mirror: Path) -> None:
    if not mirror.is_file():
        fail(f"missing PNG mirror: {mirror.relative_to(REPOSITORY_ROOT)}")
    if mirror.read_bytes() != source.read_bytes():
        fail(f"PNG mirror differs from canonical source: {mirror.relative_to(REPOSITORY_ROOT)}")


def rgba_to_bgra(rgba: bytes) -> bytes:
    bgra = bytearray(len(rgba))
    for index in range(0, len(rgba), 4):
        bgra[index : index + 4] = (
            rgba[index + 2],
            rgba[index + 1],
            rgba[index],
            rgba[index + 3],
        )
    return bytes(bgra)


def validate_bgra_mirror(rgba: bytes, mirror: Path, *, bottom_up: bool = False) -> None:
    if not mirror.is_file():
        fail(f"missing BGRA mirror: {mirror.relative_to(REPOSITORY_ROOT)}")
    data = mirror.read_bytes()
    expected = rgba_to_bgra(rgba)
    if bottom_up:
        row_bytes = len(expected) // (24 if "action-sheets" in mirror.parts else 16)
        expected = b"".join(
            expected[offset : offset + row_bytes]
            for offset in range(len(expected) - row_bytes, -1, -row_bytes)
        )
    if data != expected:
        fail(f"BGRA mirror differs from canonical pixels: {mirror.relative_to(REPOSITORY_ROOT)}")


def validate_windows_character_manifest(entry: dict, rgba: bytes) -> None:
    path = (
        REPOSITORY_ROOT
        / "windows/src/Sidey.Overlay/Assets/Characters"
        / entry["id"]
        / "manifest.json"
    )
    if not path.is_file():
        fail(f"missing Windows character manifest: {path}")
    data = json.loads(path.read_text(encoding="utf-8"))
    if data.get("character_id") != entry["id"] or data.get("sha256") != entry["base"]["sha256"]:
        fail(f"{path}: source ID or SHA-256 differs from central manifest")
    bgra_path = path.with_name("frames.bgra")
    runtime = data.get("runtime_bgra", {})
    if runtime.get("byte_length") != len(rgba):
        fail(f"{path}: runtime BGRA byte length is stale")
    if runtime.get("sha256") != hashlib.sha256(bgra_path.read_bytes()).hexdigest():
        fail(f"{path}: runtime BGRA SHA-256 is stale")


def main() -> int:
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    if manifest["schema_version"] != 1 or manifest["approval"]["status"] != "approved":
        fail("asset manifest is not the approved v1 contract")
    if manifest["format"] != {
        "color_space": "sRGB",
        "bit_depth": 8,
        "color_type": "RGBA",
        "alpha": "hard",
        "background": "transparent",
        "filtering": "nearest",
        "runtime_shadows": False,
    }:
        fail("pixel format contract is incomplete or unsupported")
    expected_sheets = {
        "base_sheet": ((24, 24), (240, 24), 10, 3),
        "throw_hit_sheet": ((24, 24), (192, 24), 8, 3),
        "throwable_sheet": ((16, 16), (192, 16), 12, None),
    }
    for key, (cell_size, sheet_size, frame_count, baseline) in expected_sheets.items():
        sheet = manifest[key]
        actual = (
            tuple(sheet["cell_pixel_size"]),
            tuple(sheet["sheet_pixel_size"]),
            sheet["frame_count"],
            sheet.get("foot_baseline_pixels"),
        )
        if actual != (cell_size, sheet_size, frame_count, baseline):
            fail(f"{key} geometry contract is invalid")
    if manifest["throwable_sheet"]["rotation_center_pixel"] != [7.5, 7.5]:
        fail("throwable rotation center must remain fixed at 7.5,7.5")
    if manifest["base_sheet"]["frames"] != {
        "idle": [0, 1], "walk": [2, 5], "doze": [6, 7], "offline": [8, 9]
    }:
        fail("base frame ranges are invalid")
    if manifest["throw_hit_sheet"]["frames"] != {
        "throw_prepare": [0, 0], "throw_exert": [1, 1], "throw_release": [2, 2],
        "throw_follow_through": [3, 3], "hit_contact": [4, 4], "hit_squash": [5, 5],
        "hit_rebound": [6, 6], "hit_recover": [7, 7]
    }:
        fail("throw/hit frame ranges are invalid")
    if manifest["throwable_sheet"]["frames"] != {
        "rotation": [0, 7], "impact_contact": [8, 8], "impact_squash": [9, 9],
        "impact_bounce": [10, 10], "impact_recover": [11, 11]
    }:
        fail("throwable frame ranges are invalid")

    characters = manifest["characters"]
    throwables = manifest["throwables"]
    if len(characters) != 9 or len(throwables) != 5:
        fail("manifest must contain nine characters and five throwables")
    if len({entry["id"] for entry in characters}) != 9:
        fail("duplicate character ID")
    if len({entry["id"] for entry in throwables}) != 5:
        fail("duplicate throwable ID")

    mirrors = manifest["mirrors"]
    if mirrors["bgra_row_order"] != {
        "character_base": "top_down",
        "throw_hit": "bottom_up",
        "throwable": "bottom_up",
    }:
        fail("unsupported BGRA mirror row order")
    managed_pngs: set[Path] = set()
    for entry in characters:
        if entry["base"]["path"] != f"characters/{entry['id']}/base.png":
            fail(f"non-canonical base path for {entry['id']}")
        if entry["throw_hit"]["path"] != f"characters/{entry['id']}/throw_hit.png":
            fail(f"non-canonical throw/hit path for {entry['id']}")
        base_path, base_rgba = validate_sheet(entry["base"], (240, 24), 24, 10, 3)
        action_path, action_rgba = validate_sheet(entry["throw_hit"], (192, 24), 24, 8, 3)
        managed_pngs.update((base_path, action_path))
        for pattern in mirrors["character_base_png"]:
            validate_png_mirror(base_path, mirror_path(pattern, entry))
        for pattern in mirrors["character_base_bgra"]:
            validate_bgra_mirror(base_rgba, mirror_path(pattern, entry))
        for pattern in mirrors["throw_hit_png"]:
            validate_png_mirror(action_path, mirror_path(pattern, entry))
        for pattern in mirrors["throw_hit_bgra"]:
            validate_bgra_mirror(action_rgba, mirror_path(pattern, entry), bottom_up=True)
        validate_windows_character_manifest(entry, base_rgba)

    for entry in throwables:
        if entry["sprite"]["path"] != f"throwables/{entry['id']}/sprite.png":
            fail(f"non-canonical throwable path for {entry['id']}")
        sprite_path, sprite_rgba = validate_sheet(entry["sprite"], (192, 16), 16, 12)
        managed_pngs.add(sprite_path)
        for pattern in mirrors["throwable_png"]:
            validate_png_mirror(sprite_path, mirror_path(pattern, entry))
        for pattern in mirrors["throwable_bgra"]:
            validate_bgra_mirror(sprite_rgba, mirror_path(pattern, entry), bottom_up=True)

    character_ids = {entry["id"] for entry in characters}
    throwable_ids = {entry["id"] for entry in throwables}
    mapping = {entry["id"]: entry["throwable_id"] for entry in characters}
    if set(mapping) != character_ids or not set(mapping.values()) <= throwable_ids:
        fail("character-to-throwable mapping is incomplete")

    licensing = manifest["licensing"]
    if licensing.get("paid_asset_license") != "../PAID_ASSET_LICENSE.md":
        fail("paid asset license path is missing or unsupported")
    paid_asset_license = ASSET_ROOT / licensing["paid_asset_license"]
    if not paid_asset_license.is_file():
        fail("paid asset license file is missing")

    paid_character_list = licensing["paid_character_ids"]
    paid_throwable_list = licensing["paid_throwable_ids"]
    if not isinstance(paid_character_list, list) or not isinstance(paid_throwable_list, list):
        fail("paid asset ID schedules must be lists")
    paid_character_ids = set(paid_character_list)
    paid_throwable_ids = set(paid_throwable_list)
    if len(paid_character_ids) != len(paid_character_list):
        fail("duplicate paid character ID")
    if len(paid_throwable_ids) != len(paid_throwable_list):
        fail("duplicate paid throwable ID")
    if not paid_character_ids or not paid_character_ids <= character_ids:
        fail("paid character schedule is empty or references an unknown character")
    if not paid_throwable_ids or not paid_throwable_ids <= throwable_ids:
        fail("paid throwable schedule is empty or references an unknown throwable")
    if {mapping[character_id] for character_id in paid_character_ids} != paid_throwable_ids:
        fail("paid characters and their licensed throwables differ")
    free_character_ids = character_ids - paid_character_ids
    if {mapping[character_id] for character_id in free_character_ids} & paid_throwable_ids:
        fail("a free character references a paid throwable")

    if manifest["fallbacks"]["character_id"] not in character_ids:
        fail("character fallback is missing")
    if manifest["fallbacks"]["throwable_id"] not in throwable_ids:
        fail("throwable fallback is missing")

    hamster = next(entry for entry in characters if entry["id"] == "pixel_hamster")
    patch_ball = next(entry for entry in throwables if entry["id"] == "patch_soft_ball")
    defaults = mirrors["previewer_defaults"]
    validate_png_mirror(
        ASSET_ROOT / hamster["throw_hit"]["path"],
        REPOSITORY_ROOT / defaults["pixel_hamster_throw_hit"],
    )
    validate_png_mirror(
        ASSET_ROOT / patch_ball["sprite"]["path"],
        REPOSITORY_ROOT / defaults["patch_soft_ball"],
    )

    reference = ASSET_ROOT / manifest["reference"]["path"]
    if not reference.is_file() or hashlib.sha256(reference.read_bytes()).hexdigest() != manifest["reference"]["sha256"]:
        fail("official reference image SHA-256 mismatch")

    actual_pngs = set((ASSET_ROOT / "characters").glob("*/*.png")) | set(
        (ASSET_ROOT / "throwables").glob("*/*.png")
    )
    if actual_pngs != managed_pngs:
        paths = sorted(str(path.relative_to(ASSET_ROOT)) for path in actual_pngs ^ managed_pngs)
        fail(f"canonical assets and manifest differ: {paths}")

    print(
        "Validated 9 base sheets, 9 throw/hit sheets, 5 throwables, all mirrors, "
        "baselines, mappings, paid asset licensing, formats, and SHA-256 values."
    )
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (AssertionError, KeyError, json.JSONDecodeError, OSError, zlib.error) as error:
        print(f"pixel asset validation failed: {error}", file=sys.stderr)
        sys.exit(1)
