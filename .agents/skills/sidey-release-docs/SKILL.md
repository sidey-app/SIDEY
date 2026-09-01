---
name: sidey-release-docs
description: Write or update SIDEY README update sections, release-note files, and public GitHub release copy for a new macOS or Windows version. Use when preparing, publishing, or revising a SIDEY release, changelog, latest-update summary, or future roadmap. Keep wording concise and user-facing, verify claims against repository and release evidence, and enforce SIDEY platform branch isolation.
---

# SIDEY Release Docs

Create public release writing for ordinary SIDEY users. Describe what changed for the user, not how it was implemented.

## Required context

1. Read the repository-root `AGENTS.md` completely.
2. Read `docs/DECISIONS.md`, then `docs/PRODUCT_SPEC.md`. Confirmed decisions win.
3. Inspect the target tag, version, release date, actual diff, tests, and existing public release before drafting.
4. Do not claim a feature, fix, platform, signing state, or validation result without evidence.

## Branch guard

- Make README, release-note, roadmap, and other shared documentation changes only on `shared/<topic>`.
- Never edit macOS or Windows implementation files while using this skill.
- Do not switch, clean, or reuse a dirty worktree owned by another task or agent.
- Before committing or publishing, inspect all changed paths and stop if platform implementation files are present.

## Writing rules

- Use the product name `SIDEY`.
- Lead with the user-visible result. Prefer `결제 기능이 추가되었습니다.` over implementation details.
- Summarize backend, database, refactoring, performance, or operational-only work as `내부 안정성이 개선되었습니다.` or `내부 운영 구조가 개선되었습니다.` when it materially supports the release.
- Omit table names, schema names, classes, APIs, frameworks, algorithms, migrations, and build-pipeline details unless the user must act on them.
- Keep each change to one short sentence. Merge related implementation work into one outcome.
- Preserve essential installation actions, supported OS and architecture, data-loss risks, unsigned-build warnings, and known limitations.
- Never claim E2EE, universal overlay compatibility, completed manual validation, or release signing that has not been verified.
- Keep released changes separate from future plans. A roadmap item is not a release claim.

## README contract

- Preserve the short product introduction, official website, and preview image.
- Keep installation instructions separated into `macOS` and `Windows`.
- Under `최신 업데이트`, maintain independent platform blocks with date, version, and concise user-visible changes.
- Under `추후 개선 및 개발 예정`, use one common list. Add a platform label only when an item is platform-specific.
- Do not add technical-stack, architecture, backend, development, or build instructions to the public README.

## Release-note contract

- Use the matching file under `docs/releases/` as the source for the public GitHub release body.
- Include a short summary, installation instructions, user-visible changes, and only the warnings users need.
- Keep macOS and Windows release notes independent. Never copy an unverified change from one platform to the other.

## Publishing safety

- Draft and validate files by default. Do not create tags, upload artifacts, deploy, or edit a public release unless the user explicitly authorizes that external change.
- When public release editing is authorized, update from the committed release-note file and read the result back from GitHub.
- Never force-push. Stop on a non-fast-forward update and reconcile from the latest remote branch.

## Validation

- Verify version and date consistency across README, release file, and public release.
- Search the final public copy for unnecessary implementation jargon.
- Run the skill validator and inspect the final branch diff before handoff.
