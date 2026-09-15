---
name: windows-code-review
description: Review substantive SIDEY Windows application and distribution changes for actionable correctness, privacy, lifecycle, concurrency, native-resource, packaging, and test defects. Use for Windows-owned diffs, commits, branches, or pull requests, including scripts/windows and Windows-specific workflow logic. Do not use for prose-only review or ordinary implementation work.
---

# Windows Code Review

Review the complete requested range and report only defects supported by a concrete trigger and execution path. Stay read-only unless the user also asks for fixes.

Apply the repository-root `AGENTS.md`, [`windows/AGENTS.md`](../../../windows/AGENTS.md), and the authoritative product or architecture documents relevant to the changed paths. Honor a user-supplied base; otherwise identify and state the intended integration base. Include Windows-owned files outside `windows/**`, especially `scripts/windows/**` and Windows workflow changes.

Inspect every changed hunk and trace affected callers, state owners, protocols, artifact consumers, tests, and cleanup paths. Do not infer safety from a successful build alone. If the range crosses a prohibited platform or shared-file boundary, identify the mixed paths and the safe split.

When the diff contains PowerShell, apply `$windows-powershell` for its caller and compatibility contract without leaving read-only review mode. If the review includes authorized test changes, also use `$windows-tests` to choose the correct boundary.

## Review Windows risks

Check only risks relevant to the diff, with particular attention to:

- cancellation, event unsubscription, task ownership, shutdown order, recovery coalescing, bounded-queue overflow, stale-event reconciliation, and lock ordering;
- ownership and cleanup of Win32, GDI, USER, COM, socket, timer, stream, registry, and process resources on success, failure, cancellation, and repeated initialization;
- UI-thread access, dispatcher lifetime, window activation, DPI and monitor transitions, taskbar and shell boundaries, and partial native-API failures;
- the root-defined privacy, backend, realtime, durable-storage, and server-enforcement boundaries;
- framework-dependent publishing, the launcher and `Runtime` layout, shared prerequisites, external assets, Release-only behavior, and installer upgrade, repair, rollback, and uninstall continuity.

Review test coverage at the narrowest boundary that proves the changed behavior. Look for missing failure, cancellation, cleanup, overflow, and repeat-use cases. Reject tests that mirror C# implementation bodies, depend on incidental XAML whitespace or ordering, duplicate production logic, use arbitrary sleeps, or require uncontrolled machine state. Structured inspection is appropriate when a project file, XAML declaration, manifest, workflow, installer source, localization catalog, or packaged asset is itself the contract.

Do not report mechanically enforced formatting or style unless enforcement is absent or failing. Report a maintainability issue only when it obscures ownership or side effects or creates a concrete path to incorrect behavior.

## Validate and report

For each suspected defect, identify the trigger, follow the execution path, and determine whether an existing guard or test prevents it. Run the narrowest useful non-installing check first and use the broader validation sequence in `windows/AGENTS.md` only when warranted. Publishing, installation, GUI startup, elevation, network access, release operations, or machine-state changes require matching user authorization. An unavailable or failed check is evidence to report, not proof of a code defect by itself.

Lead with findings in severity order:

- `P0`: immediate security, privacy, destructive-data, or broadly unusable-release risk;
- `P1`: likely release blocker or common user-facing regression;
- `P2`: concrete defect with a narrower trigger or a maintainability defect likely to cause incorrect behavior;
- `P3`: low-impact but concrete defect worth fixing; omit cosmetic preferences.

Give each finding an imperative title, one precise file and line, the triggering scenario, the impact, and the smallest safe correction. Do not attribute pre-existing or speculative issues to the reviewed change. After the findings, list material assumptions, validation performed, and meaningful residual gaps. If there are no findings, say so directly.
