"""Create the bright, compact animated-style Minty Pup desk station.

Run from Blender with the approved narrow-desk assembly already open::

    blender source.blend --background --python blender_stylize_minty_station.py -- \
        output.blend

The adjustment is intentionally limited to static props.  It narrows the desk
once more, brightens the shared desk/chair cream, and turns the laptop into a
soft cool silver while preserving the dark logo and keyboard details.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import bpy


DESK_WIDTH_SCALE_FROM_V2 = 0.88
DESK_WIDTH_SCALE_FROM_ORIGINAL = 0.78 * DESK_WIDTH_SCALE_FROM_V2
STATION_CREAM_LINEAR = (1.0, 0.72, 0.42, 1.0)
STATION_CREAM_ROUGHNESS = 0.92
LAPTOP_SILVER_LINEAR = (0.90, 0.95, 1.0, 1.0)
LAPTOP_SILVER_ROUGHNESS = 0.52
LAPTOP_SILVER_METALLIC = 0.28


def _argument() -> Path:
    if "--" not in sys.argv:
        raise SystemExit("Expected: -- output.blend")
    args = sys.argv[sys.argv.index("--") + 1 :]
    if len(args) != 1:
        raise SystemExit("Expected exactly one output .blend path")
    return Path(args[0]).resolve()


def _shader(material_name: str) -> bpy.types.ShaderNodeBsdfPrincipled:
    material = bpy.data.materials.get(material_name)
    if material is None or not material.use_nodes:
        raise RuntimeError(f"Expected node material {material_name}")
    shader = material.node_tree.nodes.get("Principled BSDF")
    if shader is None:
        raise RuntimeError(f"Expected Principled BSDF in {material_name}")
    return shader


def main() -> None:
    output = _argument()
    output.parent.mkdir(parents=True, exist_ok=True)
    source = bpy.data.filepath

    desk = bpy.data.objects.get("Desk")
    if desk is None or desk.type != "MESH":
        raise RuntimeError("Expected Desk mesh")
    width_before = float(desk.dimensions.x)
    desk.scale.x *= DESK_WIDTH_SCALE_FROM_V2
    bpy.ops.object.select_all(action="DESELECT")
    desk.select_set(True)
    bpy.context.view_layer.objects.active = desk
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    width_after = float(desk.dimensions.x)

    cream = _shader("StationCream")
    cream.inputs["Base Color"].default_value = STATION_CREAM_LINEAR
    cream.inputs["Roughness"].default_value = STATION_CREAM_ROUGHNESS
    cream.inputs["Metallic"].default_value = 0.0

    silver = _shader("LaptopSilver")
    silver.inputs["Base Color"].default_value = LAPTOP_SILVER_LINEAR
    silver.inputs["Roughness"].default_value = LAPTOP_SILVER_ROUGHNESS
    silver.inputs["Metallic"].default_value = LAPTOP_SILVER_METALLIC

    bpy.ops.wm.save_as_mainfile(filepath=str(output))
    report = {
        "source": source,
        "output": str(output),
        "desk_width_before": round(width_before, 4),
        "desk_width_after": round(width_after, 4),
        "desk_width_scale_from_v2": DESK_WIDTH_SCALE_FROM_V2,
        "desk_width_scale_from_original": round(DESK_WIDTH_SCALE_FROM_ORIGINAL, 4),
        "materials": {
            "StationCream": {
                "base_color_linear": list(STATION_CREAM_LINEAR[:3]),
                "roughness": STATION_CREAM_ROUGHNESS,
                "metallic": 0.0,
                "affects": ["Desk", "Chair"],
            },
            "LaptopSilver": {
                "base_color_linear": list(LAPTOP_SILVER_LINEAR[:3]),
                "roughness": LAPTOP_SILVER_ROUGHNESS,
                "metallic": LAPTOP_SILVER_METALLIC,
                "affects": ["LaptopBase", "LaptopLid", "station trim"],
            },
        },
        "unchanged": [
            "character geometry and rig",
            "character base color",
            "dark laptop logo and keyboard details",
            "animation timing",
        ],
    }
    output.with_name(f"{output.stem}_style_report.json").write_text(
        json.dumps(report, indent=2) + "\n",
        encoding="utf-8",
    )
    print("SIDEY_STATION_STYLE_REPORT=" + json.dumps(report, sort_keys=True))


if __name__ == "__main__":
    main()
