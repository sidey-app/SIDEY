#!/usr/bin/env python3

import struct
import zlib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = ROOT / "macos" / "SIDEY" / "Resources" / "Characters"
OUTPUT_ROOT = ROOT / "windows" / "src" / "Sidey.Overlay" / "Assets" / "Characters"
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
CHARACTERS = {
    "pixel_guinea_pig": "PixelGuineaPig",
    "pixel_monkey": "PixelMonkey",
    "pixel_chinchilla": "PixelChinchilla",
    "pixel_starlight_upalupa": "PixelStarlightUpalupa",
}


def paeth(left: int, up: int, upper_left: int) -> int:
    estimate = left + up - upper_left
    distances = (abs(estimate - left), abs(estimate - up), abs(estimate - upper_left))
    if distances[0] <= distances[1] and distances[0] <= distances[2]:
        return left
    return up if distances[1] <= distances[2] else upper_left


def decode_rgba_png(data: bytes) -> tuple[int, int, bytes]:
    if not data.startswith(PNG_SIGNATURE):
        raise ValueError("invalid PNG signature")

    offset = len(PNG_SIGNATURE)
    width = height = None
    compressed = bytearray()
    while offset < len(data):
        length = struct.unpack(">I", data[offset : offset + 4])[0]
        kind = data[offset + 4 : offset + 8]
        payload = data[offset + 8 : offset + 8 + length]
        expected_crc = struct.unpack(">I", data[offset + 8 + length : offset + 12 + length])[0]
        if zlib.crc32(kind + payload) & 0xFFFFFFFF != expected_crc:
            raise ValueError(f"corrupt {kind!r} chunk")
        offset += 12 + length

        if kind == b"IHDR":
            width, height, depth, color_type, compression, filtering, interlace = struct.unpack(
                ">IIBBBBB", payload
            )
            if (depth, color_type, compression, filtering, interlace) != (8, 6, 0, 0, 0):
                raise ValueError("expected 8-bit non-interlaced RGBA PNG")
        elif kind == b"IDAT":
            compressed.extend(payload)
        elif kind == b"IEND":
            break

    if (width, height) != (240, 24) or not compressed:
        raise ValueError(f"expected a complete 240x24 sprite sheet, got {width}x{height}")

    encoded = zlib.decompress(compressed)
    row_bytes = width * 4
    if len(encoded) != height * (row_bytes + 1):
        raise ValueError("unexpected decompressed byte count")

    decoded = bytearray(height * row_bytes)
    previous = bytearray(row_bytes)
    source_offset = 0
    for y in range(height):
        filter_type = encoded[source_offset]
        source_offset += 1
        current = bytearray(encoded[source_offset : source_offset + row_bytes])
        source_offset += row_bytes
        for index in range(row_bytes):
            left = current[index - 4] if index >= 4 else 0
            up = previous[index]
            upper_left = previous[index - 4] if index >= 4 else 0
            if filter_type == 0:
                value = current[index]
            elif filter_type == 1:
                value = current[index] + left
            elif filter_type == 2:
                value = current[index] + up
            elif filter_type == 3:
                value = current[index] + ((left + up) // 2)
            elif filter_type == 4:
                value = current[index] + paeth(left, up, upper_left)
            else:
                raise ValueError(f"unsupported PNG filter {filter_type}")
            current[index] = value & 0xFF
        decoded[y * row_bytes : (y + 1) * row_bytes] = current
        previous = current

    return width, height, bytes(decoded)


def main() -> None:
    for character_id, source_directory in CHARACTERS.items():
        source_path = SOURCE_ROOT / source_directory / f"{character_id}.png"
        png = source_path.read_bytes()
        _, _, rgba = decode_rgba_png(png)
        alpha_values = set(rgba[3::4])
        if alpha_values != {0, 255}:
            raise ValueError(f"{character_id} must use hard alpha")

        bgra = bytearray(len(rgba))
        for index in range(0, len(rgba), 4):
            bgra[index : index + 4] = (rgba[index + 2], rgba[index + 1], rgba[index], rgba[index + 3])

        output_directory = OUTPUT_ROOT / character_id
        output_directory.mkdir(parents=True, exist_ok=True)
        (output_directory / "sprite.png").write_bytes(png)
        (output_directory / "frames.bgra").write_bytes(bgra)
        print(f"Imported {character_id}")


if __name__ == "__main__":
    main()
