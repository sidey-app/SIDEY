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

The installer checks these requirements first and downloads only missing runtimes from Microsoft URLs. It cleans up the existing SIDEY files only after runtime installation succeeds. Deleting the application before a prerequisite failure would leave the user unable to run the previous version.

Exit code `3010` from removing a previous MSI means that Windows must restart. When it appears, leave the new files untouched, show restart guidance, and exit. The user can run Setup again after the restart to complete the migration safely.

## Keep user data separate from program files

Updates and removal may replace the installation directory. They preserve user data. Cleanup for an existing NSIS or MSI installation must never target the paths that hold messages and settings.

Follow this order when changing installation or update code:

1. Shut down running SIDEY processes safely.
2. Confirm that the required runtimes are ready.
3. Select the removal path for the previous installation type.
4. Clean up program files only.
5. Copy the new published output and update registration data.
6. Verify an actual start through the Launcher.

## Test the published layout itself

First validate the solution from the repository root.

```powershell
dotnet restore windows/SIDEY.Windows.slnx
dotnet build windows/SIDEY.Windows.slnx --configuration Release --no-restore
dotnet test windows/SIDEY.Windows.slnx --configuration Release --no-restore --no-build
```

`Test-WindowsBuild.ps1` creates a separate publish directory and checks the framework-dependent contract, prerequisites, and startup of both Launcher and Host. Installing missing prerequisites changes machine state, so review the script's scope before running it.

```powershell
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts/windows/Test-WindowsBuild.ps1
```

To inspect an existing publish directory, pass the same explicit `-PublishDirectory` to `Test-FrameworkDependentPublish.ps1` and `Test-PublishedApplication.ps1`. Neither script discovers a publish directory automatically.

The checks cover:

- Launcher and Host are in their defined locations;
- all seven language catalogs and all rendering and audio assets are present;
- no self-contained .NET or Windows App Runtime files are mixed into the output; and
- the Launcher can start the actual Host.

If the installer changed, also run the runtime prerequisite checks and deployment contract tests. An installation check can change installed runtimes and the machine's installation state, so review the inputs and scope of the relevant scripts first.

## Fix the stage that dropped a deployment file

Manually adding a missing DLL to Setup may repair one local package while leaving the next publish broken. Find whether project output, publish conversion, or installer copying dropped the file, then repair the contract at that stage.

Version selection and release writing follow the repository's separate Windows policies. This guide covers the deployment layout and safe installation order.
