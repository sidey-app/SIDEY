# Windows deployment layout

SIDEY for Windows follows the same fixed-version self-contained deployment principle as PowerToys. Publishing carries the .NET and Windows App SDK files used by the app, so Setup neither downloads nor changes shared runtimes on the user's PC. `windows/global.json`, `Sidey.App.csproj`, and `Directory.Packages.props` pin the SDK and runtime versions exactly.

## Launcher and Host have separate jobs

The user starts the Launcher, `SIDEY.exe`. It starts the app-local `Runtime\SIDEY.Host.exe`, which runs the WinUI Host.

```text
SIDEY.exe
Uninstall.exe
Langs\
Assets\
  Bubbles\
  Characters\
  Icons\
  Impacts\
  Throwables\
Runtime\
  SIDEY.Host.exe
  SIDEY.Host.dll
  SIDEY.Host.deps.json
  SIDEY.Host.runtimeconfig.json
  coreclr.dll
  hostfxr.dll
  Microsoft.WindowsAppRuntime.dll
  Microsoft.ui.xaml.dll
  Sidey.Core.dll
  Sidey.Infrastructure.dll
  Sidey.Overlay.dll
  Sidey.Platform.Windows.dll
  Sidey.Presentation.dll
```

`dotnet publish` produces an intermediate layout. `ConvertTo-PublishLayout.ps1` rearranges it into the Launcher and Host structure and gathers the .NET and Windows App SDK files under `Runtime`.

## Treat assets as runtime dependencies

A successful build can still fail at runtime when `Assets\Characters` or `Langs` is missing. The deployment contract includes:

- `Langs\*.json` catalogs for all supported languages;
- pixel characters, speech bubbles, and throwable assets;
- impact sound effects and application icons; and
- each project's managed assemblies and runtime configuration.

Source assets live in the App and Overlay projects. Publishing gathers them in fixed locations under the deployment root. Host assemblies belong in `Runtime`; do not copy `Assets` and `Langs` there again. A path change must update the project copy rules, publish conversion, and deployment tests together.

## Treat runtimes as payload files

Setup does not run .NET or Windows App Runtime installers. Publishing places the files required by the app under `Runtime`, and `Test-SelfContainedPublish.ps1` verifies the actual runtime pack and Windows App SDK payload. SIDEY has no C++ project and currently imports no Visual C++ runtime. If a future native binary dynamically imports a VC runtime DLL, validation fails unless that app-local DLL is also present under `Runtime`.

Setup extracts and validates the full new payload in a protected staging directory on the same volume as the live install. Setup rejects a parent directory that is writable by an unprivileged identity or contains a reparse point, because such a location cannot safely contain elevated extraction against path-swap races. A staging failure must leave the previous SIDEY runnable.

The distributed Setup performs error normalization, install transactions, and process shutdown through compiled .NET Framework 4.7.2 helpers. It does not run PowerShell scripts or `ExecutionPolicy Bypass` on the user's PC, and packaging checks prevent those calls from returning to the NSIS runtime path. Repository build and verification scripts are outside this runtime restriction.

WiX MSI and NSIS cannot share one atomic rollback boundary. When Setup detects a previous MSI, it stops without removing or changing that installation. The user must remove the MSI from Windows Settings > Apps and then run Setup again.

## Keep user data separate from program files

Updates and removal may replace the installation directory. They preserve user data. Cleanup for an existing NSIS or MSI installation must never target the paths that hold messages and settings.

Setup and the uninstaller run elevated to modify Program Files, HKLM, and the all-users Start menu. Post-install launch and cleanup of `%LOCALAPPDATA%`, Credential Manager, and HKCU startup registration instead run with the desktop shell user's token. When a standard user enters another administrator's credentials at UAC, the administrator's data and credentials must not be treated as the current user's state. If the desktop token cannot be acquired, the installer fails safely instead of launching SIDEY elevated or deleting the administrator's data.

Setup and the uninstaller are serialized by one global mutex. When an interactive Setup or uninstaller is started again, the second process does not create another language dialog. It restores and attempts to activate the existing language, Setup, or uninstall window, then exits with code `1618`. If Windows denies foreground activation, it flashes the existing taskbar entry; a silent duplicate exits with the same code without showing UI. An update does not uninstall the existing NSIS package first. After the complete staging payload is ready, Setup stops the app, renames the live install to a rollback sibling, and renames staging to the live path. It also records the pre-install machine registration. A file activation or registration failure restores the files, machine registration, and all-users shortcuts. The old directory is removed only after registration succeeds and the transaction is committed. The next Setup run recovers interrupted state, and uninstall also finishes any deferred rollback cleanup.

Follow this order when changing installation or update code:

1. Extract and validate the full published output, including app-local runtimes, in same-volume staging.
2. Shut down running SIDEY processes.
3. Preserve live as rollback and activate staging as live.
4. Update all-users shortcuts and machine registration.
5. Restore the previous live install on failure, or remove rollback on success.
6. Run the Launcher with the desktop user's token only when the user selects it.

## Test the published layout itself

First validate the solution from `windows/` so the .NET CLI applies the SDK policy in `windows/global.json`.

```powershell
Push-Location windows
dotnet restore SIDEY.Windows.slnx
dotnet build SIDEY.Windows.slnx --configuration Release --no-restore
dotnet test SIDEY.Windows.slnx --configuration Release --no-restore --no-build
Pop-Location
```

`Test-WindowsBuild.ps1` creates a separate publish directory and checks the self-contained contract and startup of both Launcher and Host.

```powershell
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts/windows/tests/Test-WindowsBuild.ps1
```

To inspect an existing publish directory, pass the same explicit `-PublishDirectory` to `Test-SelfContainedPublish.ps1` and `Test-PublishedApplication.ps1`. Neither script discovers a publish directory automatically.

The checks cover:

- Launcher and Host are in their defined locations;
- all seven language catalogs and all rendering and audio assets are present;
- the pinned .NET and Windows App SDK files are under `Runtime`, and every VC runtime import is resolved app-locally; and
- the Launcher can start the actual Host.

If the installer changed, also run `Test-SelfContainedPublish.ps1`, `Test-InstallTransaction.ps1`, and the deployment contract tests. An installation check can change machine installation state, so review the inputs and scope of the relevant scripts first.

## Fix the stage that dropped a deployment file

Manually adding a missing DLL to Setup may repair one local package while leaving the next publish broken. Find whether project output, publish conversion, or installer copying dropped the file, then repair the contract at that stage.

Version selection and release writing follow the repository's separate Windows policies. This guide covers the deployment layout and safe installation order.
