# SIDEY Sparkle feed

`appcast.xml` is the production update feed read by SIDEY. It must remain signed with the
Sparkle EdDSA key stored under the `sidey-app` account in the release operator's login
Keychain. Never edit a signed feed by hand.

Create and notarize the release ZIP with the signing environment documented in the
repository README, upload that exact ZIP to its GitHub Release, then regenerate the feed
with the release's committed notes file:

```sh
SIDEY_RELEASE_NOTES=docs/releases/v0.2.0.md \
  ./scripts/macos/prepare_sparkle_appcast.sh \
  v0.2.0 \
  build/releases/v0.2.0/SIDEY-macOS-arm64-v0.2.0.zip
```

Commit and push the generated `appcast.xml` only after the ZIP URL is live. The script
rejects ad-hoc and development-channel builds by default and verifies the Developer ID
signature, Hardened Runtime, stapled notarization ticket, production display name and
channel, embedded public key, feed URL, signed-feed security flags, and that the
already-uploaded GitHub Release ZIP is byte-for-byte identical to the local ZIP.

For an isolated local pipeline test, `SIDEY_ALLOW_AD_HOC_SPARKLE=1` bypasses only the
Developer ID and notarization requirement. Never publish an appcast generated in that mode.

The private key is not stored in this repository. Export it only to encrypted offline
storage with Sparkle's `generate_keys --account sidey-app -x <backup-file>` command.
