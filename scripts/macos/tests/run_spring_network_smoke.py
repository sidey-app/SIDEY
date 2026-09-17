#!/usr/bin/env python3
"""Run production Swift REST/WS clients against two disposable loopback sessions.

This is not an Xcode/XCTest or packaged-application launch substitute. The server
must issue identity-backed fixture sessions; no identity verifier is bypassed.
The scenario deletes only those two explicitly supplied disposable accounts.
"""
import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("fixture", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[3]
    names = """Models ProductLimits CommerceModels CommerceProductDefinition OverlayModels
        BackendModels SpringRealtimeTransport SideyBackend SpringBackendModels AppleAuthorization
        GoogleDesktopOAuth SideySessionClient DistributionConfiguration RuntimeConfiguration
        KeychainStore KeychainTransitionNotice PixelCharacterCatalog NetworkPathMonitoring
        LaunchAtLoginController""".split()
    sources = list((root / "macos/SIDEY").rglob("*.swift"))
    with tempfile.TemporaryDirectory(prefix="sidey-spring-network-") as temporary:
        directory = Path(temporary)
        copied = []
        for name in names:
            matches = [path for path in sources if path.name == name + ".swift"]
            if len(matches) != 1:
                raise RuntimeError("Ambiguous production source: " + name)
            destination = directory / matches[0].name
            shutil.copy2(matches[0], destination)
            copied.append(str(destination))
        shutil.copytree(root / "macos/SIDEY/Resources/Commerce", directory / "Commerce")
        executable = directory / "spring-network-smoke"
        subprocess.run(["xcrun", "swiftc", "-swift-version", "6", "-strict-concurrency=complete",
                        "-D", "APP_STORE", "-module-name", "SIDEY", *copied,
                        str(Path(__file__).with_name("SpringNetworkSmoke.swift")),
                        "-o", str(executable)], check=True, cwd=root)
        subprocess.run([str(executable), str(args.fixture.resolve())], check=True, timeout=120)


if __name__ == "__main__":
    main()
