# SIDEY Windows Developer Documentation Instructions

These instructions apply to `windows/docs/**` in addition to the repository-root and Windows `AGENTS.md` files.

## Location and language editions

- Keep Windows contributor and implementation guides in this directory. The Korean edition is `windows/docs/{topic}.md`; its English edition is `windows/docs/en/{topic}-en.md`.
- Use a concise lowercase topic name, with hyphens only when a multiword topic needs them. Keep paired editions on the same topic and align their technical claims, commands, headings, and links when either edition changes.
- Link a Korean guide to Korean neighbors and an English guide to English neighbors. Resolve relative links from the file that contains them; English files are one directory deeper.
- Do not place public README copy, release notes, store or download claims, policy text, or general product decisions here. Public release notes live under `docs/releases/**`; repository-wide decisions and specifications live in `docs/DECISIONS.md` and `docs/PRODUCT_SPEC.md` and require a separate shared change when updated.

## Writing and evidence

- Verify behavior against current Windows code, tests, project metadata, scripts, and CI before documenting it. Distinguish implemented behavior from a proposal or manual procedure.
- Preserve the language of the target edition. Use the natural polite conversational style already established in Korean guides and a direct technical-writing register in English guides. Keep identifiers, commands, paths, product names, and platform terms unchanged.
- Explain the concrete contributor problem and consequence. Use lists for real sets or procedures, not to fragment ordinary reasoning, and link to maintained details instead of copying long contracts between guides.
- Write commands for the repository root unless the guide explicitly states another working directory. Inspect commands with installation, publication, elevation, GUI, network, or other machine side effects and say so near the command.
- Validate relative links and code examples, run the narrowest relevant check for behavioral claims, and run `git diff --check`. Documentation-only edits do not require an application build when repository evidence is sufficient.

For the full research, drafting, and validation workflow, use [`windows-dev-docs`](../../.agents/skills/windows-dev-docs/SKILL.md).
