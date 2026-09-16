---
name: web-verification
description: Investigate and verify SIDEY public website copy and responsive presentation against shipped product evidence, correcting the site when requested and returning page, claim, test, and rendering verdicts. Use for landing, store, checkout, policy, or download presentation under website/**; do not use for README, release notes, generic developer documentation, or deployment.
---

# Web Verification

Evaluate the changed public experience, not merely whether its source compiles. The durable
public contract and presentation rules are owned by `website/AGENTS.md`; use this skill to
apply those rules to a concrete change and produce evidence.

## Inputs

Identify the changed or proposed routes, locales, claims, and viewport-sensitive components.
Read the relevant current product documents and architecture, then inspect the canonical
catalog, release manifest, policy source, tests, or shipped client/server behavior behind each
material claim. Source code and machine-readable sources own exact current values; decision
records explain long-lived rationale. Do not infer availability from planned code or internal
rollout state.

## Verification

1. Map changed source files to generated public routes and localized counterparts.
2. Check product, price, purchase, download, privacy, security, compatibility, refund, and
   availability statements against their current source evidence. Flag stale or unsupported
   claims and internal rollout terminology.
3. Run `pnpm --dir website test` and any narrower affected checks. Separate build/test results
   from claim correctness.
4. When presentation changes, inspect rendered desktop and narrow-mobile pages for hierarchy,
   wrapping, overflow, alignment, focus visibility, and locale-specific breakage. Use an actual
   browser or captured rendering when available; source inspection alone is not visual proof.
5. When correction is requested, make the smallest website change that resolves supported
   findings and repeat the affected checks.

Do not report a viewport, interaction, route, or claim as verified when its evidence was not
available. Record it as `NOT RUN` or make the overall verdict `BLOCKED` when it is required for
the requested conclusion.

## Evidence

```text
Routes / locales / changed sources
Claims: claim, source of truth, PASS / FAIL / NOT RUN
Automated checks: command, target, result
Rendering: viewport, route, method, observed result
Findings and corrections
Verdict: PASS / FAIL / BLOCKED
Unverified surfaces or limitations
```

This skill does not authorize app or backend behavior changes, sales-state changes, website
deployment, release publication, or production configuration changes.
