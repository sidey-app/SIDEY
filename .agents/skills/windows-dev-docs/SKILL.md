---
name: windows-dev-docs
description: Create or revise SIDEY Windows developer guides under windows/docs. Use for evidence-based implementation, contributor, debugging, deployment, localization, logging, or code-style documentation. Do not use for public README or release copy, website or policy copy, repository-wide product documents, backend documentation, review-only requests, or implementation-only work.
---

# Windows Developer Documentation

Write Windows guides whose claims, commands, and links a contributor can verify against the current repository.

## Establish the documentation contract

1. Read the repository-root `AGENTS.md`, `windows/AGENTS.md`, and `windows/docs/AGENTS.md`. The last file owns guide locations, paired editions, language conventions, and path-specific validation rules; do not duplicate or override them here.
2. Read the target guide and its paired edition when one exists. Identify the contributor problem and the decision or procedure the guide must support.
3. Trace every behavioral claim to current Windows code, tests, project metadata, scripts, packaging inputs, or CI. Confirmed decisions take precedence where the repository instructions say they do.
4. Mark planned behavior and manual procedures as such. Do not present either as implemented or verified behavior.
5. Keep implementation changes and product decisions out of a documentation-only task. If accurate documentation requires either, report the gap and follow the repository's separate ownership and branch rules.

## Draft from evidence

- Explain the concrete failure, maintenance cost, or contributor choice before introducing a rule.
- Keep exact identifiers, paths, commands, limits, and platform terms when they help the reader find the evidence.
- Link to maintained details instead of copying contracts across guides.
- Preserve useful text that still matches the implementation. Add a new guide only when the subject cannot fit an existing guide without mixing unrelated reasons to change.
- For a Korean guide, read [references/korean-writing-style.md](references/korean-writing-style.md). Do not load that reference for an English-only change.

## Verify claims, commands, and links

- Re-read each cited implementation source and ensure the prose does not promise more than it proves.
- Read every referenced script and its direct callers before documenting a command. Supply mandatory parameters, use the working directory stated by the guide, and describe installation, publication, elevation, GUI, network, process, or machine-state effects near the command.
- Run the narrowest safe repository check that proves a behavioral claim. Follow `windows/AGENTS.md` for the maintained Windows checks. Documentation-only changes do not require a local application build when repository evidence is sufficient.
- Resolve every relative Markdown link from the file containing it. There is no dedicated repository Markdown-link checker, so confirm local targets explicitly and search renamed paths for stale references.
- Compare paired editions for equivalent technical claims, commands, headings, and language-appropriate links. They need not be literal translations.
- Verify code examples as executable code or label them clearly as pseudocode.
- Search changed text for stale product names, paths, counts, versions, platform promises, and unsupported availability claims.
- Run `git diff --check` and inspect every changed path against the branch base.

Report the guides changed, implementation evidence inspected, checks run, and any unresolved implementation or product-decision gap.
