import macOSRelease from "../../../release/macos.json";
import windowsRelease from "../../../release/windows.json";

export const releases = {
  macos: {
    version: macOSRelease.version,
    url: `https://github.com/sidey-app/SIDEY/releases/download/v${macOSRelease.version}/SIDEY-macOS-arm64-v${macOSRelease.version}.dmg`,
    notes: `https://github.com/sidey-app/SIDEY/releases/tag/v${macOSRelease.version}`,
    // Local-preview fallback. Pages replaces it with the verified release asset hash.
    sha256: "0842eec1973871e9a091c15cf303e79c40e17e6cadba7f49f545ee253b8d6111",
  },
  windows: {
    version: windowsRelease.version,
    url: `https://github.com/sidey-app/SIDEY/releases/download/windows-v${windowsRelease.version}/SIDEY-Windows-x64-v${windowsRelease.version}-Setup.exe`,
    notes: `https://github.com/sidey-app/SIDEY/releases/tag/windows-v${windowsRelease.version}`,
    // Local-preview fallback. Pages replaces it with the verified release asset hash.
    sha256: "269a9f292fffd9e1a1ee205fe068b82f2a16d798eb4e64bd9025f8157d0fa0fb",
  },
} as const;
