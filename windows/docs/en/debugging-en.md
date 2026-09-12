# Debugging on Windows

Debugging starts by finding where a user action first changes as it crosses system boundaries. That boundary narrows the search before anyone reads or modifies unrelated projects.

## Fix the reproduction conditions first

Window state, connection state, DPI, and monitor layout can give similar-looking failures different causes. Record the following before investigating:

- the user action and expected result;
- the actual result and when it first appeared;
- the Debug or Release configuration, app version, and installation method;
- the Windows version, monitor count, scaling, and layout;
- the selected app language and connection state; and
- whether the problem occurs consistently and still occurs after a restart.

Do not include personal data such as message contents, invite codes, or raw user and room UUIDs in reproduction notes.

## Follow the boundaries crossed by the behavior

If the send button does not work, for example, inspect the flow in this order:

```text
XAML Command binding
  → ComposerViewModel command and state
  → SendRequested event
  → App composition code
  → AppCoordinator
  → storage and server response
```

The first unexpected value marks a likely source of the bug. Checking the flow one boundary at a time is faster than reading all of `AppCoordinator` up front.

Choose a starting point based on the type of problem:

- Start with `Sidey.Presentation` for UI state and commands.
- Start with `Sidey.Infrastructure` for the server, authentication, configuration, and local persistence.
- Start with `Sidey.Overlay` for pixel layout and drawing.
- Start with `Sidey.Platform.Windows` for windows, monitors, pointer pass-through, and startup.
- Start with `Sidey.App` for object creation and lifetime wiring.

## Run the smallest relevant check first

Start with the test closest to the suspected cause. Its result arrives sooner and usually points to a smaller part of the system.

```powershell
dotnet test windows/tests/Sidey.Presentation.Tests/Sidey.Presentation.Tests.csproj --configuration Release --nologo
```

After making a change, run the full checks from the repository root.

```powershell
dotnet restore windows/SIDEY.Windows.slnx
dotnet format windows/SIDEY.Windows.slnx --verify-no-changes --no-restore
dotnet build windows/SIDEY.Windows.slnx --configuration Debug --no-restore
dotnet build windows/SIDEY.Windows.slnx --configuration Release --no-restore
dotnet test windows/SIDEY.Windows.slnx --configuration Release --no-restore --no-build
```

ViewModel tests check state and collaborator calls after a command runs. A test may parse XAML as XML when the file itself is a contract, but it must ignore whitespace and attribute order. Use UI interaction tests or manual checks for focus, window activation, clicks, and other live WinUI behavior.

## Diagnose Launcher and Host separately for startup failures

A published SIDEY installation has two startup layers: the Launcher checks the runtime environment, and the Host runs the WinUI app. A failure to open `SIDEY.exe` can occur before any View code runs.

1. Confirm that the published directory structure is complete.
2. Confirm that the Launcher passes its .NET, Visual C++ Redistributable, and Windows App Runtime checks.
3. Check the stage markers in the session log to determine whether the Host started.
4. If the Host started, find the first failed stage around `startup-complete`.

Diagnostic logs are stored at:

```text
%LOCALAPPDATA%\SIDEY\Logs\SIDEY.<version>.<yyyyMMdd>.<HHmmss>.log
```

The log records the exception type, HRESULT, and safely classified network and Win32 information instead of the complete exception message. See [`logging-en.md`](logging-en.md) for the detailed rules.

## Clean only the relevant build output

Stale `bin` and `obj` directories sometimes cause build failures. Deleting them across the repository before investigating can hide the cause, so identify the failing project and any process using its files first. Then use `dotnet clean` to recreate known build output.

For a publishing problem, inspect the published output rather than a normal build result.

```powershell
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts/windows/Test-FrameworkDependentPublish.ps1
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts/windows/Test-PublishedApplication.ps1
```

These checks cover deployment file locations, shared-runtime assumptions, and application startup. A complete deployment check may install prerequisites and change the environment, so read the script's scope before running it.

## State the coordinate system when investigating overlay problems

The overlay uses logical coordinates, screen pixels, and monitor work areas together. A number without its coordinate system or scale may look correct but become misaligned at a different DPI.

Check all of the following:

- the monitor origin and work area;
- Windows scaling and logical size;
- integer scaling of the 24×24 logical pixels;
- horizontal mirroring and premultiplied BGRA handling;
- default pointer pass-through and transition into explicit interaction mode; and
- whether a new bitmap or buffer is allocated on every frame.

The product does not guarantee that the overlay is always visible above secure screens, DRM applications, elevated applications, or every exclusive-fullscreen game. Do not treat an overlay hidden in one of these environments as equivalent to a defect in an ordinary window.

## Write down the cause and the check that prevents a repeat

A useful bug-fix record names the broken boundary and the check that prevents the same failure from returning.

- Cause: Removal of the previous MSI returned 3010, but the installer treated it as a general failure.
- Fix: The installer handles 3010 as a restart-required state and stops the installation.
- Prevention: Installer contract tests verify this branch and its guidance text.

With those details, the next person who sees the symptom can start at the failed boundary.
