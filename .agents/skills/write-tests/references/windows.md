# Windows Test Reference

Read this reference only when changing Windows-owned tests. Apply `windows/AGENTS.md` first.

## Existing boundaries

- Use `windows/tests/Sidey.Core.Tests` for deterministic domain and policy behavior with no platform dependency.
- Use `windows/tests/Sidey.Presentation.Tests` for view-model state, commands, presentation behavior and declarative MVVM or XAML contracts.
- Use `windows/tests/Sidey.Platform.Windows.Tests` for Windows policies, native and infrastructure behavior, filesystem or local-protocol integration, and distribution contracts.
- Use `scripts/windows/tests/*.ps1` for executable helper, prerequisite, installer, publish-layout and packaged-artifact checks. When changing a PowerShell test or helper, also use `$windows-powershell`.

Run the nearest affected test first, then use the non-installing solution sequence in `windows/AGENTS.md` and any affected artifact check. Do not use `scripts/windows/tests/Test-WindowsBuild.ps1` by default; it publishes, may install prerequisites and starts executables.
