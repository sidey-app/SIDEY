# Windows Review Reference

Read this reference only when the review includes Windows-owned changes. Apply `windows/AGENTS.md` first.

## Risk map

- Trace ownership and cleanup of Win32, GDI, USER, COM, sockets, timers, streams, registry state and processes on success, failure, cancellation and repeated initialization.
- Check UI-thread access, dispatcher lifetime, window activation, DPI and monitor transitions, taskbar and shell boundaries, and partial native-API failures.
- Preserve framework-dependent publishing, the launcher and `Runtime` layout, shared prerequisites, external assets and Release-only behavior.
- Follow installer upgrade, repair, rollback and uninstall continuity, including preserved user state and machine-wide prerequisite ownership.
- For PowerShell, apply `$windows-powershell` to the caller and compatibility contract without expanding review into implementation.

## Test and validation boundaries

Look for coverage in `Sidey.Core.Tests`, `Sidey.Presentation.Tests`, `Sidey.Platform.Windows.Tests` or the relevant `scripts/windows/tests/*.ps1` artifact boundary. Structured XAML, project, manifest, workflow and installer inspection may be the correct test when the declaration is the contract.

Run the narrowest non-installing check first. Use the broader sequence in `windows/AGENTS.md` only when warranted. Publishing, installation, GUI startup, elevation, network access, release operations and machine-state changes require matching authorization.
