#!/usr/bin/env python3
"""Validate SIDEY's authoritative platform release manifests and their mirrors."""

from __future__ import annotations

import argparse
import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
SEMVER = re.compile(r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$")
SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"


class ConsistencyError(RuntimeError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ConsistencyError(message)


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def load_manifest(platform: str) -> dict[str, object]:
    path = ROOT / "release" / f"{platform}.json"
    data = json.loads(path.read_text(encoding="utf-8"))
    required = {"schema", "platform", "channel", "version"}
    if platform == "macos":
        required.add("build")
    require(set(data) == required, f"{path} must contain exactly {sorted(required)}")
    require(data["schema"] == 1, f"{path} has an unsupported schema")
    require(data["platform"] == platform, f"{path} has the wrong platform")
    require(data["channel"] == "production", f"{path} must use the production channel")
    require(
        isinstance(data["version"], str) and SEMVER.fullmatch(data["version"]),
        f"{path} must contain a stable semantic version",
    )
    if platform == "macos":
        require(
            isinstance(data["build"], int) and data["build"] > 0,
            f"{path} must contain a positive numeric build",
        )
    return data


def project_values_for_bundle_identifier(
    source: str, bundle_identifier: str, setting: str
) -> set[str]:
    values: set[str] = set()
    matching_configurations = 0
    for body in re.findall(r"buildSettings = \{(.*?)\n\s*\};", source, re.DOTALL):
        settings = dict(re.findall(r"\b([A-Z][A-Z0-9_]*) = ([^;]+);", body))
        configured_bundle = settings.get("PRODUCT_BUNDLE_IDENTIFIER", "").strip('"')
        if configured_bundle != bundle_identifier:
            continue
        matching_configurations += 1
        if setting in settings:
            values.add(settings[setting].strip('"'))
    require(
        matching_configurations > 0,
        f"no build configurations found for {bundle_identifier}",
    )
    require(
        len(values) == 1,
        f"{setting} for {bundle_identifier} must have one value, found {sorted(values)}",
    )
    return values


def project_value_for_bundle_identifier(
    source: str, bundle_identifier: str, setting: str
) -> str:
    return next(iter(project_values_for_bundle_identifier(
        source, bundle_identifier, setting
    )))


def validate_macos(allow_pending_appcast: bool = False) -> dict[str, str]:
    manifest = load_manifest("macos")
    version = str(manifest["version"])
    build = str(manifest["build"])
    tag = f"v{version}"
    dmg_name = f"SIDEY-macOS-arm64-{tag}.dmg"
    zip_name = f"SIDEY-macOS-arm64-{tag}.zip"
    notes = f"docs/releases/{tag}.md"

    project = read("macos/SIDEY.xcodeproj/project.pbxproj")
    direct_bundle = "$(SIDEY_APP_BUNDLE_IDENTIFIER)"
    require(project_value_for_bundle_identifier(
        project, direct_bundle, "MARKETING_VERSION"
    ) == version,
            "macOS project version does not match release/macos.json")
    require(project_value_for_bundle_identifier(
        project, direct_bundle, "CURRENT_PROJECT_VERSION"
    ) == build,
            "macOS project build does not match release/macos.json")
    app_store_bundle = "app.sidey.desktop.appstore"
    app_store_version = project_value_for_bundle_identifier(
        project, app_store_bundle, "MARKETING_VERSION"
    )
    app_store_build = project_value_for_bundle_identifier(
        project, app_store_bundle, "CURRENT_PROJECT_VERSION"
    )
    require(SEMVER.fullmatch(app_store_version) is not None,
            "Mac App Store target must contain a stable semantic version")
    require(app_store_build.isdigit() and int(app_store_build) > 0,
            "Mac App Store target must contain a positive numeric build")
    require((ROOT / notes).is_file(), f"macOS release notes are missing: {notes}")

    appcast_path = ROOT / "updates" / "appcast.xml"
    appcast_text = appcast_path.read_text(encoding="utf-8")
    appcast = ET.fromstring(appcast_text)
    item = appcast.find("./channel/item")
    require(item is not None, "Sparkle appcast has no release item")
    appcast_version = item.findtext(f"{{{SPARKLE}}}shortVersionString") or ""
    appcast_build = item.findtext(f"{{{SPARKLE}}}version") or ""
    appcast_is_current = appcast_version == version and appcast_build == build
    if not appcast_is_current:
        require(allow_pending_appcast,
                "Sparkle appcast version does not match release/macos.json")
        require(SEMVER.fullmatch(appcast_version) is not None and appcast_build.isdigit(),
                "Sparkle appcast has invalid version metadata")
        manifest_order = (tuple(map(int, version.split("."))), int(build))
        appcast_order = (tuple(map(int, appcast_version.split("."))), int(appcast_build))
        require(appcast_order < manifest_order,
                "Pending Sparkle appcast must be older than release/macos.json")
    enclosure = item.find("enclosure")
    require(enclosure is not None, "Sparkle appcast release has no enclosure")
    expected_zip_url = (
        f"https://github.com/sidey-app/SIDEY/releases/download/{tag}/{zip_name}"
    )
    if appcast_is_current:
        require(enclosure.get("url") == expected_zip_url,
                "Sparkle appcast ZIP URL does not match release/macos.json")
    require("sparkle-signatures:" in appcast_text, "Sparkle appcast is not signed")

    release_data = read("website/src/data/releases.ts")
    require("version: macOSRelease.version" in release_data,
            "website release data must derive the macOS version from release/macos.json")
    require("SIDEY-macOS-arm64-v${macOSRelease.version}.dmg" in release_data,
            "website release data has the wrong macOS DMG URL template")
    require("releases/tag/v${macOSRelease.version}" in release_data,
            "website release data has the wrong macOS release URL template")

    require(f"`{tag}`(build {build})" in read("README.md"),
            "README macOS public version does not match release/macos.json")
    require(f"`{tag}` macOS GitHub 정식 stable release" in read("docs/DECISIONS.md"),
            "DECISIONS macOS public version does not match release/macos.json")
    require(f"macOS `{tag}`(build {build}) 정식 공개" in read("docs/PRODUCT_SPEC.md"),
            "PRODUCT_SPEC macOS public version does not match release/macos.json")

    return {
        "version": version,
        "build": build,
        "tag": tag,
        "dmg_name": dmg_name,
        "zip_name": zip_name,
        "release_notes": notes,
    }


def validate_windows(allow_unreleased_source: bool = False) -> dict[str, str]:
    manifest = load_manifest("windows")
    version = str(manifest["version"])
    tag = f"windows-v{version}"
    installer_name = f"SIDEY-Windows-x64-v{version}-Setup.exe"
    installer_url = (
        f"https://github.com/sidey-app/SIDEY/releases/download/{tag}/{installer_name}"
    )
    notes = f"docs/releases/{tag}.md"

    project = ET.parse(ROOT / "windows" / "src" / "Sidey.App" / "Sidey.App.csproj")
    values = {element.tag: (element.text or "") for element in project.getroot().iter()}
    source_version = values.get("Version", "")
    require(SEMVER.fullmatch(source_version) is not None,
            "Windows project must contain a stable semantic version")
    if source_version != version:
        require(allow_unreleased_source,
                "Windows project version does not match release/windows.json")
        require(
            tuple(map(int, source_version.split(".")))
            > tuple(map(int, version.split("."))),
                "unreleased Windows source version must be newer than the public release")
    require(values.get("FileVersion") == f"{source_version}.0",
            "Windows file version does not match the project version")
    require(values.get("AssemblyVersion") == f"{source_version}.0",
            "Windows assembly version does not match the project version")
    update_source_paths = sorted(
        (ROOT / "windows" / "src" / "Sidey.Platform.Windows").rglob(
            "WindowsUpdateService.cs"
        )
    )
    require(
        len(update_source_paths) == 1,
        "Windows updater source must resolve to exactly one WindowsUpdateService.cs",
    )
    update_source = update_source_paths[0].read_text(encoding="utf-8")
    require(f'CurrentVersion = "{source_version}"' in update_source,
            "Windows updater version does not match the project version")
    require((ROOT / notes).is_file(), f"Windows release notes are missing: {notes}")

    require(installer_name in read("README.md"),
            "README Windows installer does not match release/windows.json")
    require(f"`{tag}` Windows 정식 release" in read("docs/DECISIONS.md"),
            "DECISIONS Windows public version does not match release/windows.json")
    require(f"Windows 네이티브 `v{version}` 정식 출시" in read("docs/PRODUCT_SPEC.md"),
            "PRODUCT_SPEC Windows public version does not match release/windows.json")
    release_data = read("website/src/data/releases.ts")
    require("version: windowsRelease.version" in release_data,
            "website release data must derive the Windows version from release/windows.json")
    require("SIDEY-Windows-x64-v${windowsRelease.version}-Setup.exe" in release_data,
            "website release data has the wrong Windows installer URL template")
    require("releases/tag/windows-v${windowsRelease.version}" in release_data,
            "website release data has the wrong Windows release URL template")

    return {
        "version": version,
        "tag": tag,
        "installer_name": installer_name,
        "installer_url": installer_url,
        "release_notes": notes,
        "source_version": source_version,
    }


def write_github_output(path: Path, values: dict[str, str]) -> None:
    with path.open("a", encoding="utf-8", newline="\n") as output:
        for key, value in values.items():
            require("\n" not in value and "\r" not in value, f"invalid output: {key}")
            output.write(f"{key}={value}\n")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--platform", choices=("all", "macos", "windows"), default="all")
    parser.add_argument("--github-output", type=Path)
    parser.add_argument(
        "--allow-pending-appcast",
        action="store_true",
        help="allow a signed Sparkle item older than the staged macOS manifest",
    )
    parser.add_argument(
        "--allow-unreleased-source",
        action="store_true",
        help="allow a Windows source version newer than the current public manifest",
    )
    args = parser.parse_args()

    outputs: dict[str, str] = {}
    try:
        if args.platform in ("all", "macos"):
            outputs = validate_macos(args.allow_pending_appcast)
        if args.platform in ("all", "windows"):
            windows = validate_windows(args.allow_unreleased_source)
            outputs = windows if args.platform == "windows" else outputs
    except (ConsistencyError, ET.ParseError, json.JSONDecodeError) as error:
        print(f"release consistency error: {error}", file=sys.stderr)
        return 1

    if args.github_output:
        write_github_output(args.github_output, outputs)
    if args.platform == "all":
        print("release metadata is consistent for macOS and Windows")
    else:
        print(f"release metadata is consistent for {args.platform}: {outputs['tag']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
