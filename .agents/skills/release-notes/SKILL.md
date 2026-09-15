---
name: release-notes
description: Research, draft, and validate the canonical user-facing release note for one SIDEY macOS or Windows release from the exact shipped commit range, with inclusion and exclusion evidence. Use for docs/releases/** or GitHub Release body preparation; do not use for README, developer documentation, version selection, or release publication.
---

# Release Notes

Produce the canonical release body for one platform artifact. General documentation and README
rules remain in `docs/AGENTS.md`; this skill owns the release-specific investigation and copy.

## Inputs

Establish the platform, target version, release date, target commit, and intended artifact.
Use the matching `release/*.json` as release metadata, and identify the previous published
regular release for that platform. A staged target manifest is not itself evidence that its tag
has already shipped. Stop with `BLOCKED` if the target or comparison baseline is ambiguous.

## Draft and verify

1. Collect the exact commit and PR range from the previous public tag to the target. Inspect
   changed paths and relevant hunks, plus tests or artifact evidence supporting user-facing
   claims.
2. Include only changes actually consumed by the target platform artifact. Keep macOS and
   Windows independent. Exclude work for another platform, future work, internal-only changes
   without a meaningful user outcome, and changes not present in the target.
3. Translate implementation evidence into concise user outcomes. Preserve installation actions,
   compatibility limits, data-risk warnings, signing status, and known limitations when users
   need them. Do not claim unverified functionality, security, signing, testing, availability,
   or release completion.
4. Write or revise the canonical file: `docs/releases/v<version>.md` for macOS or
   `docs/releases/windows-v<version>.md` for Windows. The public GitHub Release body must derive
   from that file rather than a separately maintained draft.
5. Verify heading, version, build when applicable, date, artifact name, installation text,
   warnings, and comparison link against the selected manifest and exact range. Run the
   relevant `scripts/verify_release_consistency.py` check and validate changed links.

## Evidence

```text
Platform / version / target commit / artifact
Baseline tag and commit / exact comparison range
Included: source evidence -> user-facing outcome
Excluded: source evidence -> exclusion reason
Canonical release-note path
Validation: manifest, version/build/date, links, deterministic checks
Verdict: READY / ACTION REQUIRED / BLOCKED
Unverified claims or missing evidence
```

Do not create or push a tag, upload an artifact, create or edit a public GitHub Release, submit
to a store, or deploy. Publication remains a separate explicitly authorized release operation.
