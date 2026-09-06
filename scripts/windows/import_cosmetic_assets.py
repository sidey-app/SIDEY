#!/usr/bin/env python3

"""Mirror canonical cosmetic PNGs into the Windows renderer and build BGRA caches."""

import shutil
import sys
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPOSITORY_ROOT / "scripts"))

from validate_pixel_assets import parse_rgba_png, rgba_to_bgra  # noqa: E402


def mirror(source: Path, destination: Path, *, bgra: bool, bottom_up: bool = False) -> None:
    destination.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, destination / source.name)
    if bgra:
        width, height, rgba = parse_rgba_png(source)
        converted = rgba_to_bgra(rgba)
        if bottom_up:
            row_bytes = width * 4
            converted = b"".join(
                converted[offset : offset + row_bytes]
                for offset in range((height - 1) * row_bytes, -1, -row_bytes)
            )
        (destination / f"{source.stem}.bgra").write_bytes(converted)


def main() -> None:
    canonical = REPOSITORY_ROOT / "assets" / "v1"
    windows = REPOSITORY_ROOT / "windows" / "src" / "Sidey.Overlay" / "Assets"
    for bubble_id in ("bubble_bunny_pink", "bubble_butter_chick", "bubble_starry_cat"):
        source = canonical / "bubbles" / bubble_id
        destination = windows / "Bubbles" / bubble_id
        mirror(source / "decoration.png", destination, bgra=True)
        mirror(source / "preview.png", destination, bgra=False)
    for throwable_id in (
        "throwable_bouncy_heart",
        "throwable_toy_cannon",
        "throwable_squeaky_duck",
    ):
        source = canonical / "throwables" / throwable_id
        destination = windows / "Throwables" / throwable_id
        mirror(source / "sprite.png", destination, bgra=True, bottom_up=True)
        preview = source / "preview.png"
        if preview.is_file():
            mirror(preview, destination, bgra=False)
        emitter = source / "emitter.png"
        if emitter.is_file():
            mirror(emitter, destination, bgra=True, bottom_up=True)


if __name__ == "__main__":
    main()
