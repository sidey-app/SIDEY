---
name: sidey-public-web
description: Create or revise SIDEY public website landing, store, policy, and checkout presentation when copy or responsive layout changes. Keep public text durable and user-facing, verify availability claims against shipped behavior, and keep internal rollout language out of merchandising pages. Do not use for README or release notes; use sidey-release-docs instead.
---

# SIDEY Public Web

Write public pages for ordinary SIDEY users. Describe the product, purchase path, terms, and limitations without turning the website into an engineering status page.

## Required context

1. Read the repository-root `AGENTS.md` completely.
2. Read `docs/DECISIONS.md`, then `docs/PRODUCT_SPEC.md`; confirmed decisions win.
3. Inspect the target page, related policy pages, existing web tests, and the shipped app or server behavior behind any availability claim.
4. Work on `shared/<topic>`. Use an isolated worktree when the current branch is wrong or another task owns the working tree.

## Public copy

- Lead with stable user value or an action. Store heroes and catalog cards describe the products and where purchases happen; they do not announce preparation work or rollout phases.
- Keep internal environment and implementation terms such as `production`, `staging`, `Sidey-dev`, test channels, migrations, channel keys, and server topology out of merchandising pages. Convert relevant facts into plain user behavior or omit them.
- Do not use `출시 예정`, `준비 중`, or similar temporary status as fixed store copy unless the user explicitly requests a time-bound announcement and the confirmed decisions support it.
- Never claim that a purchase or download is currently available without evidence from the shipped client and server. When availability is not live, describe the intended app, platform, purchase path, prices, and terms without inventing a live CTA.
- Preserve user-relevant legal, privacy, refund, supported-platform, and security limitations. Rewrite developer jargon in plain language instead of silently deleting a limitation users need.
- Keep the product name `SIDEY`. Do not expose checkout tokens, payment identifiers, secrets, or unpublished operational instructions.

## Layout

- Use semantic HTML and explicit CSS for visible structures. In particular, never leave seller or policy definition lists on browser-default `dt`/`dd` spacing.
- Align repeated labels and values on a shared grid, keep row spacing and dividers consistent, and allow long addresses and email links to wrap without horizontal overflow.
- Keep Korean headings and paragraphs from leaving a single syllable or punctuation mark on its own line. Tune the copy and usable width first, then apply `word-break: keep-all` with `text-wrap: balance` for headings or `text-wrap: pretty` for prose. Do not add a hardcoded `<br>` unless that break is intentional at every target width.
- Keep secondary store and policy pages below landing-page display scale. Scope typography to a page class so a store cleanup does not silently resize the home page.
- Check desktop and narrow mobile widths. Keep existing static-page ownership in HTML and the shared stylesheet; do not add a framework or JavaScript for copy-only layout work.

## Decision and scope discipline

- Update `docs/DECISIONS.md` in the same change when public product wording becomes a confirmed rule. Update `docs/PRODUCT_SPEC.md` when public behavior or scope changes.
- Keep public catalog copy separate from internal truth: internal documents may retain accurate deployment locks and test-environment details that do not belong on the landing page.
- Do not change app purchase gates, backend sales settings, checkout behavior, deploy, or publish merely because public copy changes. Those require explicit scope and verification.

## Validation

- Run `node --test website/tests/commerce-pages.test.mjs` and any other affected web checks.
- Test durable invariants such as products, prices, purchase path, seller fields, links, and absence of internal rollout jargon; avoid locking tests to an entire headline or paragraph.
- Inspect desktop and mobile rendering for alignment, Korean orphan lines, wrapping, focus visibility, and overflow.
- Search the final public pages for temporary status and internal environment terms, then inspect every changed path against the branch base.
