---
name: write-tests
description: Create, revise, or remove automated tests for Windows application code. Use for unit, integration, artifact, and UI interaction tests, test reliability fixes, and coverage decisions. Do not use for implementation-only or prose-only work.
---

# Write Tests

Write the smallest reliable test that proves the Windows behavior at the narrowest useful boundary. The user's explicit instructions take precedence over this skill.

## Establish the contract

1. Resolve the repository root with `git rev-parse --show-toplevel` and use it as the working directory for repository-relative paths and commands.
2. Discover and read the repository instructions, authoritative behavior documents, test guidance, and style or analyzer configuration that apply to the affected code.
3. Read the affected production code, its callers, and the nearest tests before choosing what to change.
4. Verify a clean or task-owned worktree and apply the repository's current branch, platform, and shared-code isolation rules.
5. State the trigger, observable result, and failure mode the test must prove before choosing a test layer.

When a test or test helper is written in PowerShell, also use `$write-powershell` and apply its compatibility, style, output, and safety rules.

## Choose the boundary

- Put deterministic domain and policy behavior in the lowest test layer that has no platform dependency.
- Test commands, state transitions, and presentation behavior through public boundaries with fakes.
- Use platform or integration tests for native policies, serialization, local protocol integration, filesystem boundaries, and files that are themselves distribution contracts.
- Use the repository's chosen UI automation stack only for interaction that cannot be proved below the UI layer. Select controls through stable automation identifiers.
- Match a test target's framework and bootstrap requirements to the code it exercises. Enable UI-framework initialization only when the test directly uses APIs that require it.

## Make tests reliable

- Name tests as a concrete trigger and observable result.
- Prefer fixed identifiers, fixed timestamps, explicit inputs, fakes, local protocol servers, and completion signals.
- Put bounded timeouts on asynchronous boundaries so failures terminate. Use `TaskCompletionSource`, cancellation, callbacks, or emitted events to detect readiness; do not sleep for an arbitrary duration while waiting for expected state.
- When elapsed time is the behavior, derive the wait from the production policy and keep the margin explicit.
- Assert the externally meaningful payload, state transition, ordering, cleanup, or recovery result. Do not mirror the implementation line by line.
- Exercise success and the consequential failure boundary. Add combinatorial cases only when each case protects a distinct rule.
- Keep tests independent of execution order, wall-clock date, machine locale, network access, user data, and installed application state.

Read a repository file directly only when the file is the contract, such as a project file, release manifest, workflow, installer script, localization catalog, or packaged asset. Do not test C# method bodies through source strings or depend on XAML whitespace, element order, or private symbol names.

Delete or replace tests that merely duplicate production code, assert formatting, depend on arbitrary delays, cover no meaningful failure, or prevent safe refactoring without protecting behavior. Preserve coverage for a real invariant by moving it to a behavioral or artifact boundary before deleting the old test.

## Validate

Discover test and build entry points from current project metadata, contributor guidance, and workflows. Run the nearest affected test target first, then the documented broader suite and affected build configurations.

For startup, UI composition, prerequisites, packaging, or distribution changes, use the repository's current relevant checks after inspecting their side effects. Run a complete release validation only when publishing, GUI startup, prerequisite installation, and other machine changes are within the user's authorized scope. Validate auxiliary artifacts with the compiler or packaging tool their actual build path uses.

Before handing off or committing, run `git diff --check`, inspect every changed path against the branch base, and confirm that the change follows the repository's current ownership and isolation rules. Report the behavior covered, tests removed or replaced, commands run, results, and any remaining manual UI validation.
