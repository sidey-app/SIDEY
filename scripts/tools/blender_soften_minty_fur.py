"""Make Minty Pup's cream fur matte without flattening eyes or clothing.

Run from Blender with the approved station ``.blend`` already open::

    blender source.blend --background --python blender_soften_minty_fur.py -- \
        output.blend output_metallic_roughness.png

The Meshy character uses one atlas for fur, eyes, nose, and the blue hoodie.
Changing the whole material roughness would therefore make the eyes lifeless.
This script raises only bright, non-blue texels that were not authored as very
glossy details.  The result keeps the generated color and normal maps intact.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import bpy
import numpy as np


TARGET_FUR_ROUGHNESS = 0.82
MAXIMUM_STRENGTH = 0.94


def _arguments() -> tuple[Path, Path]:
    if "--" not in sys.argv:
        raise SystemExit("Expected: -- output.blend output_metallic_roughness.png")
    args = sys.argv[sys.argv.index("--") + 1 :]
    if len(args) != 2:
        raise SystemExit("Expected exactly two output paths")
    return Path(args[0]).resolve(), Path(args[1]).resolve()


def _linear_to_srgb(rgb: np.ndarray) -> np.ndarray:
    return np.where(
        rgb <= 0.0031308,
        rgb * 12.92,
        1.055 * np.power(np.maximum(rgb, 0.0), 1.0 / 2.4) - 0.055,
    )


def _image_pixels(image: bpy.types.Image) -> np.ndarray:
    pixels = np.empty(len(image.pixels), dtype=np.float32)
    image.pixels.foreach_get(pixels)
    return pixels.reshape((-1, 4))


def _texture_node(material: bpy.types.Material, image_name: str) -> bpy.types.ShaderNodeTexImage:
    for node in material.node_tree.nodes:
        if node.type == "TEX_IMAGE" and node.image is not None and node.image.name == image_name:
            return node
    raise RuntimeError(f"Expected image texture node for {image_name}")


def _quantiles(values: np.ndarray) -> list[float]:
    return [round(float(value), 4) for value in np.quantile(values, [0.1, 0.5, 0.9])]


def _soften_fur(
    base_color: bpy.types.Image,
    metallic_roughness: bpy.types.Image,
    output_texture: Path,
) -> tuple[bpy.types.Image, dict[str, object]]:
    if tuple(base_color.size) != tuple(metallic_roughness.size):
        raise RuntimeError("Base-color and metallic-roughness atlases must have matching dimensions")

    base_pixels = _image_pixels(base_color)
    surface_pixels = _image_pixels(metallic_roughness)
    base_srgb = np.clip(_linear_to_srgb(base_pixels[:, :3]), 0.0, 1.0)

    luminance = 0.2126 * base_srgb[:, 0] + 0.7152 * base_srgb[:, 1] + 0.0722 * base_srgb[:, 2]
    blue_dominance = base_srgb[:, 2] - np.maximum(base_srgb[:, 0], base_srgb[:, 1])
    original_roughness = surface_pixels[:, 1].copy()

    # Bright non-blue texels cover the cream fur.  Preserve deliberately glossy
    # pixels (eye highlights and similarly smooth facial details) by fading the
    # mask in only above the source roughness floor.
    light_weight = np.clip((luminance - 0.42) / 0.20, 0.0, 1.0)
    non_blue_weight = 1.0 - np.clip((blue_dominance + 0.015) / 0.08, 0.0, 1.0)
    glossy_detail_protection = np.clip((original_roughness - 0.22) / 0.14, 0.0, 1.0)
    fur_weight = light_weight * non_blue_weight * glossy_detail_protection
    strength = MAXIMUM_STRENGTH * fur_weight

    surface_pixels[:, 1] = original_roughness + (
        TARGET_FUR_ROUGHNESS - original_roughness
    ) * strength
    # Generated fur occasionally contains small non-zero metallic values. Real
    # fur is dielectric, so clear them only where the fur mask is confident.
    surface_pixels[:, 2] *= 1.0 - strength

    softened = metallic_roughness.copy()
    softened.name = "metallic_roughness_soft_fur"
    softened.colorspace_settings.name = "Non-Color"
    softened.pixels.foreach_set(surface_pixels.reshape(-1))
    softened.filepath_raw = str(output_texture)
    softened.file_format = "PNG"
    softened.save()
    softened.pack()

    selected = fur_weight >= 0.5
    if not np.any(selected):
        raise RuntimeError("Fur mask selected no texels")
    report = {
        "atlas_dimensions": [int(base_color.size[0]), int(base_color.size[1])],
        "selected_texels": int(np.count_nonzero(selected)),
        "selected_fraction": round(float(np.mean(selected)), 4),
        "source_roughness_quantiles_10_50_90": _quantiles(original_roughness[selected]),
        "output_roughness_quantiles_10_50_90": _quantiles(surface_pixels[selected, 1]),
        "target_fur_roughness": TARGET_FUR_ROUGHNESS,
        "maximum_strength": MAXIMUM_STRENGTH,
        "protected_details": ["blue hoodie", "dark eyes and nose", "authored glossy highlights"],
    }
    return softened, report


def main() -> None:
    output_blend, output_texture = _arguments()
    output_blend.parent.mkdir(parents=True, exist_ok=True)
    output_texture.parent.mkdir(parents=True, exist_ok=True)
    source_blend = bpy.data.filepath

    material = bpy.data.materials.get("material")
    if material is None or not material.use_nodes:
        raise RuntimeError("Expected the Meshy character material named 'material'")

    base_node = _texture_node(material, "base_color")
    surface_node = _texture_node(material, "metallic_roughness")
    softened, report = _soften_fur(base_node.image, surface_node.image, output_texture)
    surface_node.image = softened

    bpy.ops.wm.save_as_mainfile(filepath=str(output_blend))
    report.update({
        "source_blend": source_blend,
        "output_blend": str(output_blend),
        "output_texture": str(output_texture),
    })
    output_blend.with_name(f"{output_blend.stem}_material_report.json").write_text(
        json.dumps(report, indent=2) + "\n",
        encoding="utf-8",
    )
    print("SIDEY_FUR_MATERIAL_REPORT=" + json.dumps(report, sort_keys=True))


if __name__ == "__main__":
    main()
