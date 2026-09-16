---
name: release-notes
description: Research, draft and validate the canonical user-facing release note for one SIDEY macOS or Windows release from its exact shipped commit and pull-request range, with author attribution and inclusion or exclusion evidence. Use for docs/releases/** or GitHub Release body preparation; do not use for README, developer documentation, version selection or release publication.
---

# Release Notes

Produce the canonical release body for one platform artifact. General documentation rules remain in `docs/AGENTS.md`; this skill owns the release-specific investigation, attribution, copy and format validation.

## Inputs

Establish the platform, target version and commit, intended artifact, and previous published regular release for that platform. Use the matching `release/*.json` as release metadata. A staged target manifest is not evidence that its tag has shipped. Stop with `BLOCKED` if the target, artifact or comparison baseline is ambiguous.

## Collect and classify evidence

Read [references/evidence.md](references/evidence.md), then use the read-only
[collector](../../../scripts/skills/release-notes/collect_release_evidence.py)
to inventory first-parent integrations, associated pull requests, direct
commits, authors and changed paths in the exact baseline-to-target range. The
inventory is a routing aid, not sufficient evidence for release copy: inspect
the relevant hunks, pull-request context and tests or artifact evidence.

Include only changes consumed by the target platform artifact. Keep macOS and Windows independent. Exclude other-platform work, future work, release-note preparation itself, and internal-only changes without a meaningful user outcome. Record every integration as included or excluded with a reason; unresolved PR association or author attribution is `ACTION REQUIRED`, not a value to invent.

## Draft and verify

Read [references/format.md](references/format.md) before drafting. Translate implementation evidence into a short final-user summary followed by one-sentence change bullets. Preserve installation actions, compatibility limits, data-risk warnings, signing status and known limitations only when users need them or the user requests a separate section. Do not claim unverified functionality, security, signing, testing, availability or release completion.

Write or revise `docs/releases/v<version>.md` for macOS or `docs/releases/windows-v<version>.md` for Windows. The public GitHub Release body derives from that canonical file. Unless the user explicitly requests another section, use only the requested preamble when present, the summary, `## 변경사항`, attributed bullets and the final comparison link; do not add a release title, date, installation or limitations section by habit.

Save the collector output outside tracked source, then run the
[format validator](../../../scripts/skills/release-notes/validate_release_note.py)
with that evidence and the exact baseline and target tags. Then run the
relevant `scripts/skills/verify_release_consistency.py` mode and validate
changed links. Recheck every bullet's PR or direct-commit reference and author
against the collected evidence.

## Evidence

```text
Platform / version / target commit / artifact
Baseline tag and commit / exact comparison range
Included: PR or commit, author, source evidence -> user-facing outcome
Excluded: PR or commit, author, source evidence -> exclusion reason
Canonical release-note path
Validation: note format, attribution, comparison URL, manifest, links, deterministic checks
Verdict: READY / ACTION REQUIRED / BLOCKED
Unverified claims or missing evidence
```

Do not change milestones or pull requests, create or push a tag, upload an artifact, create or edit a public GitHub Release, submit to a store, or deploy. Publication remains a separate explicitly authorized release operation.
