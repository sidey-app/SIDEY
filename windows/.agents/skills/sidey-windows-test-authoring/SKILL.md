---
name: sidey-windows-test-authoring
description: Create, revise, or remove automated tests for SIDEY Windows code under windows/**. Use for C# unit tests, Windows integration and artifact tests, WinUI interaction-test planning, test reliability fixes, and coverage decisions. Do not use for macOS or shared backend and website test work.
---

# SIDEY Windows Test Authoring

Write the smallest reliable test that proves the Windows behavior at the narrowest useful boundary. The user's explicit instructions take precedence over this skill.

## Establish the contract

1. Resolve the repository root with `git rev-parse --show-toplevel` and use it as the working directory for every repository-relative path and command below. The skill is normally discovered while Codex is started in `windows` or one of its descendants.
2. Read the repository-root `AGENTS.md`, `docs/DECISIONS.md`, and `docs/PRODUCT_SPEC.md`; confirmed decisions win.
3. Read `windows/tests/README.md`, `windows/.editorconfig`, the affected production code, and the nearest existing tests.
4. Verify a clean or task-owned worktree on a `windows/*` branch. Limit edits to `windows/**`; record cross-platform or shared follow-up work instead of mixing it into the Windows change.
5. State the trigger, observable result, and failure mode the test must prove before choosing a test layer.

When a test or test helper is written in PowerShell, also read `../sidey-windows-powershell-authoring/SKILL.md` and apply its compatibility, style, output, and safety rules.

## Choose the boundary

- Use `Sidey.Core.Tests` for deterministic domain, protocol-policy, catalog, geometry, and overlay-policy behavior that has no Windows dependency.
- Use `Sidey.Presentation.Tests` for commands, state transitions, coordinator calls, and view-model behavior with fakes.
- Use `Sidey.Platform.Windows.Tests` for Win32 policies, serialization, local HTTP or WebSocket integration, filesystem boundaries, and files that are themselves distribution contracts.
- Use Appium Windows Driver for real WinUI interaction. Select controls through stable automation identifiers and reserve UI automation for behavior that cannot be proved below the UI layer.
- Match the Windows target framework of a test project to the code it exercises. Enable Windows App SDK bootstrap initialization only when that test project directly uses Windows App SDK APIs and needs dynamic dependency initialization.

## Make tests reliable

- Name tests as a concrete trigger and observable result.
- Prefer fixed identifiers, fixed timestamps, explicit inputs, fakes, local protocol servers, and completion signals.
- Put bounded timeouts on asynchronous boundaries so failures terminate. Use `TaskCompletionSource`, cancellation, callbacks, or emitted events to detect readiness; do not sleep for an arbitrary duration while waiting for expected state.
- When elapsed time is the behavior, derive the wait from the production policy and keep the margin explicit.
- Assert the externally meaningful payload, state transition, ordering, cleanup, or recovery result. Do not mirror the implementation line by line.
- Exercise success and the consequential failure boundary. Add combinatorial cases only when each case protects a distinct rule.
- Keep tests independent of execution order, wall-clock date, machine locale, network access, user data, and installed SIDEY state.

Read a repository file directly only when the file is the contract, such as a project file, release manifest, workflow, installer script, localization catalog, or packaged asset. Do not test C# method bodies through source strings or depend on XAML whitespace, element order, or private symbol names.

Delete or replace tests that merely duplicate production code, assert formatting, depend on arbitrary delays, cover no meaningful failure, or prevent safe refactoring without protecting behavior. Preserve coverage for a real invariant by moving it to a behavioral or artifact boundary before deleting the old test.

## Validate

Run the nearest affected project first, then the complete suite:

```powershell
dotnet test windows/SIDEY.Windows.slnx --configuration Release --nologo
dotnet build windows/SIDEY.Windows.slnx --configuration Debug --nologo
dotnet build windows/SIDEY.Windows.slnx --configuration Release --nologo
```

For startup, WinUI composition, prerequisites, packaging, or distribution changes, run the relevant repository checks such as `scripts/windows/tests/Test-RuntimePrerequisites.ps1`, `scripts/windows/Test-FrameworkDependentPublish.ps1`, and `scripts/windows/Test-PublishedApplication.ps1`. Run the complete `scripts/windows/Test-WindowsBuild.ps1` only when its publish, GUI-startup, and possible prerequisite-install effects are within the user's authorized scope. Validate the standalone launcher, uninstaller, and installer language selector with their actual .NET Framework compiler path when those sources change.

Before handing off or committing, run `git diff --check`, inspect every changed path against the branch base, and confirm that no macOS or shared paths entered the change. Report the behavior covered, tests removed or replaced, commands run, results, and any remaining manual WinUI validation.
