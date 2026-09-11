# Windows test strategy

Keep tests at the narrowest boundary that can prove user-visible behavior:

- `Sidey.Core.Tests` covers deterministic domain and overlay policies.
- `Sidey.Presentation.Tests` covers commands, state transitions, and coordinator interactions without WinUI.
- `Sidey.Platform.Windows.Tests` covers Windows policies, serialization, files that are distribution contracts, and local HTTP/WebSocket integration.
- WinUI interaction tests should use Appium Windows Driver on a Windows runner and select controls by stable automation identifiers.

Tests should describe a trigger and observable result. Prefer fixed inputs, fakes, local protocol servers, and completion signals. Put a timeout on asynchronous boundaries; do not use an arbitrary delay to wait for expected state.

Do not inspect C# method bodies or depend on XAML whitespace and element ordering. A file may be read directly only when the file itself is the contract, such as a release manifest, project property, installer script, localization catalog, or packaged asset.

Run the complete suite from the repository root:

```powershell
dotnet test windows/SIDEY.Windows.slnx --configuration Release --nologo
```
