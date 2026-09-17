#!/usr/bin/env python3

import hashlib
import json
import struct
import subprocess
import sys
import zlib
from dataclasses import dataclass
from pathlib import Path

from catalog_source import load_source


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
ASSET_ROOT = REPOSITORY_ROOT / "assets" / "v1"
MANIFEST_PATH = ASSET_ROOT / "manifest.json"
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


class PixelAssetValidationError(AssertionError):
    """Report a violated pixel asset contract."""


@dataclass(frozen=True)
class NativeMirrorSpec:
    """Describe one canonical asset and its native mirror formats."""

    collection: str
    asset_key: str
    mirror_key: str
    dimensions: tuple[int, int]
    cell_width: int | None
    frame_count: int | None
    baseline_pixels: int | None
    bottom_up: bool


NATIVE_MIRROR_SPECS = (
    NativeMirrorSpec(
        collection="characters",
        asset_key="base",
        mirror_key="character_base",
        dimensions=(240, 24),
        cell_width=24,
        frame_count=10,
        baseline_pixels=3,
        bottom_up=False,
    ),
    NativeMirrorSpec(
        collection="characters",
        asset_key="throw_hit",
        mirror_key="throw_hit",
        dimensions=(192, 24),
        cell_width=24,
        frame_count=8,
        baseline_pixels=3,
        bottom_up=True,
    ),
    NativeMirrorSpec(
        collection="throwables",
        asset_key="sprite",
        mirror_key="throwable",
        dimensions=(192, 16),
        cell_width=16,
        frame_count=12,
        baseline_pixels=None,
        bottom_up=True,
    ),
    NativeMirrorSpec(
        collection="throwables",
        asset_key="emitter",
        mirror_key="cannon_emitter",
        dimensions=(96, 24),
        cell_width=24,
        frame_count=4,
        baseline_pixels=None,
        bottom_up=True,
    ),
    NativeMirrorSpec(
        collection="throwables",
        asset_key="preview",
        mirror_key="cannon_preview",
        dimensions=(176, 56),
        cell_width=None,
        frame_count=None,
        baseline_pixels=None,
        bottom_up=False,
    ),
    NativeMirrorSpec(
        collection="bubbles",
        asset_key="decoration",
        mirror_key="bubble_decoration",
        dimensions=(16, 16),
        cell_width=None,
        frame_count=None,
        baseline_pixels=None,
        bottom_up=False,
    ),
    NativeMirrorSpec(
        collection="bubbles",
        asset_key="preview",
        mirror_key="bubble_preview",
        dimensions=(128, 48),
        cell_width=None,
        frame_count=None,
        baseline_pixels=None,
        bottom_up=False,
    ),
)


def fail(message: str) -> None:
    raise PixelAssetValidationError(message)


def parse_rgba_png(path: Path) -> tuple[int, int, bytes]:
    return decode_rgba_png(path.read_bytes(), str(path))


def decode_rgba_png(data: bytes, path: str) -> tuple[int, int, bytes]:
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
        expected_crc = struct.unpack(
            ">I", data[offset + 8 + length : offset + 12 + length]
        )[0]
        actual_crc = zlib.crc32(kind + payload) & 0xFFFFFFFF
        if actual_crc != expected_crc:
            chunk_name = kind.decode("ascii", errors="replace")
            fail(f"{path}: corrupt {chunk_name} chunk")
        offset += 12 + length

        if kind == b"IHDR":
            (
                width,
                height,
                depth,
                color_type,
                compression,
                filtering,
                interlace,
            ) = struct.unpack(">IIBBBBB", payload)
            png_format = (
                depth,
                color_type,
                compression,
                filtering,
                interlace,
            )
            if png_format != (8, 6, 0, 0, 0):
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


def apply_filter(
    filter_type: int,
    row: bytearray,
    previous: bytearray,
    bpp: int,
    path: Path,
) -> None:
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


def validate_entry(
    entry: dict,
    expected_size: tuple[int, int],
    frame_width: int | None = None,
    frame_count: int | None = None,
) -> None:
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
    has_frame_geometry = frame_width is not None and frame_count is not None
    if has_frame_geometry and width != frame_width * frame_count:
        fail(f"{path}: frame geometry mismatch")

    alpha = rgba[3::4]
    if set(alpha) != {0, 255}:
        fail(
            f"{path}: alpha must be hard and contain transparent and "
            "opaque pixels"
        )


def validate_action_baselines(
    entries: list[dict],
    baseline_pixels: int,
) -> None:
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
                fail(
                    f"{path}: frame {frame} does not preserve the "
                    f"{baseline_pixels}px baseline"
                )


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
                fail(
                    f"{path}: frame {frame} does not preserve the "
                    f"{baseline_pixels}px baseline"
                )
    return path, rgba


def mirror_path(pattern: str, entry: dict) -> Path:
    return REPOSITORY_ROOT / pattern.format(**entry)


def validate_supported_platforms(entry: dict) -> set[str]:
    platforms = entry.get("supported_platforms")
    if not isinstance(platforms, list) or not platforms:
        identifier = entry.get("id", "<unknown>")
        fail(
            f"{identifier}: supported_platforms must be a non-empty list"
        )
    platform_set = set(platforms)
    supported = {"macos", "windows", "checkout"}
    if len(platform_set) != len(platforms) or not platform_set <= supported:
        fail(f"{entry['id']}: invalid or duplicate supported platform")
    return platform_set


def mirror_platform(pattern: str) -> str:
    if pattern.startswith("macos/"):
        return "macos"
    if pattern.startswith("windows/"):
        return "windows"
    if pattern.startswith("website/"):
        return "checkout"
    fail(f"mirror path has no supported platform: {pattern}")


def validate_declared_web_png_mirrors(
    source: Path,
    patterns: list[str],
    entry: dict,
    *,
    canonical_only: bool,
) -> None:
    platforms = validate_supported_platforms(entry)
    if canonical_only:
        return
    for pattern in patterns:
        if mirror_platform(pattern) == "checkout" and "checkout" in platforms:
            validate_png_mirror(source, mirror_path(pattern, entry))


def validate_png_mirror(source: Path, mirror: Path) -> None:
    if not mirror.is_file():
        relative = mirror.relative_to(REPOSITORY_ROOT)
        fail(f"missing PNG mirror: {relative}")
    if mirror.read_bytes() != source.read_bytes():
        relative = mirror.relative_to(REPOSITORY_ROOT)
        fail(f"PNG mirror differs from canonical source: {relative}")


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


def validate_bgra_mirror(
    rgba: bytes,
    mirror: Path,
    *,
    bottom_up: bool = False,
    row_count: int | None = None,
) -> None:
    if not mirror.is_file():
        relative = mirror.relative_to(REPOSITORY_ROOT)
        fail(f"missing BGRA mirror: {relative}")
    data = mirror.read_bytes()
    expected = rgba_to_bgra(rgba)
    if bottom_up:
        if row_count is None:
            relative = mirror.relative_to(REPOSITORY_ROOT)
            fail(f"missing BGRA row count: {relative}")
        row_bytes = len(expected) // row_count
        expected = b"".join(
            expected[offset : offset + row_bytes]
            for offset in range(len(expected) - row_bytes, -1, -row_bytes)
        )
    if data != expected:
        relative = mirror.relative_to(REPOSITORY_ROOT)
        fail(f"BGRA mirror differs from canonical pixels: {relative}")


def validate_windows_character_manifest(
    entry: dict,
    rgba: bytes,
    root: Path | None = None,
) -> None:
    path = (
        (root or REPOSITORY_ROOT)
        / "windows/src/Sidey.Overlay/Assets/Characters"
        / entry["id"]
        / "manifest.json"
    )
    if not path.is_file():
        fail(f"missing Windows character manifest: {path}")
    data = json.loads(path.read_text(encoding="utf-8"))
    source_id_matches = data.get("character_id") == entry["id"]
    source_hash_matches = data.get("sha256") == entry["base"]["sha256"]
    if not source_id_matches or not source_hash_matches:
        fail(f"{path}: source ID or SHA-256 differs from central manifest")
    bgra_path = path.with_name("base.bgra")
    runtime = data.get("runtime_bgra", {})
    if runtime.get("byte_length") != len(rgba):
        fail(f"{path}: runtime BGRA byte length is stale")
    runtime_hash = hashlib.sha256(bgra_path.read_bytes()).hexdigest()
    if runtime.get("sha256") != runtime_hash:
        fail(f"{path}: runtime BGRA SHA-256 is stale")


def pinned_asset_bytes(root: Path, commit: str, path: str) -> bytes:
    # Catalog JSON normalizes CRLF. PNGs retain every original byte.
    result = subprocess.run(
        ["git", "show", f"{commit}:{path}"],
        cwd=root,
        capture_output=True,
    )
    if result.returncode:
        fail(f"pinned asset is unavailable at {commit}: {path}")
    return result.stdout


def required_native_ids(
    manifest: dict,
    current_manifest: dict,
    platform: str,
    collection: str,
) -> set[str]:
    """Return the pinned and current native asset identifiers."""
    identifiers = {
        entry["id"]
        for source in (manifest, current_manifest)
        for entry in source[collection]
        if platform in validate_supported_platforms(entry)
    }
    pinned_ids = {entry["id"] for entry in manifest[collection]}
    missing = identifiers - pinned_ids
    if missing:
        fail(
            f"{platform}: declared native assets are missing from the "
            f"reviewed pin: {sorted(missing)}"
        )
    return identifiers


def native_mirror_patterns(
    manifest: dict,
    entry: dict,
    spec: NativeMirrorSpec,
    platform: str,
) -> tuple[list[str], list[str]]:
    """Return PNG and BGRA patterns that belong to one platform."""
    mirrors = manifest["mirrors"]
    png_patterns = list(mirrors.get(f"{spec.mirror_key}_png", []))
    if spec.collection == "characters" and spec.asset_key == "base":
        png_patterns += entry.get("additional_base_mirrors", [])
    png_patterns = [
        pattern
        for pattern in png_patterns
        if mirror_platform(pattern) == platform
    ]
    bgra_patterns = [
        pattern
        for pattern in mirrors.get(f"{spec.mirror_key}_bgra", [])
        if mirror_platform(pattern) == platform
    ]
    return png_patterns, bgra_patterns


def reviewed_asset_bytes(
    root: Path,
    pin: dict | None,
    asset: dict,
    platform: str,
) -> tuple[str, bytes]:
    """Read and authenticate one platform's reviewed canonical asset."""
    relative = Path(asset["path"])
    if relative.is_absolute() or ".." in relative.parts:
        fail(f"unsafe pinned asset path: {relative}")

    path = f"assets/v1/{relative.as_posix()}"
    if pin:
        data = pinned_asset_bytes(root, pin["source_commit"], path)
    else:
        data = (root / path).read_bytes()
    if hashlib.sha256(data).hexdigest() != asset["sha256"]:
        fail(f"{platform}: reviewed asset SHA-256 mismatch: {path}")
    return path, data


def validate_reviewed_baseline(
    rgba: bytes,
    width: int,
    height: int,
    spec: NativeMirrorSpec,
    platform: str,
    path: str,
) -> None:
    """Check every frame against the reviewed baseline contract."""
    if spec.baseline_pixels is None:
        return

    for frame in range(spec.frame_count):
        opaque_rows = []
        for row in range(height):
            start = (row * width + frame * spec.cell_width) * 4 + 3
            end = (row * width + (frame + 1) * spec.cell_width) * 4
            if any(rgba[start:end:4]):
                opaque_rows.append(row)
        expected_row = height - spec.baseline_pixels - 1
        if not opaque_rows or max(opaque_rows) != expected_row:
            fail(
                f"{platform}: reviewed asset baseline differs: {path} "
                f"frame {frame}"
            )


def validate_reviewed_asset(
    data: bytes,
    path: str,
    platform: str,
    spec: NativeMirrorSpec,
) -> tuple[int, bytes]:
    """Decode and validate geometry, alpha, and baseline properties."""
    width, height, rgba = decode_rgba_png(data, path)
    valid_geometry = (width, height) == spec.dimensions
    if not valid_geometry or set(rgba[3::4]) != {0, 255}:
        fail(f"{platform}: reviewed asset geometry/alpha differs: {path}")
    validate_reviewed_baseline(
        rgba,
        width,
        height,
        spec,
        platform,
        path,
    )
    return height, rgba


def validate_native_mirror_files(
    root: Path,
    entry: dict,
    spec: NativeMirrorSpec,
    platform: str,
    data: bytes,
    rgba: bytes,
    height: int,
    png_patterns: list[str],
    bgra_patterns: list[str],
) -> int:
    """Validate the platform copies for one reviewed asset."""
    count = 0
    for pattern in png_patterns:
        native = root / pattern.format(**entry)
        if not native.is_file() or native.read_bytes() != data:
            fail(
                f"{platform}: PNG mirror differs from reviewed source: "
                f"{native}"
            )
        count += 1
    for pattern in bgra_patterns:
        validate_bgra_mirror(
            rgba,
            root / pattern.format(**entry),
            bottom_up=spec.bottom_up,
            row_count=height,
        )
        count += 1
    return count


def validate_native_mirrors(
    root: Path | None = None,
    platforms=("macos", "windows"),
) -> int:
    """Check native mirrors against each bundle's reviewed source.

    Verify support declared by either current or pinned manifest, while using
    pinned bytes. A later support declaration must not hide a mirror whose pin
    still describes that asset as checkout-only. Removed pinned assets also
    stay checked. Unpinned bundles require current canonical bytes.
    """
    root = root or REPOSITORY_ROOT
    current_manifest_path = root / "assets/v1/manifest.json"
    current_manifest = json.loads(
        current_manifest_path.read_text(encoding="utf-8")
    )
    count = 0
    for platform in platforms:
        _, manifest, pin = load_source(root, platform)
        required_ids = {}
        for collection in ("characters", "throwables", "bubbles"):
            required_ids[collection] = required_native_ids(
                manifest,
                current_manifest,
                platform,
                collection,
            )
        for spec in NATIVE_MIRROR_SPECS:
            for entry in manifest[spec.collection]:
                if entry["id"] not in required_ids[spec.collection]:
                    continue
                optional_throwable = (
                    spec.collection == "throwables"
                    and spec.asset_key in ("emitter", "preview")
                )
                if optional_throwable and spec.asset_key not in entry:
                    continue
                png_patterns, bgra_patterns = native_mirror_patterns(
                    manifest,
                    entry,
                    spec,
                    platform,
                )
                if not png_patterns and not bgra_patterns:
                    continue
                path, data = reviewed_asset_bytes(
                    root,
                    pin,
                    entry[spec.asset_key],
                    platform,
                )
                height, rgba = validate_reviewed_asset(
                    data,
                    path,
                    platform,
                    spec,
                )
                count += validate_native_mirror_files(
                    root,
                    entry,
                    spec,
                    platform,
                    data,
                    rgba,
                    height,
                    png_patterns,
                    bgra_patterns,
                )
                is_windows_character_base = (
                    platform == "windows"
                    and spec.collection == "characters"
                    and spec.asset_key == "base"
                )
                if is_windows_character_base:
                    validate_windows_character_manifest(entry, rgba, root)
    return count


def parse_arguments(arguments: list[str]) -> bool:
    """Return whether validation should stop at canonical assets."""
    canonical_only = "--canonical-only" in arguments
    unknown_arguments = set(arguments) - {"--canonical-only"}
    if unknown_arguments:
        fail(f"unknown arguments: {sorted(unknown_arguments)}")
    return canonical_only


def validate_manifest_header(manifest: dict) -> None:
    """Validate schema approval and the shared pixel format contract."""
    approved_schema = (
        manifest["schema_version"] == 2
        and manifest["approval"]["status"] == "approved"
    )
    if not approved_schema:
        fail("asset manifest is not the approved schema v2 contract")
    expected_format = {
        "color_space": "sRGB",
        "bit_depth": 8,
        "color_type": "RGBA",
        "alpha": "hard",
        "background": "transparent",
        "filtering": "nearest",
        "runtime_shadows": False,
    }
    if manifest["format"] != expected_format:
        fail("pixel format contract is incomplete or unsupported")


def validate_sheet_contracts(manifest: dict) -> None:
    """Validate sheet geometry, frame ranges, and rotation center."""
    expected_sheets = {
        "base_sheet": ((24, 24), (240, 24), 10, 3),
        "throw_hit_sheet": ((24, 24), (192, 24), 8, 3),
        "throwable_sheet": ((16, 16), (192, 16), 12, None),
    }
    for key, expected in expected_sheets.items():
        cell_size, sheet_size, frame_count, baseline = expected
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

    expected_base_frames = {
        "idle": [0, 1],
        "walk": [2, 5],
        "doze": [6, 7],
        "offline": [8, 9],
    }
    if manifest["base_sheet"]["frames"] != expected_base_frames:
        fail("base frame ranges are invalid")

    expected_action_frames = {
        "throw_prepare": [0, 0],
        "throw_exert": [1, 1],
        "throw_release": [2, 2],
        "throw_follow_through": [3, 3],
        "hit_contact": [4, 4],
        "hit_squash": [5, 5],
        "hit_rebound": [6, 6],
        "hit_recover": [7, 7],
    }
    if manifest["throw_hit_sheet"]["frames"] != expected_action_frames:
        fail("throw/hit frame ranges are invalid")

    expected_throwable_frames = {
        "rotation": [0, 7],
        "impact_contact": [8, 8],
        "impact_squash": [9, 9],
        "impact_bounce": [10, 10],
        "impact_recover": [11, 11],
    }
    if manifest["throwable_sheet"]["frames"] != expected_throwable_frames:
        fail("throwable frame ranges are invalid")


def validate_collection_ids(
    manifest: dict,
) -> tuple[list[dict], list[dict], list[dict]]:
    """Validate collection presence and identifier uniqueness."""
    characters = manifest["characters"]
    throwables = manifest["throwables"]
    bubbles = manifest["bubbles"]
    if not characters or not throwables or not bubbles:
        fail("manifest asset collections must not be empty")
    if len({entry["id"] for entry in characters}) != len(characters):
        fail("duplicate character ID")
    if len({entry["id"] for entry in throwables}) != len(throwables):
        fail("duplicate throwable ID")
    if len({entry["id"] for entry in bubbles}) != len(bubbles):
        fail("duplicate bubble ID")
    return characters, throwables, bubbles


def validate_mirror_contract(mirrors: dict) -> None:
    """Validate native BGRA row ordering."""
    expected_row_order = {
        "character_base": "top_down",
        "throw_hit": "bottom_up",
        "throwable": "bottom_up",
        "bubble_decoration": "top_down",
        "cannon_emitter": "bottom_up",
    }
    if mirrors["bgra_row_order"] != expected_row_order:
        fail("unsupported BGRA mirror row order")


def validate_character_assets(
    characters: list[dict],
    mirrors: dict,
    *,
    canonical_only: bool,
) -> set[Path]:
    """Validate character sheets and their declared web mirrors."""
    managed_pngs: set[Path] = set()
    for entry in characters:
        validate_supported_platforms(entry)
        if entry["base"]["path"] != f"characters/{entry['id']}/base.png":
            fail(f"non-canonical base path for {entry['id']}")
        expected_action_path = f"characters/{entry['id']}/throw_hit.png"
        if entry["throw_hit"]["path"] != expected_action_path:
            fail(f"non-canonical throw/hit path for {entry['id']}")
        base_path, _ = validate_sheet(entry["base"], (240, 24), 24, 10, 3)
        action_path, _ = validate_sheet(
            entry["throw_hit"],
            (192, 24),
            24,
            8,
            3,
        )
        managed_pngs.update((base_path, action_path))
        validate_declared_web_png_mirrors(
            base_path,
            mirrors["character_base_png"],
            entry,
            canonical_only=canonical_only,
        )
        validate_declared_web_png_mirrors(
            base_path,
            entry.get("additional_base_mirrors", []),
            entry,
            canonical_only=canonical_only,
        )
        validate_declared_web_png_mirrors(
            action_path,
            mirrors["throw_hit_png"],
            entry,
            canonical_only=canonical_only,
        )
    return managed_pngs


def validate_throwable_assets(
    throwables: list[dict],
    mirrors: dict,
    *,
    canonical_only: bool,
) -> set[Path]:
    """Validate throwable sheets, previews, and declared web mirrors."""
    managed_pngs: set[Path] = set()
    for entry in throwables:
        validate_supported_platforms(entry)
        if entry["sprite"]["path"] != f"throwables/{entry['id']}/sprite.png":
            fail(f"non-canonical throwable path for {entry['id']}")
        sprite_path, _ = validate_sheet(entry["sprite"], (192, 16), 16, 12)
        managed_pngs.add(sprite_path)
        validate_declared_web_png_mirrors(
            sprite_path,
            mirrors["throwable_png"],
            entry,
            canonical_only=canonical_only,
        )
        if "emitter" in entry:
            emitter_path, _ = validate_sheet(entry["emitter"], (96, 24), 24, 4)
            managed_pngs.add(emitter_path)
            validate_declared_web_png_mirrors(
                emitter_path,
                mirrors["cannon_emitter_png"],
                entry,
                canonical_only=canonical_only,
            )
        if "preview" in entry:
            validate_entry(entry["preview"], (176, 56))
            preview_path = ASSET_ROOT / entry["preview"]["path"]
            managed_pngs.add(preview_path)
            validate_declared_web_png_mirrors(
                preview_path,
                mirrors["cannon_preview_png"],
                entry,
                canonical_only=canonical_only,
            )
    return managed_pngs


def validate_bubble_assets(
    bubbles: list[dict],
    mirrors: dict,
    *,
    canonical_only: bool,
) -> set[Path]:
    """Validate bubble images, contrast, and declared web mirrors."""
    managed_pngs: set[Path] = set()
    for entry in bubbles:
        validate_supported_platforms(entry)
        expected_decoration = f"bubbles/{entry['id']}/decoration.png"
        if entry["decoration"]["path"] != expected_decoration:
            fail(f"non-canonical bubble decoration path for {entry['id']}")
        if entry["preview"]["path"] != f"bubbles/{entry['id']}/preview.png":
            fail(f"non-canonical bubble preview path for {entry['id']}")
        validate_entry(entry["decoration"], (16, 16))
        validate_entry(entry["preview"], (128, 48))
        if float(entry["contrast_ratio"]) < 7.0:
            fail(
                f"{entry['id']}: text contrast must meet WCAG AAA for "
                "normal text"
            )
        decoration_path = ASSET_ROOT / entry["decoration"]["path"]
        preview_path = ASSET_ROOT / entry["preview"]["path"]
        managed_pngs.update((decoration_path, preview_path))
        validate_declared_web_png_mirrors(
            decoration_path,
            mirrors["bubble_decoration_png"],
            entry,
            canonical_only=canonical_only,
        )
        validate_declared_web_png_mirrors(
            preview_path,
            mirrors["bubble_preview_png"],
            entry,
            canonical_only=canonical_only,
        )
    return managed_pngs


def validate_character_mapping(
    characters: list[dict],
    throwables: list[dict],
) -> tuple[set[str], set[str], dict[str, str]]:
    """Validate and return the character-to-throwable mapping."""
    character_ids = {entry["id"] for entry in characters}
    throwable_ids = {entry["id"] for entry in throwables}
    mapping = {entry["id"]: entry["throwable_id"] for entry in characters}
    has_all_characters = set(mapping) == character_ids
    has_known_throwables = set(mapping.values()) <= throwable_ids
    if not has_all_characters or not has_known_throwables:
        fail("character-to-throwable mapping is incomplete")
    return character_ids, throwable_ids, mapping


def validate_licensing(
    manifest: dict,
    character_ids: set[str],
    throwable_ids: set[str],
    bubble_ids: set[str],
    mapping: dict[str, str],
) -> None:
    """Validate paid schedules and cross-asset licensing boundaries."""
    licensing = manifest["licensing"]
    if licensing.get("paid_asset_license") != "../PAID_ASSET_LICENSE.md":
        fail("paid asset license path is missing or unsupported")
    paid_asset_license = ASSET_ROOT / licensing["paid_asset_license"]
    if not paid_asset_license.is_file():
        fail("paid asset license file is missing")

    paid_character_list = licensing["paid_character_ids"]
    paid_throwable_list = licensing["paid_throwable_ids"]
    paid_bubble_list = licensing["paid_bubble_ids"]
    paid_lists = (
        paid_character_list,
        paid_throwable_list,
        paid_bubble_list,
    )
    if not all(isinstance(values, list) for values in paid_lists):
        fail("paid asset ID schedules must be lists")
    paid_character_ids = set(paid_character_list)
    paid_throwable_ids = set(paid_throwable_list)
    paid_bubble_ids = set(paid_bubble_list)
    if len(paid_character_ids) != len(paid_character_list):
        fail("duplicate paid character ID")
    if len(paid_throwable_ids) != len(paid_throwable_list):
        fail("duplicate paid throwable ID")
    if len(paid_bubble_ids) != len(paid_bubble_list):
        fail("duplicate paid bubble ID")
    if not paid_character_ids or not paid_character_ids <= character_ids:
        fail(
            "paid character schedule is empty or references an unknown "
            "character"
        )
    if not paid_throwable_ids or not paid_throwable_ids <= throwable_ids:
        fail(
            "paid throwable schedule is empty or references an unknown "
            "throwable"
        )
    if not paid_bubble_ids or not paid_bubble_ids <= bubble_ids:
        fail(
            "paid bubble schedule is empty or references an unknown bubble"
        )
    paid_character_throwables = {
        mapping[character_id] for character_id in paid_character_ids
    }
    if not paid_character_throwables <= paid_throwable_ids:
        fail("a paid character references an unlicensed throwable")
    free_character_ids = character_ids - paid_character_ids
    free_character_throwables = {
        mapping[character_id] for character_id in free_character_ids
    }
    if free_character_throwables & paid_throwable_ids:
        fail("a free character references a paid throwable")


def validate_fallbacks(
    manifest: dict,
    character_ids: set[str],
    throwable_ids: set[str],
) -> None:
    """Validate fallback identifiers."""
    if manifest["fallbacks"]["character_id"] not in character_ids:
        fail("character fallback is missing")
    if manifest["fallbacks"]["throwable_id"] not in throwable_ids:
        fail("throwable fallback is missing")


def validate_previewer_defaults(
    characters: list[dict],
    throwables: list[dict],
    mirrors: dict,
) -> None:
    """Validate previewer defaults against canonical source assets."""
    hamster = next(
        entry for entry in characters if entry["id"] == "pixel_hamster"
    )
    patch_ball = next(
        entry for entry in throwables if entry["id"] == "patch_soft_ball"
    )
    defaults = mirrors["previewer_defaults"]
    validate_png_mirror(
        ASSET_ROOT / hamster["throw_hit"]["path"],
        REPOSITORY_ROOT / defaults["pixel_hamster_throw_hit"],
    )
    validate_png_mirror(
        ASSET_ROOT / patch_ball["sprite"]["path"],
        REPOSITORY_ROOT / defaults["patch_soft_ball"],
    )


def validate_reference_asset(manifest: dict) -> None:
    """Validate the official visual reference image."""
    reference = ASSET_ROOT / manifest["reference"]["path"]
    if not reference.is_file():
        fail("official reference image SHA-256 mismatch")
    reference_hash = hashlib.sha256(reference.read_bytes()).hexdigest()
    if reference_hash != manifest["reference"]["sha256"]:
        fail("official reference image SHA-256 mismatch")


def validate_canonical_inventory(managed_pngs: set[Path]) -> None:
    """Reject unlisted canonical PNGs and missing manifest entries."""
    actual_pngs = (
        set((ASSET_ROOT / "characters").glob("*/*.png"))
        | set((ASSET_ROOT / "throwables").glob("*/*.png"))
        | set((ASSET_ROOT / "bubbles").glob("*/*.png"))
    )
    if actual_pngs != managed_pngs:
        mismatched_pngs = actual_pngs ^ managed_pngs
        paths = sorted(
            str(path.relative_to(ASSET_ROOT))
            for path in mismatched_pngs
        )
        fail(f"canonical assets and manifest differ: {paths}")


def validate_manifest_assets(
    manifest: dict,
    *,
    canonical_only: bool,
) -> tuple[list[dict], list[dict], list[dict]]:
    """Run manifest and canonical asset validation stages in order."""
    validate_manifest_header(manifest)
    validate_sheet_contracts(manifest)
    characters, throwables, bubbles = validate_collection_ids(manifest)

    mirrors = manifest["mirrors"]
    validate_mirror_contract(mirrors)
    managed_pngs = validate_character_assets(
        characters,
        mirrors,
        canonical_only=canonical_only,
    )
    managed_pngs.update(
        validate_throwable_assets(
            throwables,
            mirrors,
            canonical_only=canonical_only,
        )
    )
    managed_pngs.update(
        validate_bubble_assets(
            bubbles,
            mirrors,
            canonical_only=canonical_only,
        )
    )

    character_ids, throwable_ids, mapping = validate_character_mapping(
        characters,
        throwables,
    )
    bubble_ids = {entry["id"] for entry in bubbles}
    validate_licensing(
        manifest,
        character_ids,
        throwable_ids,
        bubble_ids,
        mapping,
    )
    validate_fallbacks(manifest, character_ids, throwable_ids)
    validate_previewer_defaults(characters, throwables, mirrors)
    validate_reference_asset(manifest)
    validate_canonical_inventory(managed_pngs)
    return characters, throwables, bubbles


def main() -> int:
    canonical_only = parse_arguments(sys.argv[1:])
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    characters, throwables, bubbles = validate_manifest_assets(
        manifest,
        canonical_only=canonical_only,
    )

    if not canonical_only:
        native_count = validate_native_mirrors()
        print(
            f"Verified {native_count} native mirrors against their reviewed "
            "platform source pins."
        )

    mirror_scope = (
        "canonical assets only" if canonical_only else "all declared mirrors"
    )
    print(
        f"Validated {len(characters)} base sheets, "
        f"{len(characters)} throw/hit sheets, {len(throwables)} throwables, "
        f"{len(bubbles)} bubbles, "
        f"{mirror_scope}"
        ", baselines, mappings, paid asset licensing, formats, and SHA-256 "
        "values."
    )
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (
        PixelAssetValidationError,
        KeyError,
        ValueError,
        json.JSONDecodeError,
        OSError,
        zlib.error,
    ) as error:
        print(f"pixel asset validation failed: {error}", file=sys.stderr)
        sys.exit(1)
