---
name: windows-tests
description: Design, create, revise, or remove automated tests for SIDEY Windows code and distribution contracts. Use when changing Windows xUnit or PowerShell tests, repairing test reliability, or explicitly deciding a Windows test boundary. Do not use merely to run existing checks, review a diff, or change production code or prose without test work.
---

# Windows Tests

Write the smallest reliable test that proves the requested Windows behavior at the narrowest useful boundary.

Apply the repository-root `AGENTS.md`, [`windows/AGENTS.md`](../../../windows/AGENTS.md), and the authoritative behavior or architecture documents relevant to the change. Read the affected production code, its callers, and the nearest tests. State the trigger, observable result, and consequential failure before choosing a test layer.

When a test or helper is written in PowerShell, also use `$windows-powershell` and preserve the existing fail-fast script contract.

## Choose the existing test boundary

- Use `windows/tests/Sidey.Core.Tests` for deterministic domain and policy behavior with no platform dependency.
- Use `windows/tests/Sidey.Presentation.Tests` for view-model state, commands, presentation behavior, and declarative MVVM or XAML contracts.
- Use `windows/tests/Sidey.Platform.Windows.Tests` for Windows policies, native and infrastructure behavior, filesystem or local-protocol integration, and distribution contracts.
- Use `scripts/windows/tests/*.ps1` for executable helper, prerequisite, installer, publish-layout, and packaged-artifact checks.

Do not invent a UI-automation stack. Prove behavior below the UI where possible, inspect XAML structurally when the declaration is the contract, and reserve the existing startup smoke or manual UI validation for behavior that cannot be established below that layer. Startup, process, installer, and machine-level checks remain subject to the authorization boundary in `windows/AGENTS.md`.

## Keep the test reliable

- Name the concrete trigger and observable result.
- Assert externally meaningful payloads, state transitions, ordering, cleanup, recovery, or artifact structure rather than mirroring implementation steps.
- Prefer fixed inputs, fakes, local protocol servers, completion signals, and bounded timeouts.
- Use event, callback, cancellation, or completion signals for asynchronous readiness. Use bounded polling or a policy-derived delay only when timing is itself part of the contract, and keep the margin explicit.
- Cover the consequential failure boundary as well as success. Add cases only when each protects a distinct rule.
- Keep tests independent of execution order, wall-clock date, machine locale, network access, user data, and installed application state unless the selected authorized layer explicitly owns that dependency.

Read repository files directly when they are the contract, including project files, XAML declarations, manifests, workflows, installer sources, localization catalogs, and packaged assets. Do not test C# method bodies through source strings or depend on incidental XAML whitespace, element order, or private symbol names.

Replace brittle tests only within the requested scope and preserve every real invariant at a behavioral, structural, or artifact boundary.

## Validate

Run the nearest affected test or project first. Then use the non-installing solution sequence documented in `windows/AGENTS.md` and the affected PowerShell or artifact checks from the canonical Windows job when the change warrants them. Do not use `scripts/windows/Test-WindowsBuild.ps1` as a default test command: it publishes, installs prerequisites, and starts executables.

Report the behavior covered, tests replaced or removed, commands and results, and any remaining manual, installer, or machine-level validation gap.
