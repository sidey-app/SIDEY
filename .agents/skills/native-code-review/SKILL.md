---
name: native-code-review
description: Review substantive SIDEY macOS or Windows application and distribution changes for actionable correctness, privacy, lifecycle, concurrency, native-resource, packaging and test defects. Use for native diffs, commits, branches or pull requests; do not use for prose-only review, website or backend review, or ordinary implementation work.
---

# Native Code Review

Review the complete requested range and report only defects supported by a concrete trigger and execution path. Stay read-only unless the user also asks for fixes.

Apply the repository-root `AGENTS.md`, every nested `AGENTS.md` governing the changed paths, and the authoritative product or architecture documents relevant to the change. Honor a user-supplied base; otherwise identify and state the intended integration base. Include native-owned scripts, workflows, packaging inputs and generated consumers outside the application directory.

Read only the platform references needed by the range:

- For macOS, read [references/macos.md](references/macos.md).
- For Windows, read [references/windows.md](references/windows.md).

If a range crosses platforms or a shared-file boundary, review each affected contract but identify any prohibited implementation mix and the safe split. When Windows-owned PowerShell is present, also apply `$windows-powershell` without leaving read-only review mode. When authorized test changes are part of the task, use `$native-tests` to select the boundary.

## Review common risks

Inspect every changed hunk and trace affected callers, state owners, protocols, persistence, artifact consumers, tests and cleanup paths. Check only risks relevant to the diff, especially:

- cancellation, observer or event removal, task ownership, shutdown order, recovery coalescing, bounded queues, stale-event reconciliation and lock ordering;
- UI-thread or main-actor access, process and window lifetime, partial native-API failures, and resource cleanup on success, failure, cancellation and repeat use;
- the root-defined privacy, backend, realtime, durable-storage and server-enforcement boundaries;
- distribution-specific behavior, external assets, release-only paths, upgrades, rollback and uninstall or replacement continuity.

Review coverage at the narrowest boundary that proves the behavior. Look for missing failure, cancellation, cleanup, overflow and repeat-use cases. Reject tests that mirror implementation bodies, depend on incidental source formatting, duplicate production logic, use arbitrary sleeps or require uncontrolled machine state. Structured inspection is appropriate when declarations, manifests, workflows, project files, localization catalogs or packaged assets are themselves the contract.

Do not report mechanically enforced formatting or style unless enforcement is absent or failing. Report maintainability only when it obscures ownership or side effects or creates a concrete path to incorrect behavior.

## Validate and report

For each suspected defect, identify the trigger, follow the execution path and determine whether an existing guard or test prevents it. Run the narrowest useful non-mutating check first and follow the selected platform instructions for broader validation. An unavailable or failed check is evidence to report, not proof of a code defect by itself.

Lead with findings in severity order:

- `P0`: immediate security, privacy, destructive-data or broadly unusable-release risk;
- `P1`: likely release blocker or common user-facing regression;
- `P2`: concrete defect with a narrower trigger, or a maintainability defect likely to cause incorrect behavior;
- `P3`: low-impact but concrete defect worth fixing; omit cosmetic preferences.

Give each finding an imperative title, one precise file and line, the triggering scenario, the impact and the smallest safe correction. Do not attribute pre-existing or speculative issues to the reviewed change. Then list material assumptions, validation performed and meaningful residual gaps. If there are no findings, say so directly.
