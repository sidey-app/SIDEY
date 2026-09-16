# Windows deployment layout

SIDEY for Windows uses framework-dependent publishing. The package contains the app and SIDEY assets, while .NET, the Visual C++ Redistributable, and Windows App Runtime come from shared Microsoft installations. This keeps the installer smaller and lets those shared runtimes receive their normal security updates.

## Launcher and Host have separate jobs

The user starts the Launcher, `SIDEY.exe`. It checks the required runtimes and then starts `Runtime\SIDEY.Host.exe`, the WinUI Host.

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
  Sidey.Core.dll
  Sidey.Infrastructure.dll
  Sidey.Overlay.dll
  Sidey.Platform.Windows.dll
  Sidey.Presentation.dll
```

`dotnet publish` produces an intermediate layout. `ConvertTo-PublishLayout.ps1` rearranges it into the Launcher and Host structure, then checks for leftover self-contained runtime files.

## Treat assets as runtime dependencies

A successful build can still fail at runtime when `Assets\Characters` or `Langs` is missing. The deployment contract includes:

- `Langs\*.json` catalogs for all supported languages;
- pixel characters, speech bubbles, and throwable assets;
- impact sound effects and application icons; and
- each project's managed assemblies and runtime configuration.

Source assets live in the App and Overlay projects. Publishing gathers them in fixed locations under the deployment root. Host assemblies belong in `Runtime`; do not copy `Assets` and `Langs` there again. A path change must update the project copy rules, publish conversion, and deployment tests together.

## Check prerequisites before replacing the application

`windows/installer/Sidey.Setup/prerequisites.json` defines the required runtimes and minimum versions.

- Visual C++ Redistributable x64
- .NET Runtime x64
- Windows App Runtime package set

The installer checks these requirements first and downloads only missing runtimes from Microsoft URLs. Visual C++ and .NET are installed machine-wide, while the Windows App Runtime installer runs with the interactive desktop user's token and success is verified by querying that user's SID for the required package set. If a standard user enters another administrator's credentials at UAC, Setup does not register the Windows App Runtime for that administrator or provision it for every user instead. After the runtimes are ready, Setup extracts and validates the full new payload in a protected staging directory on the same volume as the live install. Setup rejects a parent directory that is writable by an unprivileged identity or contains a reparse point, because such a location cannot safely contain elevated extraction against path-swap races. A prerequisite or staging failure must leave the previous SIDEY runnable.

The distributed Setup performs prerequisite installation, error normalization, install transactions, and process shutdown through compiled .NET Framework 4.7.2 helpers. It does not run PowerShell scripts or `ExecutionPolicy Bypass` on the user's PC, and packaging checks prevent those calls from returning to the NSIS runtime path. Repository build and verification scripts are outside this runtime restriction.

WiX MSI and NSIS cannot share one atomic rollback boundary. When Setup detects a previous MSI, it stops without removing or changing that installation. The user must remove the MSI from Windows Settings > Apps and then run Setup again.

## Keep user data separate from program files

Updates and removal may replace the installation directory. They preserve user data. Cleanup for an existing NSIS or MSI installation must never target the paths that hold messages and settings.

Setup and the uninstaller run elevated to modify Program Files, HKLM, and the all-users Start menu. Windows App Runtime installation and registration, post-install launch, and cleanup of `%LOCALAPPDATA%`, Credential Manager, and HKCU startup registration instead run with the desktop shell user's token. When a standard user enters another administrator's credentials at UAC, the administrator's runtime, data, and credentials must not be treated as the current user's state. If the desktop token cannot be acquired, the installer fails safely instead of registering the runtime for the wrong account, launching SIDEY elevated, or deleting the administrator's data.

Setup and the uninstaller are serialized by one global mutex. An update does not uninstall the existing NSIS package first. After the complete staging payload is ready, Setup stops the app, renames the live install to a rollback sibling, and renames staging to the live path. It also records the pre-install machine registration. A file activation or registration failure restores the files, machine registration, and all-users shortcuts. The old directory is removed only after registration succeeds and the transaction is committed. The next Setup run recovers interrupted state, and uninstall also finishes any deferred rollback cleanup.

Follow this order when changing installation or update code:

1. Confirm that the required runtimes are ready.
2. Extract and validate the full published output in same-volume staging.
3. Shut down running SIDEY processes.
4. Preserve live as rollback and activate staging as live.
5. Update all-users shortcuts and machine registration.
6. Restore the previous live install on failure, or remove rollback on success.
7. Run the Launcher with the desktop user's token only when the user selects it.

## Test the published layout itself

First validate the solution from the repository root.

```powershell
dotnet restore windows/SIDEY.Windows.slnx
dotnet build windows/SIDEY.Windows.slnx --configuration Release --no-restore
dotnet test windows/SIDEY.Windows.slnx --configuration Release --no-restore --no-build
```

`Test-WindowsBuild.ps1` creates a separate publish directory and checks the framework-dependent contract, prerequisites, and startup of both Launcher and Host. Installing missing prerequisites changes machine state, so review the script's scope before running it.

```powershell
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts/windows/tests/Test-WindowsBuild.ps1
```

To inspect an existing publish directory, pass the same explicit `-PublishDirectory` to `Test-FrameworkDependentPublish.ps1` and `Test-PublishedApplication.ps1`. Neither script discovers a publish directory automatically.

The checks cover:

- Launcher and Host are in their defined locations;
- all seven language catalogs and all rendering and audio assets are present;
- no self-contained .NET or Windows App Runtime files are mixed into the output; and
- the Launcher can start the actual Host.

If the installer changed, also run the runtime prerequisite checks, `Test-InstallTransaction.ps1`, and deployment contract tests. An installation check can change installed runtimes and the machine's installation state, so review the inputs and scope of the relevant scripts first.

## Fix the stage that dropped a deployment file

Manually adding a missing DLL to Setup may repair one local package while leaving the next publish broken. Find whether project output, publish conversion, or installer copying dropped the file, then repair the contract at that stage.

Version selection and release writing follow the repository's separate Windows policies. This guide covers the deployment layout and safe installation order.
