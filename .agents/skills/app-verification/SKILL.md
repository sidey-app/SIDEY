---
name: app-verification
description: Verify an integrated SIDEY macOS or Windows app/runtime against exact current-main source and runtime provenance, then report PASS, FAIL, or BLOCKED evidence. Use after app-affecting integration or when explicitly asked to open, smoke-test, or review the current app; do not use for ordinary unit tests, source review, release packaging, or publication.
---

# App Verification

Decide what the available runtime evidence actually proves. Repository automation owns source
freshness, builds, task state, and provenance checks; this skill selects and interprets that
evidence without reimplementing it.

## Inputs

Identify the platform, exact target commit, distribution or scheme, integrated task when
applicable, and the behavior the user expects to observe. Distinguish a current-main review
from an explicitly requested preview.

## macOS

Use the verified opener exposed by `scripts/skills/workflow.py`. For an already integrated task awaiting
app review, run `python3 scripts/skills/workflow.py open --task <task> --scheme <scheme>`. Without a task,
its plain `open` path reviews latest main. Use preview or offline modes only when explicitly
requested, and label offline freshness as unverified.

Collect the opener's actual source, remote-main SHA, project, scheme, app and executable paths,
build ID, source commit and input hash, configuration, PID, and ready-window result. Opening a
proven executable proves startup readiness; it does not prove visual or functional behavior
that was not separately observed.

## Windows

For an already integrated task awaiting app review, provide the successful current-`main` push
run to `python3 scripts/skills/workflow.py finish <task> --windows-run <run-id>`. The evidence must
identify the exact head SHA, `.github/workflows/integration.yml` run URL, successful `windows`
job, and successful `Run Windows app smoke` step. That smoke proves the published launcher/host
startup and its instrumented preview probes; report it as GitHub Actions Windows verification,
not local or manual Windows execution.

Local Windows runtime, installer, elevation, or prerequisite checks are supplemental and may
change machine state. Run them only when explicitly in scope and never substitute them for the
required current-main integration provenance.

## Verdict

```text
Platform / target commit / distribution or target
Environment / artifact or executable
Source: freshness, commit, input hash
Build: build ID, target, configuration
Runtime: command or CI run, process/startup/window evidence
Requested observations: PASS / FAIL / NOT RUN with method
Limitations and reproduction evidence
Verdict: PASS / FAIL / BLOCKED
```

Use `FAIL` when an executed required check disproves readiness. Use `BLOCKED` when required
provenance, environment, current-main run, or observable evidence is unavailable. A successful
build or test suite alone is not runtime verification, and unobserved behavior is `NOT RUN`.

This skill does not authorize release packaging, signing, notarization, installer execution,
tags, uploads, publication, store submission, or deployment.
