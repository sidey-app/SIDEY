# Contributing to SIDEY

SIDEY welcomes contributions to code, tests, documentation, and translations.
External asset contributions are not accepted.

Start with the problem you want to solve. Search the existing
[issues](https://github.com/sidey-app/SIDEY/issues) before opening a new one.
If an issue already covers the same request, add a reaction instead of a
`+1` comment. For a new feature, behavior change, or large refactor, describe
the user scenario and agree on the direction with the maintainers before
writing code. Small, self-contained fixes such as typo corrections may go
straight to a pull request.

## Report an issue

Use the repository's issue forms for
[bugs](.github/ISSUE_TEMPLATE/01-bug-report.yml),
[feature requests](.github/ISSUE_TEMPLATE/02-feature-request.yml), and
[documentation problems](.github/ISSUE_TEMPLATE/03-docs-issue.yml). Include
the steps needed to reproduce a bug, what you expected, what happened, and the
SIDEY and operating-system versions involved.

Remove access tokens, invite codes, message contents, personal information,
and other secrets from logs and screenshots before posting them.

## Choose the right contribution path

Read the relevant [current product documents](docs/product/overview.md) and
[architecture](docs/architecture.md) before changing product behavior. Consult
[long-lived decisions](docs/decisions/README.md) when the change touches an established
identity, security, distribution or source-of-truth boundary. Machine-readable source and
code own exact values; decision records explain rationale rather than overriding current
state. Keep a change focused on the issue it addresses.

Code, tests, documentation, translations, workflows, and other repository
changes use the
[general pull request template](.github/PULL_REQUEST_TEMPLATE/general.md).

## Contribution licensing

SIDEY software source code is licensed under GNU AGPL version 3 only
(`AGPL-3.0-only`); see [LICENSE](LICENSE) and the
[licensing scope](LICENSING.md). By intentionally submitting code for inclusion,
you agree to license your contribution under those terms and confirm that you
have the right to do so. Identify any third-party material and its license in
your pull request, and preserve its existing notices.

Contributors retain their copyright. A code contribution does not transfer
copyright, grant SIDEY a separate proprietary license, or by itself create an
entitlement to payment, revenue sharing or ownership of the business.

Do not submit character, bubble, throwable, audio, logo or other asset files.
Existing assets and their mirrors remain available for maintainer-controlled
maintenance under their existing licenses; this is not an asset intake process.

## Set up an external fork

External contributors can fork SIDEY on GitHub, clone that fork as `origin`,
and add the canonical repository as `upstream`:

```shell
git clone https://github.com/YOUR-GITHUB-USER/SIDEY.git
cd SIDEY
git remote add upstream https://github.com/sidey-app/SIDEY.git
git remote -v
```

Keep `upstream` pointed at the canonical repository. The task workflow starts
and checks work against canonical `upstream/main`, rather than the fork's
possibly stale `origin/main`.

## Create an isolated worktree

Do not implement changes directly on `main`. Give each task its own worktree
and use the prefix that covers the complete change:

- `macos/<topic>` for macOS implementation
- `windows/<topic>` for Windows implementation
- `shared/<topic>` for shared documentation, website, protocol, and
  repository-wide work

Start a tracked task from a clean primary checkout:

```shell
python3 scripts/skills/workflow.py doctor
python3 scripts/skills/workflow.py start <task> --platform <shared|macos|windows> --worktree <path>
```

Keep platform work separate. A `macos/*` branch must not change Windows-owned
files, and a `windows/*` branch must not change macOS-owned files. Put shared
changes on a `shared/*` branch and land them independently.

Do not clean, switch, or reuse another task's dirty worktree. Avoid unrelated
refactors, formatting, generated output, and documentation changes.

## Write commits

Directly authored commit subjects use this form:

```text
<type>(<optional-scope>): <Korean description>
```

Allowed types are `feat`, `fix`, `docs`, `test`, `perf`, `chore`, `style`,
`comment`, `ci`, `init`, `refactor`, `build`, and `revert`. Use standard
Conventional Commits spellings such as `feat`, `perf`, and `ci`.

The scope is optional. When present, use the affected domain, such as
`release` or `commerce`. Test scopes use `test/<domain>`. Keep the Korean
description within 50 characters, omit the final period, end with a word or
noun phrase, and avoid past tense.

The optional Korean body explains why the change is needed and how behavior
differs from before. Write it in the imperative or present tense and keep each
line within 72 characters. Use `Resolves`, `Closes`, or `Fixes` for a resolved
issue. Use `See also`, `Ref`, or `Related to` for related work.

For example:

```text
fix(auth): API 응답에 접근할 수 없는 문제 수정

CORS 설정이 없어 브라우저가 API 응답 접근을 차단합니다.
요청과 응답에 CORS 헤더를 추가합니다.

Resolves: #273
See also: #266
```

Install the attribution hook once per clone when Codex contributes to a
commit:

```shell
python3 scripts/skills/commit/setup_codex_attribution.py
```

Before committing, inspect the complete working tree, stage only the files for
the current commit, and review the staged diff:

```shell
git status --short
git add -- <files>
git diff --cached
python3 scripts/skills/commit/validate_commit_message.py --subject "<subject>"
git commit
```

Do not use `git add .` when unrelated changes may be present. Do not bypass a
failed hook or rewrite existing history to add attribution.

## Validate the exact head

Run the checks required by the changed paths. A failed, skipped, stale, or
unavailable required check is not a passing result. Fix the failure or report
the gap in the pull request.

Review the full diff against the branch base, then run the repository workflow
check. If any source file changes afterward, rerun the affected checks.

```shell
python3 scripts/skills/workflow.py check <task>
```

The pull request must point to the same commit that passed review and
validation.

## Open a pull request

Write the pull request title with the same commit-subject contract, without a
pull request number. Fill in every relevant section of the selected template,
including the reason for the change and the commands or manual checks you ran.
Leave checklist items unchecked when they do not pass.

Review every changed path before publishing the branch. Pushing a branch,
opening a pull request, merging, releasing, uploading to a store, and deploying
to production are separate actions. Perform only the actions that the task
explicitly authorizes.

Once branch publication and pull request creation are authorized, use the
checked task workflow:

```shell
python3 scripts/skills/workflow.py publish <task> --title "<title>" --body-file <path>
```

For a fork clone, `publish` pushes the checked branch to `origin` and creates
a cross-repository pull request into `sidey-app/SIDEY`. If the fork uses a
different remote name, select it explicitly with `--push-remote <remote>`.

Required CI must finish successfully before merge. SIDEY uses squash merge;
GitHub creates the squash commit title and body from the repository's merge
message settings.

## Review

Respond to review comments with a focused follow-up commit. Run the affected
checks again and make sure the pull request still identifies the reviewed
head. Do not replace the checked commit with an amended or rebuilt equivalent
without repeating review and validation.

We appreciate the time you spend reporting problems, explaining use cases,
testing fixes, and improving SIDEY.
