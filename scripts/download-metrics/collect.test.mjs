import assert from "node:assert/strict";
import test from "node:test";
import { classifyReleaseAssets } from "./collect.mjs";

const asset = (id, name, downloadCount) => ({ id, name, download_count: downloadCount });

test("keeps pre-split DMG counters historically unclassified", () => {
  const result = classifyReleaseAssets([
    {
      tag_name: "v1.0.4",
      draft: false,
      prerelease: false,
      assets: [
        asset(1, "SIDEY-macOS-arm64-v1.0.4.dmg", 100),
        asset(2, "SIDEY-macOS-arm64-v1.0.4.zip", 50),
        asset(3, "SIDEY-macOS-arm64-v1.0.4.dmg.sha256", 12),
      ],
    },
  ]);

  assert.deepEqual(result, [
    {
      asset_id: 1,
      asset_name: "SIDEY-macOS-arm64-v1.0.4.dmg",
      release_tag: "v1.0.4",
      version: "1.0.4",
      channel: "legacy_unclassified",
      download_count: 100,
    },
  ]);
});

test("separates direct, Homebrew, and MSI assets after the split", () => {
  const result = classifyReleaseAssets([
    {
      tag_name: "v1.0.5",
      draft: false,
      prerelease: false,
      assets: [
        asset(10, "SIDEY-macOS-arm64-v1.0.5.dmg", 7),
        asset(11, "SIDEY-macOS-arm64-v1.0.5-homebrew.dmg", 9),
      ],
    },
    {
      tag_name: "windows-v1.0.3",
      draft: false,
      prerelease: false,
      assets: [asset(12, "SIDEY-Windows-x64-v1.0.3.msi", 11)],
    },
  ]);

  assert.deepEqual(
    result.map(({ channel, download_count }) => [channel, download_count]),
    [
      ["direct_dmg", 7],
      ["homebrew_dmg", 9],
      ["windows_msi", 11],
    ],
  );
});

test("ignores drafts and prereleases", () => {
  const result = classifyReleaseAssets([
    {
      tag_name: "v2.0.0-beta",
      draft: false,
      prerelease: true,
      assets: [asset(20, "SIDEY-macOS-arm64-v2.0.0.dmg", 999)],
    },
    {
      tag_name: "v2.0.0",
      draft: true,
      prerelease: false,
      assets: [asset(21, "SIDEY-macOS-arm64-v2.0.0.dmg", 999)],
    },
  ]);

  assert.deepEqual(result, []);
});
