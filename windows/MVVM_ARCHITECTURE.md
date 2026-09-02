# SIDEY Windows MVVM architecture

This document defines the presentation boundary for the Windows client. The macOS
client is a behavioral reference and is not part of this architecture or refactor.

## Dependency direction

```text
XAML view + minimal code-behind
              |
              v
          ViewModel
              |
              v
      ISideyCoordinator
              |
              v
 AppCoordinator + infrastructure/platform services
              |
              v
          Sidey.Core
```

- `Sidey.Core` owns domain records, validation, presence, message, and movement
  policy. It does not reference WinUI, Windows, Supabase, or a ViewModel.
- `Sidey.Infrastructure`, `Sidey.Overlay`, and `Sidey.Platform.Windows` implement
  persistence, realtime transport, native overlay, tray, monitor, and Windows
  integration concerns.
- `AppCoordinator` is the application service. It coordinates those dependencies
  and exposes immutable `CoordinatorState` snapshots through `ISideyCoordinator`.
- `Sidey.Presentation` owns ViewModels, observable presentation state, validation feedback, asynchronous
  commands, incremental collection updates, and dialog intent.
- XAML views bind to ViewModel properties and commands. Code-behind is limited to
  window lifetime, focus, sizing, backdrop, navigation visibility, scrolling, and
  other WinUI/Win32 interactions that cannot be expressed cleanly in XAML.
- `App.xaml.cs` is the composition root. It creates services, ViewModels, and views,
  then forwards coordinator snapshots to the active ViewModels.

## ViewModels

- `MainWindowViewModel` owns settings, profile, group presentation, command state,
  notices, monitor choices, and incremental room/member projections.
- `ComposerViewModel` owns draft validation, typing state, send/close commands, and
  the five-second post-send dismissal policy.
- `HistoryWindowViewModel` owns paging, newest-first merging, pending delivery state,
  local-time formatting, loading state, and the empty-state copy.

ViewModels depend on `ISideyCoordinator`, not the concrete coordinator. UI-only
interactions such as content dialogs use the narrow `IMainWindowDialogService`
boundary rather than passing WinUI controls into a ViewModel.

## Update rules

1. Add user actions as `RelayCommand` or `AsyncRelayCommand` members on a ViewModel.
2. Keep XAML code-behind free of network, persistence, group, profile, message, and
   preference mutations.
3. Keep images and brushes out of ViewModels. Bind stable IDs or booleans and map
   them with converters in the view layer.
4. Update observable collections incrementally so realtime snapshots do not reset
   list controls or interrupt transitions.
5. Keep blocking I/O asynchronous and catch exceptions only where the layer can
   recover, translate the error, or show actionable feedback.
6. Add behavior tests for policies and source-contract tests for critical view to
   ViewModel bindings.

## C# conventions

`windows/.editorconfig` captures the repository-enforced subset of Microsoft's C#
coding conventions: four-space indentation, Allman braces, file-scoped namespaces,
organized imports, explicit accessibility, .NET naming, and `var` only when the type
is evident. Run these checks before committing:

```powershell
$env:NUGET_PACKAGES = (Resolve-Path .tools/nuget-packages).Path
$env:DOTNET_CLI_HOME = (Resolve-Path .tools/dotnet-home).Path
./.tools/dotnet/dotnet.exe format windows/SIDEY.Windows.slnx --no-restore
./.tools/dotnet/dotnet.exe test windows/SIDEY.Windows.slnx -c Release --no-restore
```

References:

- [Model-View-ViewModel overview](https://learn.microsoft.com/dotnet/architecture/maui/mvvm)
- [MVVM Toolkit introduction](https://learn.microsoft.com/dotnet/communitytoolkit/mvvm/)
- [RelayCommand and AsyncRelayCommand](https://learn.microsoft.com/dotnet/communitytoolkit/mvvm/relaycommand)
- [C# coding conventions](https://learn.microsoft.com/dotnet/csharp/fundamentals/coding-style/coding-conventions)
