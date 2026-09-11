# SIDEY release manifests

`macos.json` and `windows.json` are the authoritative public release metadata for each
platform. Tags, artifact names, release-note paths, website update manifests, and workflow
outputs are derived from these files.

Platform project versions remain embedded in their native build files. The release
consistency check rejects a change unless those mirrors and the public documentation match
the corresponding manifest.

Windows releases are published only by the manually dispatched `Windows Release` workflow
on `main`. Enter the exact version from `windows.json`; the workflow builds a draft, verifies
its downloaded Setup EXE, publishes it, and calls the reusable Pages workflow.

macOS Developer ID, notarization, and Sparkle keys remain on the release operator's Mac.
After the staged version change reaches `main`, run `scripts/release_macos.sh`. It publishes
verified direct-distribution assets and opens separate signed appcast and Homebrew Cask pull
requests. Set `SIDEY_ARCHIVE_APP_STORE=1` with the App Store environment to also create the
local App Store archive; submission remains an explicit App Store Connect operation.

The CI workflows are intentionally separate: `macOS CI`, `Windows CI`, `Database CI`,
`Release metadata`, `Download metrics`, and Pages each have one responsibility.
