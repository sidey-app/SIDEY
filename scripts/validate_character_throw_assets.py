#!/usr/bin/env python3

import hashlib
import json
import struct
import sys
import zlib
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
ASSET_ROOT = REPOSITORY_ROOT / "shared" / "character-throw" / "v1"
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


def main() -> int:
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    if manifest["schema_version"] != 1 or manifest["approval"]["status"] != "approved":
        fail("asset manifest is not the approved v1 contract")

    characters = manifest["characters"]
    objects = manifest["objects"]
    if len(characters) != 9 or len(objects) != 5:
        fail("manifest must contain nine character sheets and five object sheets")
    if len({entry["id"] for entry in characters}) != 9:
        fail("duplicate character ID")
    if len({entry["id"] for entry in objects}) != 5:
        fail("duplicate object ID")

    for entry in characters:
        validate_entry(entry, (192, 24), 24, 8)
    for entry in objects:
        validate_entry(entry, (192, 16), 16, 12)
    validate_action_baselines(characters, manifest["action_sheet"]["foot_baseline_pixels"])

    character_ids = {entry["id"] for entry in characters}
    object_ids = {entry["id"] for entry in objects}
    mapping = manifest["character_to_object"]
    if set(mapping) != character_ids or not set(mapping.values()) <= object_ids:
        fail("character-to-object mapping is incomplete")
    if manifest["fallbacks"]["character_id"] not in character_ids:
        fail("character fallback is missing")
    if manifest["fallbacks"]["object_id"] not in object_ids:
        fail("object fallback is missing")

    print("Validated 9 action sheets, 5 object sheets, hard alpha, baselines, mappings, and SHA-256.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (AssertionError, KeyError, json.JSONDecodeError, OSError, zlib.error) as error:
        print(f"character throw asset validation failed: {error}", file=sys.stderr)
        sys.exit(1)
