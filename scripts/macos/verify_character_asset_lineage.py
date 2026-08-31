#!/usr/bin/env python3
"""Fail a native release when Minty Pup source/output hashes drift from its report."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import sys


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def fail(message: str) -> None:
    raise SystemExit(f"Minty Pup asset lineage failed: {message}")


def main() -> None:
    repository_root = Path(__file__).resolve().parents[2]
    resource_directory = repository_root / "macos/SIDEY/Resources/Characters/MintyPup"
    report_path = resource_directory / "export-report.json"
    if not report_path.is_file():
        fail(f"missing report: {report_path}")

    report = json.loads(report_path.read_text(encoding="utf-8"))
    source_path = repository_root / report["source"]
    if not source_path.is_file():
        fail(f"missing source GLB: {source_path}")
    actual_source_hash = sha256_file(source_path)
    if actual_source_hash != report.get("source_sha256"):
        fail(
            "source GLB SHA-256 mismatch "
            f"(expected {report.get('source_sha256')}, got {actual_source_hash})"
        )

    clips = report.get("clips", [])
    expected_tracks = {"online_idle", "typing", "away_sleep"}
    tracks = {clip.get("track") for clip in clips}
    if len(clips) != 3 or tracks != expected_tracks:
        fail(f"expected exactly {sorted(expected_tracks)}, got {sorted(str(track) for track in tracks)}")

    for clip in clips:
        output_path = resource_directory / clip["file"]
        if not output_path.is_file():
            fail(f"missing USDZ: {output_path}")
        actual_size = output_path.stat().st_size
        if actual_size != clip.get("bytes"):
            fail(
                f"{output_path.name} size mismatch "
                f"(expected {clip.get('bytes')}, got {actual_size})"
            )
        actual_hash = sha256_file(output_path)
        if actual_hash != clip.get("sha256"):
            fail(
                f"{output_path.name} SHA-256 mismatch "
                f"(expected {clip.get('sha256')}, got {actual_hash})"
            )

    print(
        "Verified Minty Pup asset lineage: "
        f"{source_path.name} -> {', '.join(clip['file'] for clip in clips)}"
    )


if __name__ == "__main__":
    try:
        main()
    except (KeyError, TypeError, ValueError, json.JSONDecodeError) as error:
        fail(f"malformed export report: {error}")
