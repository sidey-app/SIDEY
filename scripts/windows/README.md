# SIDEY Windows automation

Run these scripts from the repository root. Windows PowerShell 5.1 is the compatibility baseline; PowerShell 7 is also supported. PowerShell script names use `Verb-Noun.ps1`, and directory or file variables end in `Directory` or `Path` when the distinction matters.

## Main entry points

| Script | Purpose |
| --- | --- |
| `Test-WindowsBuild.ps1` | Restore, test, build, publish, and launch-smoke the Windows client. |
| `New-WindowsInstaller.ps1` | Validate a publish directory and create the public NSIS Setup EXE. |
| `Start-UpdateDesignTest.ps1` | Build and start the interactive update-design fixture. |
| `Test-WindowsRelease.ps1` | Compare a local release candidate with the published GitHub asset. |
| `Sync-RendererAssets.ps1` | Rebuild Windows PNG/BGRA mirrors from `assets/v1/manifest.json`. |

## Build and validation helpers

`ConvertTo-PublishLayout.ps1` is called by MSBuild. `New-InstallerArtwork.ps1`, `New-InstallerLanguageSelector.ps1`, and `New-InstallerTerms.ps1` create reproducible installer inputs. `Test-FrameworkDependentPublish.ps1`, `Test-ImpactAudioAssets.ps1`, and `Test-PublishedApplication.ps1` validate publish output. Shared native-command handling lives in `Sidey.PowerShell.psm1`.

Focused automation checks live under `tests/`. Keep one-time migration scripts out of this directory: extend `Sync-RendererAssets.ps1` when a new canonical renderer asset needs a Windows mirror.
