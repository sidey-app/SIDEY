---
name: version-audit
description: Assess whether a target SIDEY macOS or Windows artifact needs a version bump from its actual release diff, recommend or apply the minimum valid version/build, and report consistency evidence. Use for version planning, candidate or stable release preparation, and release-version audits; do not use for ordinary source edits, release-note writing, or release publication.
---

# Version Audit

Determine the version implied by the shipped artifact, then let repository tooling prove that
the chosen metadata agrees. Treat macOS and Windows as independent release lines.

## Inputs

Establish the target platform and commit, the intended artifact or distribution, and whether
the request is advisory or asks to apply metadata changes. Record any user-selected version
class, but do not accept one below the evidence-based minimum.

Start with `release/macos.json` or `release/windows.json`, then confirm whether its matching tag
(`v<version>` or `windows-v<version>`) is already a published regular release. If the manifest is
intentionally staged ahead of publication, identify the previous published platform release as
the comparison baseline and label the manifest state as pending. If the baseline, target,
artifact impact, or tag provenance cannot be established, return `BLOCKED` with the missing
evidence.

## Audit

1. Inspect commits, changed paths, and relevant hunks from the platform's public tag through
   the target commit. Commit titles alone are insufficient.
2. Decide whether the distributed platform artifact or a packaging input it consumes changes.
   A shared change counts only for a platform that consumes it. Return `NONE` for web-, server-,
   documentation-, or contributor-only changes that do not alter an app artifact.
3. Classify the highest impact present:
   - `PATCH`: fixes and compatible UI, accessibility, performance, stability, security,
     packaging, or internal improvements;
   - `MINOR`: backward-compatible user features, content, products, or meaningful behavior or
     contract changes;
   - `MAJOR`: account, persisted-data, protocol, installation, or supported-OS incompatibility
     that requires user intervention.
4. Propose the exact next version for the selected class. Reject malformed, reused, decreasing,
   skipped-within-class, or under-classified versions.
5. For macOS, keep equivalent Direct and App Store artifacts on the same marketing version.
   Before proposing a distributable build, determine the greatest build already consumed by
   either channel and add one. Repository metadata cannot prove external upload history: label
   the build `PROVISIONAL` and block upload readiness when that history is unavailable.
6. Read `scripts/verify_release_consistency.py` for the current mirrors, then run the mode that
   matches the state being audited. Windows publication uses the strict platform check. macOS
   pre-publication intentionally permits an older signed appcast; the appcast becomes strict
   after its verified post-release update. Candidate allowances validate only their named staged
   states and do not waive other inconsistencies.

When the user asks to apply the decision, change only the metadata in scope and rerun the
affected deterministic checks. An audit does not by itself authorize edits.

## Evidence

Return this structure, adapting fields only when a platform does not have them:

```text
Platform / target commit / artifact
Baseline: manifest version, build, tag, tag commit
Comparison: exact range, artifact affected YES/NO, consumed shared changes
Impact: PATCH, MINOR, and MAJOR evidence
Decision: required bump, proposed version, proposed build
Build history: VERIFIED / PROVISIONAL / BLOCKED
Consistency: source, manifest, updater or appcast, release note, public metadata, tag uniqueness
Verdict: READY / ACTION REQUIRED / BLOCKED
Missing or conflicting evidence
```

Do not create or push tags, build or upload release artifacts, publish a GitHub Release, submit
to a store, or deploy. Those operations require separate explicit authorization and remain
owned by the repository's release automation.
