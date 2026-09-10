---
name: sidey-windows-code-review
description: Review SIDEY Windows changes under windows/** for actionable correctness, regression, privacy, concurrency, native-resource, packaging, and test-quality defects. Use for local diffs, commits, branches, or pull requests that affect the Windows app. Do not use for macOS-only or general prose review.
---

# SIDEY Windows Code Review

Review for defects that could change user-visible behavior, corrupt state, weaken privacy or security, leak native resources, destabilize long-running use, or make releases unreliable. The user's explicit instructions take precedence over this skill.

Do not edit code during a review unless the user also asks for fixes. Read-only review and local validation do not require permission.

## Establish the review range

1. Resolve the repository root with `git rev-parse --show-toplevel` and use it as the working directory for every repository-relative path and command below. The skill is normally discovered while Codex is started in `windows` or one of its descendants.
2. Read the repository-root `AGENTS.md`, `docs/DECISIONS.md`, and `docs/PRODUCT_SPEC.md`; confirmed decisions win. Read `windows/tests/README.md` for test boundaries.
3. Verify the current branch and worktree. Use the user's base ref when supplied; otherwise determine the intended integration or release base from repository evidence and state the comparison range.
4. Inspect every changed path and hunk, then trace affected callers, state owners, protocols, assets, tests, and cleanup paths. Do not infer safety from a passing build alone.
5. New edits for a `windows/*` implementation task must remain under `windows/**`. Distinguish already reviewed shared commits that were merged or cherry-picked from newly mixed shared edits. Flag macOS or newly mixed shared edits as a branch-isolation defect and give the safe split or cherry-pick path.

When the diff contains PowerShell, also read `../sidey-windows-powershell-authoring/SKILL.md` and apply its compatibility, parameter, pipeline, output, error-handling, and safety rules.

## Review the Windows invariants

Apply the root `AGENTS.md` sections **Branch and platform isolation** and **Non-negotiable rules** as the authoritative product and privacy checklist. Check only invariants relevant to the diff, with particular attention to these implementation risks:

- Check cancellation, event unsubscription, task ownership, shutdown order, recovery coalescing, bounded-queue overflow, stale-event reconciliation, and lock ordering.
- Check every Win32, GDI, USER, COM, socket, timer, stream, registry, and process handle for correct ownership and cleanup on success, failure, cancellation, and repeated initialization.
- Check UI-thread access, dispatcher lifetime, window activation, DPI and monitor transitions, taskbar and shell boundaries, and behavior when native APIs fail or return partial data.
- For startup and distribution changes, check framework-dependent publishing, runtime prerequisites, upgrade and uninstall continuity, icon and asset layout, release-only behavior, and compatibility with the .NET Framework compiler used for the launcher, uninstaller, and language selector.
- For realtime, account, room, or presence changes, verify that each client, transient channel, database, and server-enforced responsibility remains on the boundary defined by the authoritative documents.

## Review tests and maintainability

- Require tests at the narrowest boundary that proves the changed behavior. Look for missing failure, cancellation, cleanup, overflow, and repeat-use cases.
- Flag tests that inspect C# source text, depend on XAML formatting or element order, duplicate the implementation, use arbitrary sleeps, or rely on machine state.
- Accept direct file inspection when the file itself is a distribution contract.
- Prefer Appium Windows Driver with stable automation identifiers for WinUI interaction that cannot be covered below the UI.
- Treat formatter output and naming as build-enforced concerns. Report style only when it creates ambiguity or the configured enforcement is missing or failing.

## Validate findings

For each suspected defect, identify a concrete trigger, follow the execution path, and check whether an existing test or guard actually prevents it. Run the narrowest useful validation first, then broader Windows checks when needed. Do not publish, install, push, or mutate external state as part of review unless the user explicitly asks.

Use these repository checks when proportionate to the diff:

```powershell
dotnet test windows/SIDEY.Windows.slnx --configuration Release --nologo
dotnet build windows/SIDEY.Windows.slnx --configuration Debug --nologo
dotnet build windows/SIDEY.Windows.slnx --configuration Release --nologo
```

Use non-installing checks such as `scripts/windows/tests/Test-RuntimePrerequisites.ps1` during ordinary review. Run `scripts/windows/Test-WindowsBuild.ps1` only when the user explicitly requests full release validation because it publishes the app, starts a GUI process, and may install missing prerequisites. A failed or unavailable check is evidence to report, not proof of a code defect by itself.

## Report

Lead with findings sorted by severity:

- `P0`: immediate security, privacy, destructive-data, or broadly unusable-release risk.
- `P1`: likely release blocker or common user-facing regression.
- `P2`: real defect with a narrower trigger or material maintainability risk that can cause incorrect changes.
- `P3`: low-impact but concrete defect worth fixing; omit cosmetic preferences.

Each finding must have a short imperative title, one precise file and line location, the triggering scenario, the impact, and the smallest safe correction. Do not report pre-existing or speculative issues as findings introduced by the reviewed diff.

After findings, list material assumptions and validation performed. If there are no findings, say so directly and mention only meaningful residual test or manual-validation gaps.
