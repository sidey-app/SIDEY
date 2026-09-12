---
name: sidey-versioning
description: Determine, apply, and validate independent macOS and Windows semantic versions for SIDEY from the actual diff. Use when choosing the next app version, preparing a candidate or stable release version, changing version fields, or auditing release-version consistency. Do not use it to write public release copy; use sidey-release-docs for that.
---

# SIDEY Versioning

Own version classification, version-number changes, build-number allocation, and consistency checks. Keep macOS and Windows version lines independent. Do not rewrite historical releases to fit this policy.

Use [sidey-workflow](../sidey-workflow/SKILL.md) and `scripts/workflow.py` for fresh-main, worktree ownership, checked-head and completion checks.

## Establish the evidence

1. Read the repository-root `AGENTS.md`, `docs/DECISIONS.md`, and `docs/PRODUCT_SPEC.md`; confirmed decisions win.
2. Run `git status --short --branch`. Never edit `main`, switch or clean another task's dirty worktree, or mix platform and shared changes. Create an isolated correctly prefixed worktree when needed.
3. Read `release/macos.json` and `release/windows.json`. They are the public stable baselines. The matching tags are `v<version>` for macOS and `windows-v<version>` for Windows. Read `scripts/verify_release_consistency.py` for the current required source fields and mirrors rather than relying on a stale hard-coded file list.
4. For each target platform, inspect the commit list, changed paths, and actual hunks from its matching public tag through the proposed release head. A useful starting point is `git diff --name-status <tag>...HEAD`, followed by focused `git diff` and `git log`; never classify from commit titles alone.
5. Decide whether the target platform's distributed app or its packaging inputs actually change. Count a shared change only when that platform consumes it in the proposed artifact. A website-only or server-only change does not bump either app.
6. If the comparison ref, target platform, shipped behavior, or artifact impact is ambiguous, report what evidence is missing and stop before changing a version.

Use the current public manifests rather than examples as authority. At adoption, the baselines are macOS `1.0.10` and Windows `1.0.8`; the ordinary next PATCH/MINOR examples are `1.0.11`/`1.1.0` and `1.0.9`/`1.1.0` respectively.

## Classify the minimum version

Choose the highest class present in the complete app-affecting diff:

| Class | Required when |
| --- | --- |
| `MAJOR` | Existing accounts, persisted data, protocol compatibility, installation continuity, or supported-OS compatibility breaks; an existing user must manually migrate, reset, reinstall through a new incompatible path, or otherwise intervene. |
| `MINOR` | A backward-compatible user feature, product or content is added, or the user contract or behavior changes meaningfully. New characters, cosmetics, and other purchasable or selectable content are MINOR. |
| `PATCH` | The artifact contains only fixes or improvements to bugs, UI, accessibility, performance, stability, security, internal code, documentation, packaging, or release tooling, without a MINOR or MAJOR change. |

Security work is PATCH unless its compatibility effect independently requires MAJOR. Refactoring is not MINOR merely because it is large. A small-looking account, storage, protocol, installer, or OS-support change can still be MAJOR.

Shared documentation, website, backend, or release-tooling work can help describe the class of an app release, but it does not trigger an app bump by itself when no distributed app artifact changes. Return `NO APP BUMP` for a web-only or server-only diff.

For a baseline `X.Y.Z`, calculate PATCH as `X.Y.(Z+1)`, MINOR as `X.(Y+1).0`, and MAJOR as `(X+1).0.0`. Mixed changes use the highest required class. A user may explicitly choose a higher class, but reject any requested class below the evidence-based minimum. Use the exact next number for the chosen class; do not skip ahead within a class or accept a number that is not strictly newer than the platform baseline.

Apply these representative cases consistently:

- a fix to existing app behavior only: PATCH;
- a backward-compatible app feature or new content: MINOR;
- a change requiring existing users to migrate manually: MAJOR;
- a website-only change with unchanged app artifacts: `NO APP BUMP`;
- mixed changes: the highest present class, such as MINOR for fix plus feature or MAJOR when any compatibility break is included.

## Report before applying

For a recommendation, return:

- target platform and public baseline;
- exact comparison range and whether the app artifact changes;
- evidence grouped by PATCH, MINOR, and MAJOR impact;
- minimum class, proposed stable version, and any user-selected higher class;
- files that would need platform-local and shared release-metadata changes;
- unresolved build, tag, or release blockers.

Do not change files for an advisory-only request. When the user asks to apply a version, make only the requested, evidence-backed changes and validate them.

## Candidate versions

- Represent an internal candidate through its branch, workflow, or expiring CI artifact. Do not put `-alpha`, `-beta`, `-rc`, or another prerelease suffix in platform source versions or production manifests. Platform source may carry the next stable version while the public manifest and public download metadata remain on the released version until release preparation.
- Do not alter existing tags, release notes, manifests, or historical `1.0.x` releases to make them match the new policy.
- A Windows candidate may keep `release/windows.json` at the public version while the project and updater use a newer stable source version. Validate that state with `--allow-unreleased-source`.
- Keep a Mac App Store-only candidate on the same marketing version as the equivalent direct app. It may use a higher, unused build while the direct target and public manifest stay unchanged.
- When a macOS direct source version and its shared manifest update are isolated on separate branches, the source-only branch cannot pass the repository-wide consistency checker. Do not call that mismatch a successful validation. Combine the reviewed platform and shared commits in a release-integration worktree, then run the pending-metadata check there.
- Keep public README, website, appcast, update manifest, and download links on the last released version until the release-preparation change is intentionally staged.

## macOS marketing and build versions

- Direct and Mac App Store distributions with equivalent features use the same marketing version.
- Before assigning a build for an artifact that will be uploaded or publicly distributed, find the greatest build already used across both distributions. Inspect both Xcode targets, `release/macos.json`, the appcast and release evidence, plus the actual upload history when it can contain a newer build. The next build is that combined maximum plus one.
- A local build does not consume a build number. Do not bump merely because a developer compiled or archived locally.
- Uploading or publishing consumes the build number. If that uploaded artifact is rebuilt for another upload, increment the build again; never replace it under the same build.
- If the greatest uploaded build cannot be established, label a computed build provisional and stop before upload or publication.

## Change isolation

- Put macOS implementation and macOS-specific source-version changes on `macos/<topic>`. Do not touch Windows implementation files there.
- Put Windows implementation and Windows-specific source-version changes on `windows/<topic>`. Do not touch macOS implementation files there.
- Put `release/*.json`, README, decision documents, public manifests, website release metadata, and other shared release state on `shared/<topic>`.
- Never mix a new platform implementation-version edit and a new shared metadata edit in one commit. Land or review them separately, then merge or cherry-pick the reviewed commits into the release integration branch that needs both.
- Before any commit or handoff, inspect every changed path relative to the branch base. Stop on a wrong-prefix branch, unrelated dirty state, cross-platform files, or mixed platform/shared changes.

Changing the version does not authorize a commit, push, upload, tag, release, or deployment. Perform only the operations the user requested. In particular, do not create or push a tag, upload an artifact, publish a release, or deploy without explicit authorization for that external action.

## Release metadata and copy ownership

Use `sidey-release-docs` when README updates, `docs/releases/*`, or GitHub Release prose must be written. This skill owns the selected version/build and verifies that every occurrence is consistent; it does not invent or rewrite public change descriptions.

Immediately before creating a stable tag, confirm the exact tag is absent locally and on the remote. Refuse to reuse an existing `vX.Y.Z` or `windows-vX.Y.Z`, even if an artifact or release was deleted.

## Validation

After composing the relevant isolated changes in a release-integration worktree, run the candidate/staged metadata check:

```sh
./scripts/verify_release_consistency.sh \
  --allow-pending-appcast \
  --allow-unreleased-source
```

The allowances only accept the intentional states implemented by the existing checker: an older signed macOS appcast than the staged macOS manifest, and a newer internally consistent Windows source version than its public manifest. They do not waive malformed, missing, reused, or decreasing versions.

Immediately before a stable release, run the target platform's strict check without allowances:

```sh
./scripts/verify_release_consistency.sh --platform macos
./scripts/verify_release_consistency.sh --platform windows
```

Run only the command for the platform being released unless both releases are in scope. Also run platform build/tests required by the changed implementation; version consistency does not replace artifact validation.

## Mandatory stops

Refuse the version operation and explain the recovery path when any of these is true:

- the app artifact does not change, so no app bump is warranted;
- the requested class or number is below the minimum, not newer than the baseline, malformed, or missing from a required source location;
- platform source, updater, production manifest, release notes, or public metadata disagree outside an explicitly allowed candidate state;
- the proposed tag already exists locally or remotely;
- a macOS build is not greater than every build already consumed across direct and App Store uploads, or an uploaded artifact was rebuilt without another increment;
- platform implementation and shared release-state edits are mixed in one commit or appear on the wrong branch;
- the diff includes an unresolved compatibility break, or the evidence is insufficient to classify it safely.

Do not bypass these stops by lowering the classification, editing history, adding a prerelease suffix to production metadata, deleting a tag, or relaxing the consistency checker.
