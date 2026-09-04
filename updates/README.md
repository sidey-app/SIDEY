# SIDEY Sparkle feed

`appcast.xml` is the production update feed read by SIDEY. It must remain signed with the
Sparkle EdDSA key stored under the `sidey-app` account in the release operator's login
Keychain. Never edit a signed feed by hand.

The supported release entry point is `scripts/release_macos.sh`. It packages and notarizes
the app, creates a draft GitHub Release, downloads and compares all four assets, publishes
the release, and opens the signed appcast and Homebrew Cask pull requests:

```sh
SIDEY_CODE_SIGN_IDENTITY='Developer ID Application: Example (TEAMID)' \
SIDEY_HARDENED_RUNTIME=YES \
SIDEY_NOTARYTOOL_PROFILE=sidey-notary \
  ./scripts/release_macos.sh
```

The lower-level `scripts/macos/prepare_sparkle_appcast.sh` remains an implementation detail
and recovery tool. Commit and push the generated `appcast.xml` only after the ZIP URL is
live. The script
rejects ad-hoc and development-channel builds by default and verifies the Developer ID
signature, Hardened Runtime, stapled notarization ticket, production display name and
channel, embedded public key, feed URL, signed-feed security flags, and that the
already-uploaded GitHub Release ZIP is byte-for-byte identical to the local ZIP.

For an isolated local pipeline test, `SIDEY_ALLOW_AD_HOC_SPARKLE=1` bypasses only the
Developer ID and notarization requirement. Never publish an appcast generated in that mode.

The private key is not stored in this repository. Export it only to encrypted offline
storage with Sparkle's `generate_keys --account sidey-app -x <backup-file>` command.
