# Contributing to SIDEY for Windows

This guide applies to `windows/**`. Repository-level `AGENTS.md` instructions and confirmed decisions in `docs/DECISIONS.md` take precedence.

## Before changing code

1. Read `docs/DECISIONS.md` and `docs/PRODUCT_SPEC.md`.
2. Work on a `windows/<topic>` branch or an isolated worktree. Do not modify macOS implementation files from a Windows branch.
3. Keep the Windows client native: C#/.NET/WinUI 3 with Win32 platform services. Do not introduce WPF, Electron, WebView, Godot, or a second renderer.
4. Preserve the privacy and server-authority boundaries in the product documents. In particular, never log message bodies, credentials, invite codes, raw user identifiers, input keys, pointer coordinates, screen contents, or active applications.

## C# style and readability

- Follow `windows/.editorconfig`; CI verifies it with `dotnet format`.
- Use four spaces, Allman braces, file-scoped namespaces, one statement per line, and `System` imports first.
- Use `PascalCase` for types and members, `I` for interfaces, and `_camelCase` for private fields.
- Prefer descriptive names that reveal intent. Avoid abbreviations whose meaning is local knowledge.
- Use `var` only when the assigned expression makes the type apparent. Write the type when it improves scanning or exposes an important domain concept.
- Prefer one primary type per file. A file may contain a small private implementation detail that cannot be useful independently.
- Keep methods cohesive and use guard clauses to make invalid or terminal paths obvious. Do not impose arbitrary method or class line limits; split code when it owns unrelated reasons to change.
- Use comments for constraints, rationale, interop behavior, and non-obvious tradeoffs. Do not narrate syntax or leave comments that merely restate stale implementation details.
- Prefer immutable records and readonly state for snapshots and values. Return empty collections instead of `null`.
- Use modern language features when they improve clarity, including property patterns, `is null`/`is not null`, collection expressions, and using declarations.

## Async, exceptions, and resource ownership

- Await asynchronous I/O end to end. Do not block with `.Result`, `.Wait()`, or `.GetAwaiter().GetResult()`.
- Do not expose `Task` or `ValueTask` for work that is always synchronous. Use `ValueTask` only when its completion and consumption contract is deliberate, and await it exactly once.
- Every long-running background task must have an owner that stores it, cancels it, observes failure, and awaits it during shutdown. A bare `_ = SomeAsync()` is limited to UI, native-event, or timer boundaries where the invoked method owns cancellation as needed and observes every exception.
- A task that captures `IDisposable` or `IAsyncDisposable` state must finish before that state is disposed.
- Pass cancellation tokens through I/O and long-running operations. Treat expected cancellation separately from failure.
- Catch the most specific exception that can be handled. Broad catches are permitted only at process, UI-command, native-callback, render-loop, and recovery boundaries; log or translate them there without exposing private data.
- Rethrow with `throw;`, not `throw exception;`.
- Dispose native handles, sockets, cancellation sources, timers, and COM resources deterministically. Ownership must be visible from the containing type.

## MVVM and dependency direction

- `Sidey.Core` contains domain policy and has no WinUI, Win32, network, or storage dependency.
- `Sidey.Presentation` contains ViewModels and UI-facing service interfaces. It may reference `Sidey.Core`, but not `Sidey.App`, `Sidey.Overlay`, `Sidey.Infrastructure`, `Sidey.Platform.Windows`, WinUI, or Win32.
- `Sidey.Infrastructure`, `Sidey.Overlay`, and `Sidey.Platform.Windows` implement external and platform concerns. `Sidey.App` is the composition root.
- A View knows its ViewModel; a ViewModel must not know its View. Keep code-behind to view-only behavior such as focus, animation, window policy, and dialogs that cannot be expressed cleanly through binding.
- Put user actions and enablement rules in ViewModel commands and observable properties.
- Depend on the smallest feature interface required by a ViewModel. Do not make every feature depend on an application-wide coordinator surface.
- Construct platform adapters in the application composition root and inject abstractions into ViewModels.

## Performance-sensitive code

- Measure before optimizing. Prefer clear code outside measured hot paths.
- The overlay runs at 30 FPS and must not allocate bitmaps, surfaces, projectile buffers, or equivalent frame resources per tick.
- Reuse bounded buffers and caches. Keep collections and background queues bounded according to the product specification.
- LINQ is welcome when it expresses intent clearly. In measured render or high-frequency paths, compare allocations and timing before replacing loops with LINQ.
- Preserve deterministic 24x24 assets, integer nearest-neighbor scaling, premultiplied BGRA, and the no-real-time-shadow rule.

## Tests

- Mirror production ownership with test projects: Core, Presentation, Infrastructure, Overlay, and Windows platform behavior should live with the corresponding layer when practical.
- Use Arrange-Act-Assert and behavior-oriented names. Cover normal behavior, boundary cases, cancellation, failure, concurrency, and cleanup.
- Prefer observable behavior over implementation strings. Parse structured artifacts such as XML/JSON when the artifact itself is the contract. Keep source-text assertions only for packaging or platform contracts that cannot be exercised safely in unit tests.
- For rendering, test deterministic pixels, premultiplied alpha, edge/DPI variants, connectivity, bounds, allocations, and relevant performance budgets.
- Avoid wall-clock sleeps. Use controllable delays, cancellation, completion sources, or bounded polling.
- Coverage is evidence, not the goal. Collect it to find untested Core and Presentation behavior; do not satisfy a percentage by testing generated code, P/Invoke declarations, or trivial bindings.

## Required checks

Run from the repository root:

```powershell
dotnet restore windows/SIDEY.Windows.slnx
dotnet format windows/SIDEY.Windows.slnx --verify-no-changes --no-restore
dotnet build windows/SIDEY.Windows.slnx --configuration Release --no-restore
dotnet test windows/SIDEY.Windows.slnx --configuration Release --no-restore --no-build
dotnet test windows/SIDEY.Windows.slnx --configuration Release --no-restore --collect:"XPlat Code Coverage" --settings windows/coverlet.runsettings --results-directory artifacts/coverage
```

Before committing, inspect every changed path relative to the branch base and confirm that no macOS implementation or unrelated shared file changed.
