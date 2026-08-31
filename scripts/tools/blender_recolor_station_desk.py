"""Create a station assembly variant with a darker wood desk only."""

from __future__ import annotations

import json
import sys
from pathlib import Path

import bpy


def main() -> None:
    if "--" not in sys.argv:
        raise SystemExit("Expected: -- output.blend")

    args = sys.argv[sys.argv.index("--") + 1 :]
    if len(args) != 1:
        raise SystemExit("Expected exactly one output .blend path")

    output = Path(args[0]).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)

    desk = bpy.data.objects.get("Desk")
    source = bpy.data.materials.get("StationCream")
    if desk is None or desk.type != "MESH" or source is None:
        raise RuntimeError("Expected Desk mesh and StationCream material")

    wood = source.copy()
    wood.name = "DeskWarmWood"
    shader = wood.node_tree.nodes.get("Principled BSDF")
    if shader is None:
        raise RuntimeError("Desk material has no Principled BSDF")

    # Linear RGB: medium warm wood, deliberately darker than the cream chair.
    shader.inputs["Base Color"].default_value = (0.24, 0.10, 0.035, 1.0)
    shader.inputs["Roughness"].default_value = 0.62

    replaced = 0
    for index, material in enumerate(desk.data.materials):
        if material == source:
            desk.data.materials[index] = wood
            replaced += 1

    if replaced != 1:
        raise RuntimeError(f"Expected one StationCream slot on Desk, replaced {replaced}")

    bpy.ops.wm.save_as_mainfile(filepath=str(output))
    report = {
        "output": str(output),
        "object": desk.name,
        "material": wood.name,
        "base_color_linear": [0.24, 0.10, 0.035],
        "chair_unchanged": True,
        "laptop_unchanged": True,
        "character_unchanged": True,
    }
    print("SIDEY_DESK_RECOLOR_REPORT=" + json.dumps(report, sort_keys=True))


if __name__ == "__main__":
    main()
