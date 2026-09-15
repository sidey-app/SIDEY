# macOS Developer Documentation Reference

Read this reference only for macOS-owned developer documentation. Apply `macos/AGENTS.md` first.

Respect the current purpose-based locations:

- place general macOS contributor and implementation guides under `macos/docs/**`;
- keep App Store readiness and registration evidence under `macos/Review/**`;
- keep recording-tool operation and contributor guidance with `macos/Recording/README.md`.

Do not impose Windows's paired Korean and English edition convention. Preserve the target document's established language and register unless the user requests a translation or a path-specific rule requires one.

Verify commands against the Xcode project, shared schemes, `scripts/macos/**` callers and macOS workflows. Describe signing, notarization, packaging, Keychain, StoreKit, network and application-launch side effects next to the command. Use `./scripts/macos/test_native.sh` only when the documented behavior warrants the full native check and the environment supports it.
