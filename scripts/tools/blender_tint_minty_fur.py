"""Create a warmer SIDEY puppy texture without changing non-fur colors.

Run from Blender with the source .blend already opened::

    blender source.blend --background --python blender_tint_minty_fur.py -- \
        output.blend output_texture.png

The Meshy base-color texture contains the cream fur, blue hoodie, eyes, and
facial details in one atlas.  A global material tint would therefore damage
the hoodie and eyes.  This script selects only bright, already-warm texels and
deepens them to a visible cream/beige while preserving the original shading.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import bpy
import numpy as np


def _arguments() -> tuple[Path, Path]:
    if "--" not in sys.argv:
        raise SystemExit("Expected: -- output.blend output_texture.png")

    args = sys.argv[sys.argv.index("--") + 1 :]
    if len(args) != 2:
        raise SystemExit("Expected exactly two arguments: output.blend output_texture.png")

    return Path(args[0]).resolve(), Path(args[1]).resolve()


def _linear_to_srgb(rgb: np.ndarray) -> np.ndarray:
    return np.where(
        rgb <= 0.0031308,
        rgb * 12.92,
        1.055 * np.power(np.maximum(rgb, 0.0), 1.0 / 2.4) - 0.055,
    )


def _srgb_to_linear(rgb: np.ndarray) -> np.ndarray:
    return np.where(
        rgb <= 0.04045,
        rgb / 12.92,
        np.power((np.maximum(rgb, 0.0) + 0.055) / 1.055, 2.4),
    )


def _tint_fur(source: bpy.types.Image, texture_path: Path) -> bpy.types.Image:
    width, height = source.size
    rgba = np.empty(width * height * 4, dtype=np.float32)
    source.pixels.foreach_get(rgba)
    rgba = rgba.reshape((-1, 4))

    srgb = np.clip(_linear_to_srgb(rgba[:, :3]), 0.0, 1.0)
    luminance = 0.2126 * srgb[:, 0] + 0.7152 * srgb[:, 1] + 0.0722 * srgb[:, 2]
    warmth = np.clip((srgb[:, 0] - srgb[:, 2]) / 0.12, 0.0, 1.0)
    blue_dominance = srgb[:, 2] - np.maximum(srgb[:, 0], srgb[:, 1])

    # Meshy painted several large face/head islands almost neutral white, so a
    # warmth-only selector leaves the forehead white.  Select all bright texels
    # except clearly blue hoodie texels; dark facial details remain protected.
    non_blue_weight = 1.0 - np.clip((blue_dominance + 0.015) / 0.08, 0.0, 1.0)
    light_weight = np.clip((luminance - 0.42) / 0.22, 0.0, 1.0)
    strength = ((0.66 + 0.16 * warmth) * non_blue_weight * light_weight)[:, np.newaxis]

    # Strong enough to read as cream in neutral lighting, while retaining the
    # baked Meshy gradients and avoiding a flat single-color result.
    cream_multiplier = np.array([0.88, 0.72, 0.56], dtype=np.float32)
    corrected = srgb * (1.0 - strength) + (srgb * cream_multiplier) * strength
    rgba[:, :3] = np.clip(_srgb_to_linear(corrected), 0.0, 1.0)

    tinted = source.copy()
    tinted.name = "base_color_warm_cream"
    tinted.pixels.foreach_set(rgba.reshape(-1))
    tinted.filepath_raw = str(texture_path)
    tinted.file_format = "PNG"
    tinted.save()
    tinted.pack()
    return tinted


def main() -> None:
    output_blend, output_texture = _arguments()
    output_blend.parent.mkdir(parents=True, exist_ok=True)
    output_texture.parent.mkdir(parents=True, exist_ok=True)

    material = bpy.data.materials.get("material")
    if material is None or not material.use_nodes:
        raise RuntimeError("Expected the Meshy character material named 'material'")

    texture_node = material.node_tree.nodes.get("Image Texture")
    if texture_node is None or texture_node.image is None:
        raise RuntimeError("Expected a base-color Image Texture node")

    source = texture_node.image
    tinted = _tint_fur(source, output_texture)
    texture_node.image = tinted

    bpy.ops.wm.save_as_mainfile(filepath=str(output_blend))
    report = {
        "source_texture": source.name,
        "tinted_texture": str(output_texture),
        "output_blend": str(output_blend),
        "selection": "bright non-blue texels; dark facial details preserved",
        "cream_multiplier_srgb": [0.88, 0.72, 0.56],
        "maximum_strength": 0.82,
    }
    print("SIDEY_FUR_TINT_REPORT=" + json.dumps(report, sort_keys=True))


if __name__ == "__main__":
    main()
