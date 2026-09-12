---
name: code-review
description: Review Windows application changes for actionable correctness, regression, privacy, concurrency, native-resource, packaging, and test-quality defects. Use for local diffs, commits, branches, or pull requests. Do not use for prose-only review.
---

# Code Review

Review for defects that could change user-visible behavior, corrupt state, weaken privacy or security, leak native resources, destabilize long-running use, or make releases unreliable. The user's explicit instructions take precedence over this skill.

Do not edit code during a review unless the user also asks for fixes. Read-only review and local validation do not require permission.

## Establish the review range

1. Resolve the repository root with `git rev-parse --show-toplevel` and use it as the working directory for repository-relative paths and commands.
2. Discover and read the instructions, authoritative product or architecture documents, test guidance, and style or analyzer configuration that apply to the changed paths. Follow the precedence declared by the repository instead of assuming fixed document names.
3. Verify the current branch and worktree. Use the user's base ref when supplied; otherwise determine the intended integration or release base from repository evidence and state the comparison range.
4. Inspect every changed path and hunk, then trace affected callers, state owners, protocols, assets, tests, and cleanup paths. Do not infer safety from a passing build alone.
5. Apply the repository's current branch, platform, and shared-code isolation rules. Distinguish previously reviewed merged changes from newly mixed edits and report a concrete safe split when the review range crosses a prohibited boundary.

When the diff contains PowerShell, also use `$write-powershell` and apply its compatibility, parameter, pipeline, output, error-handling, and safety rules.

## Review the Windows invariants

Apply the relevant product, architecture, privacy, and platform constraints discovered in the repository. Check only invariants relevant to the diff, with particular attention to these implementation risks:

- Check cancellation, event unsubscription, task ownership, shutdown order, recovery coalescing, bounded-queue overflow, stale-event reconciliation, and lock ordering.
- Check every Win32, GDI, USER, COM, socket, timer, stream, registry, and process handle for correct ownership and cleanup on success, failure, cancellation, and repeated initialization.
- Check UI-thread access, dispatcher lifetime, window activation, DPI and monitor transitions, taskbar and shell boundaries, and behavior when native APIs fail or return partial data.
- For startup and distribution changes, check publishing mode, runtime prerequisites, upgrade and uninstall continuity, asset layout, release-only behavior, and compatibility with every compiler or packaging tool the affected artifacts actually use.
- For network, account, persistence, or realtime changes, verify that client, transient transport, durable storage, and server-enforced responsibilities remain on the boundaries defined by the authoritative documents.

## Review tests and maintainability

- Require tests at the narrowest boundary that proves the changed behavior. Look for missing failure, cancellation, cleanup, overflow, and repeat-use cases.
- Flag tests that inspect implementation source text, depend on UI markup formatting or element order, duplicate the implementation, use arbitrary sleeps, or rely on machine state.
- Accept direct file inspection when the file itself is a distribution contract.
- Use the repository's chosen UI automation stack with stable automation identifiers only for interaction that cannot be covered below the UI.
- Discover and apply the repository's current style guide and enforceable formatter or analyzer configuration. Do not repeat mechanically enforced rules as manual findings unless enforcement is missing or failing. Report a style finding only when the change creates ambiguity, hides ownership or side effects, or materially increases defect risk.

## Validate findings

For each suspected defect, identify a concrete trigger, follow the execution path, and check whether an existing test or guard actually prevents it. Run the narrowest useful validation first, then broader Windows checks when needed. Do not publish, install, push, or mutate external state as part of review unless the user explicitly asks.

Discover the repository's current build and test entry points from maintained contributor guidance, project metadata, and workflows. Run the narrowest non-installing check that can prove or disprove a finding before broader validation. Inspect a validation command's side effects before running it; full release checks that publish artifacts, start GUI processes, install prerequisites, or otherwise change machine state require explicit user scope. A failed or unavailable check is evidence to report, not proof of a code defect by itself.

## Report

Lead with findings sorted by severity:

- `P0`: immediate security, privacy, destructive-data, or broadly unusable-release risk.
- `P1`: likely release blocker or common user-facing regression.
- `P2`: real defect with a narrower trigger or material maintainability risk that can cause incorrect changes.
- `P3`: low-impact but concrete defect worth fixing; omit cosmetic preferences.

Each finding must have a short imperative title, one precise file and line location, the triggering scenario, the impact, and the smallest safe correction. Do not report pre-existing or speculative issues as findings introduced by the reviewed diff.

After findings, list material assumptions and validation performed. If there are no findings, say so directly and mention only meaningful residual test or manual-validation gaps.
