"""Concatenate review movies with Blender's bundled FFmpeg support."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import bpy


def _arguments() -> argparse.Namespace:
    try:
        separator = sys.argv.index("--")
    except ValueError as error:
        raise SystemExit("Expected arguments after --") from error
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path)
    parser.add_argument("sources", type=Path, nargs="+")
    return parser.parse_args(sys.argv[separator + 1 :])


def main() -> None:
    args = _arguments()
    output = args.output.expanduser().resolve()
    sources = [source.expanduser().resolve() for source in args.sources]
    missing = [str(source) for source in sources if not source.is_file()]
    if missing:
        raise SystemExit(f"Missing input movies: {missing}")

    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    editor = scene.sequence_editor_create()
    current_frame = 1
    durations: dict[str, int] = {}
    for index, source in enumerate(sources):
        strip = editor.sequences.new_movie(
            name=source.stem,
            filepath=str(source),
            channel=index + 1,
            frame_start=current_frame,
        )
        durations[source.name] = strip.frame_final_duration
        current_frame += strip.frame_final_duration

    scene.frame_start = 1
    scene.frame_end = current_frame - 1
    scene.render.resolution_x = 720
    scene.render.resolution_y = 720
    scene.render.resolution_percentage = 100
    scene.render.fps = 30
    scene.render.image_settings.file_format = "FFMPEG"
    scene.render.image_settings.color_mode = "RGB"
    scene.render.ffmpeg.format = "QUICKTIME"
    scene.render.ffmpeg.codec = "H264"
    scene.render.ffmpeg.constant_rate_factor = "MEDIUM"
    scene.render.ffmpeg.ffmpeg_preset = "GOOD"
    scene.render.filepath = str(output.with_suffix(""))
    output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.render.render(animation=True)
    generated = sorted(output.parent.glob(f"{output.stem}????-????.mov"))
    if len(generated) != 1:
        raise SystemExit(f"Expected one concatenated movie for {output.name}, found {generated}")
    generated[0].replace(output)
    print(
        "SIDEY_CONCAT_REPORT="
        + json.dumps(
            {
                "output": str(output),
                "sources": [str(source) for source in sources],
                "durations": durations,
                "frames": scene.frame_end,
                "fps": scene.render.fps,
            },
            ensure_ascii=False,
            sort_keys=True,
        )
    )


if __name__ == "__main__":
    main()
