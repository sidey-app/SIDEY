---
name: write-docs
description: Create or revise developer and contributor documentation in the requested language. Verify claims against repository evidence, evaluate external guidance before adopting it, and apply the explanatory prose style defined by this skill. Do not use for public website copy or release notes.
---

# Write Docs

Write documentation that helps a contributor understand what to do, why the rule exists, and where the implementation proves it. The user's explicit instructions take precedence over this skill.

When drafting or revising Korean prose, read [references/korean-writing-style.md](references/korean-writing-style.md). For other languages, apply the common principles below using a natural technical-writing register for that language.

## Establish the source of truth

1. Resolve the repository root with `git rev-parse --show-toplevel` and use it for repository-relative paths.
2. Discover and read the repository instructions, authoritative product or architecture documents, and contributor guidance that apply to the target. Follow the precedence declared by the repository instead of assuming fixed document names.
3. Verify the current branch and worktree, then apply the repository's platform and shared-file isolation rules.
4. Trace each behavioral claim to the current code, tests, configuration, scripts, or packaging layout. Distinguish implemented behavior, planned behavior, and a manual procedure.
5. Identify the reader and the decision the document should help them make. Preserve useful existing content that still matches the program.

Do not change implementation merely because a draft document recommends it. When the user asks to align the program and documentation, evaluate the recommendation first, make only the authorized implementation changes through the relevant workflow, verify them, and then document the resulting behavior.

## Evaluate guidance before adopting it

Treat repository decisions and observable implementation as local evidence. Prefer official, primary documentation for language, framework, operating-system, and tool behavior. Use blogs and examples to discover ideas, not as authority.

Adopt an external rule when it fits the repository's actual language and tooling, reduces ambiguity or defect risk, and does not conflict with an established contract. Reject or narrow it when it is:

- specific to Unity, another framework, or a different application model;
- intended only for tutorial samples or documentation layout;
- a personal preference presented as a universal rule;
- already enforced more accurately by the repository's formatter configuration, compiler, analyzer, or tests;
- likely to hide platform, privacy, ownership, or lifecycle details that the application needs to keep visible.

Explain which tool enforces a mechanical rule. Reserve prose and review guidance for decisions that require context. Do not copy a source's whole checklist into a project document.

## Keep each guide responsible for one subject

Keep one guide focused on one subject and one reason to change. Discover the current documentation set before deciding whether to extend an existing guide, replace stale material, or add a new guide. Keep contributor entry points concise and link to detailed guidance instead of duplicating it.

Place Korean guides at `docs/{topic}.md`, without a language directory or filename suffix. Place guides in other languages at `docs/{lang}/{topic}-{lang}.md`, using the same lowercase language code for both the directory and filename suffix. For example, use `docs/architecture.md` for Korean, `docs/en/architecture-en.md` for English, or `docs/ja/architecture-ja.md` for Japanese. When a region is needed, separate it from the language with an underscore in both positions, as in `docs/zh_cn/architecture-zh_cn.md`. Add a new guide only when its subject cannot fit an existing guide without mixing unrelated reasons to change.

When a product decision or shared scope must change, apply the repository's current ownership and branch rules instead of assuming the target belongs in the active platform change.

## Write from evidence to explanation

Start with the concrete problem a contributor can encounter. Explain the consequence in ordinary language, introduce the term or rule, and show a repository-relevant example. When a technical term first appears, explain what it means and why it matters in the current context. Describe concrete reading, maintenance, runtime, or operational costs instead of relying on broad claims such as “improves maintainability.”

Write in the language requested by the user. When no language is specified, preserve the target document's current language. Do not translate an existing document merely to make the documentation set uniform. Keep identifiers, commands, paths, product names, and API terms in their original form unless an established localized term makes the explanation clearer.

Use paragraphs for reasoning and lists for choices, procedures, or sets whose boundaries matter. Do not force every section into the same template, repeat transitions mechanically, or manufacture an example when the point is already clear. Prefer active phrasing when ownership or responsibility matters, and keep exact type names, commands, paths, limits, and platform terms when they help the reader verify a claim.

Use links for maintained details instead of repeating them. Keep external citations next to the claim they support and link to the primary page, not a search result. Do not quote long passages when a short explanation is enough.

Complete and validate the document without depending on a separate polishing skill. Afterward, the user may choose a language-specific prose-polishing skill such as `$humanize-korean` to remove AI-like phrasing or improve rhythm. Treat that as an optional follow-up, not part of this skill, and do not invoke it unless the user asks.

## Validate the document

- Resolve every relative Markdown link and confirm renamed files have no stale references.
- Verify code examples are valid code or clearly marked pseudocode.
- Check commands from the working directory stated by the document.
- Search for stale product names, paths, counts, platform promises, and incorrect documentation paths. Korean guides use `docs/{topic}.md`; other language editions use `docs/{lang}/{topic}-{lang}.md`.
- Check that headings describe the reader's concern and that lists are used for real sets or procedures, not to fragment ordinary explanation.
- Run `git diff --check` and inspect every changed path. Documentation-only work does not require an application build unless the claims can be verified only by running one.

Report the evidence inspected, guidance adopted or rejected when material, files changed, validation performed, and remaining implementation or product-decision gaps.
