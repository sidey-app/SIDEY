from __future__ import annotations

import hashlib
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts" / "pages"))
from prepare_release_metadata import prepare


class PrepareReleaseMetadataTests(unittest.TestCase):
    def test_prepares_localized_pages_and_windows_manifests(self) -> None:
        with tempfile.TemporaryDirectory(prefix="SIDEY-Pages-") as temporary:
            test_root = Path(temporary)
            release_dir = test_root / "release"
            release_dir.mkdir()
            macos_manifest_path = ROOT / "release" / "macos.json"
            windows_manifest_path = ROOT / "release" / "windows.json"
            macos_manifest = json.loads(macos_manifest_path.read_text(encoding="utf-8"))
            windows_manifest = json.loads(windows_manifest_path.read_text(encoding="utf-8"))
            macos_dmg = release_dir / f"SIDEY-macOS-arm64-v{macos_manifest['version']}.dmg"
            windows_installer = release_dir / (
                f"SIDEY-Windows-x64-v{windows_manifest['version']}-Setup.exe"
            )
            shutil.copyfile(macos_manifest_path, macos_dmg)
            shutil.copyfile(windows_manifest_path, windows_installer)
            output_dir = test_root / "site"

            prepare(
                ROOT / "website" / "dist",
                output_dir,
                macos_manifest_path,
                macos_dmg,
                windows_manifest_path,
                windows_installer,
            )

            macos_hash = hashlib.sha256(macos_dmg.read_bytes()).hexdigest()
            windows_hash = hashlib.sha256(windows_installer.read_bytes()).hexdigest()
            published = json.loads(
                (output_dir / "windows-latest.json").read_text(encoding="utf-8")
            )
            self.assertEqual(published["sha256"], windows_hash)
            self.assertEqual(
                published,
                json.loads((output_dir / "windows" / "update.json").read_text(encoding="utf-8")),
            )
            for locale in ("ko", "en", "ja"):
                html = (output_dir / locale / "index.html").read_text(encoding="utf-8")
                self.assertIn(
                    f'<code id="macos-download-sha256" data-release-platform="macos">{macos_hash}</code>',
                    html,
                )
                self.assertIn(
                    f'<code id="windows-download-sha256" data-release-platform="windows">{windows_hash}</code>',
                    html,
                )


if __name__ == "__main__":
    unittest.main()
