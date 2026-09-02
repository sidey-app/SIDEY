import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

const version = "0.3.0-alpha.7";
const tag = `windows-v${version}`;
const installerURL = `https://github.com/sidey-app/SIDEY/releases/download/${tag}/SIDEY-Windows-x64-v${version}-Setup.exe`;
const sha256 = "30af0b889ee56ff58934337f01b39275cf5c72a8ea5aa4b37a83eef7b11f9e81";

test("Windows update manifests publish the verified release asset", async () => {
  const [latest, compatibility] = await Promise.all([
    read("windows-latest.json").then(JSON.parse),
    read("windows/update.json").then(JSON.parse),
  ]);

  assert.deepEqual(latest, compatibility);
  assert.deepEqual(latest, {
    channel: "alpha",
    version,
    tag,
    installer_url: installerURL,
    sha256,
  });
});

test("both landing pages expose the same Windows test release with warnings", async () => {
  const [korean, english] = await Promise.all([read("index.html"), read("en/index.html")]);

  for (const landing of [korean, english]) {
    assert.equal(landing.split(installerURL).length - 1, 2);
    assert.ok(landing.includes(`releases/tag/${tag}`));
    assert.ok(landing.includes(`v${version}`));
    assert.ok(!landing.includes("No public Setup.exe"));
  }

  assert.ok(korean.includes("자체 서명 테스트 빌드"));
  assert.ok(english.includes("Self-signed test build"));
});
