---
name: sidey-workflow
description: Start, resume, verify and integrate SIDEY repository tasks, or open the current macOS app with verified provenance. Use for repository changes and app review, not for general product discussion.
---

# SIDEY Workflow

Run the repository checker; a cached origin/main, open Xcode window or installed app name is not freshness evidence.

- Begin with `python3 scripts/workflow.py doctor`. Record the fetched remote SHA and worktree ownership. A failed fetch means freshness is unverified.
- Create a task from freshly fetched main using `start <task-id> --platform shared|macos|windows --worktree <new-absolute-path>`. The default app is `SIDEYAppStore`. Use `--repo <path>` before the command to select a repository.
- Resume from the registered worktree with `sync <task-id>`. Preserve dirty changes in explicit task commits first. Resolve a reported merge conflict in that worktree, then check again. Never stash, reset or force push to synchronize.
- Run `check <task-id>` after changes. It checks all changed paths, including both sides of moves and untracked files, and records the source/head/base. Platform tests, database tests and web/server checks are enforced by the CI integration gate. A local check alone is not full validation.
- Review the complete task diff. `finish <task-id> --paths <each-dirty-path> --message <commit-message> --title <PR-title> --body-file <reviewed-body-file>` commits only the explicitly enumerated task changes and creates the PR. For already committed work, omit paths/message. It refuses completion until the exact head passes CI and the base is current. Run it again when CI completes; if main advanced, sync and check again.
- Finish merges with a merge commit and fast-forwards the primary main worktree. A blocked primary update is incomplete integration. Platform tasks remain `main-updated` until app verification; for macOS use `open --task <task-id>` on latest main to record completion. Never merge unrelated PRs or unfinished branches to make main “latest.”
- For app review, use `open` (latest primary main, App Store by default), or `open --preview <absolute-worktree>`. `--offline` is allowed only for an explicit preview and must be reported as freshness unverified. If the verified opener is absent or any check fails, do not claim the app was opened or verified.
- Report fetched SHA, task target, applied checks, PR/main status and preview status. For app opening, report the actual project path, scheme and running build provenance only when the opener confirms them. App-affecting work is not complete after merge alone.

Task records and locks live under the Git common directory, never in product documents. Clean up only missing worktree metadata or clean, merged worktrees after checking untracked/ignored files and active usage. Preserve recording settings. Public releases, App Store upload and production deployment need their own explicit task authorization.
