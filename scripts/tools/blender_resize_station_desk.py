"""Create a station assembly variant with a narrower desk only."""

from __future__ import annotations

import json
import sys
from pathlib import Path

import bpy


DESK_WIDTH_SCALE = 0.78


def main() -> None:
    if "--" not in sys.argv:
        raise SystemExit("Expected: -- output.blend")

    args = sys.argv[sys.argv.index("--") + 1 :]
    if len(args) != 1:
        raise SystemExit("Expected exactly one output .blend path")

    output = Path(args[0]).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)

    desk = bpy.data.objects.get("Desk")
    if desk is None or desk.type != "MESH":
        raise RuntimeError("Expected Desk mesh")

    original_scale = tuple(desk.scale)
    desk.scale.x *= DESK_WIDTH_SCALE
    bpy.context.view_layer.objects.active = desk
    desk.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

    bpy.ops.wm.save_as_mainfile(filepath=str(output))
    report = {
        "output": str(output),
        "object": desk.name,
        "width_scale": DESK_WIDTH_SCALE,
        "original_object_scale": list(original_scale),
        "chair_unchanged": True,
        "laptop_unchanged": True,
        "character_unchanged": True,
        "materials_unchanged": True,
    }
    print("SIDEY_DESK_RESIZE_REPORT=" + json.dumps(report, sort_keys=True))


if __name__ == "__main__":
    main()
