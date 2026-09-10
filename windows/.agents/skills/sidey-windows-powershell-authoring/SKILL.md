---
name: sidey-windows-powershell-authoring
description: Create, revise, or review PowerShell scripts and modules for SIDEY Windows. Use for .ps1, .psm1, and .psd1 files under windows/** or scripts/windows/**, and for PowerShell steps in Windows-only workflows. Apply repository compatibility, PowerShell-native style, parameter, output, error-handling, safety, and validation rules. Do not use for macOS shell scripts, C#-only work, or shared website automation.
---

# SIDEY Windows PowerShell Authoring

Write PowerShell that behaves like a PowerShell tool, remains safe in unattended Windows builds, and preserves SIDEY's existing script contracts. The user's explicit instructions take precedence over this skill.

This skill adapts [Doug Finke's PowerShell coding standards](https://gist.github.com/dougbw/7d5949eaa637ec2509be72226d44c267) and Microsoft's [Strongly Encouraged Development Guidelines](https://learn.microsoft.com/en-us/powershell/scripting/developer/cmdlet/strongly-encouraged-development-guidelines?view=powershell-7.6). The Microsoft page primarily addresses compiled cmdlets; apply its parameter, pipeline, path, output, and feedback guidance to reusable advanced functions when it fits their role. Do not force interactive-cmdlet features onto build and CI entrypoints when they would change the script contract.

## Establish the contract

1. Resolve the repository root with `git rev-parse --show-toplevel` and use it as the working directory for repository-relative paths and commands. This skill is normally discovered while Codex is started in `windows` or one of its descendants.
2. Read the repository-root `AGENTS.md`, `docs/DECISIONS.md`, and `docs/PRODUCT_SPEC.md`; confirmed decisions win. Read the target script, every direct caller, and neighboring Windows scripts before editing.
3. Verify a clean or task-owned worktree on a `windows/*` branch. Limit new edits to Windows-specific paths such as `windows/**`, `scripts/windows/**`, and Windows-only workflow code. Do not edit macOS implementation files or mix new shared-file changes into the branch.
4. Identify the script's supported PowerShell editions, inputs, outputs, exit behavior, filesystem or system side effects, and CI-consumed text. Preserve these contracts unless the task explicitly changes them.
5. Keep Windows PowerShell 5.1 compatibility for installer, prerequisite, launcher, and setup paths unless repository evidence sets a newer minimum. Use PowerShell 7-only syntax or behavior only when the caller guarantees it; declare a real minimum with `#Requires -Version`.

## Use consistent PowerShell style

- Use complete cmdlet and parameter names in committed scripts. Do not use aliases or symbolic aliases such as `%`, `?`, or `!`.
- Name reusable functions with an approved `Verb-SingularNoun` and a specific noun. Use PascalCase for function and parameter names. Use the same parameter name and type for the same concept across related functions.
- Indent with four spaces. Put one statement on each line, omit semicolon line endings, and format multi-item array literals and hashtables with one item or property per line. Split long pipelines, conditions, and invocations across lines at readable boundaries.
- Use `[CmdletBinding()]` and an explicit `param` block for scripts and reusable functions. Omit it from a dot-sourced library only for a verified compatibility reason. Type parameters with the narrowest useful standard .NET type, mark required inputs with `[Parameter(Mandatory = $true)]`, and add `ValidateSet`, `ValidateRange`, `ValidatePattern`, or `ValidateScript` when invalid values can be rejected at the boundary.
- Use `[switch]` for an optional true/false choice. Use singular parameter names unless the input must always contain multiple values. Prefer standard names such as `Path`, `LiteralPath`, `Name`, `InputObject`, `Force`, and `PassThru` with their conventional meanings.
- Use `Path` when wildcard and provider semantics are intentional. Use `LiteralPath` and the `-LiteralPath` cmdlet parameter for literal, generated, or user-supplied filesystem paths.
- Declare only real dependencies with `#Requires`. Do not add a module, elevation, edition, or version requirement that callers do not need.
- Put a short comment on its own line immediately before non-obvious logic. Explain the reason or constraint. Add comment-based help with a synopsis, parameter descriptions, and useful examples to reusable public scripts and functions; do not bury small private helpers in boilerplate.
- If a module grows beyond a small cohesive file, keep its manifest and root module together, place public and private functions in clearly named folders, and keep one exported function per file with its focused Pester tests.

## Preserve pipeline and output behavior

- Emit useful objects to the success stream so callers can filter, sort, inspect, or pipe them. Do not mix progress or status text into data output.
- Use `Write-Verbose` for optional operational detail, `Write-Debug` for diagnostic detail, `Write-Warning` for recoverable risk, and `Write-Error` or `throw` for failures according to whether the operation can continue.
- Avoid `Write-Host` for reusable data output. It is acceptable for intentional human-facing console messages or stable `Key=Value` lines already consumed as a SIDEY build or CI protocol; treat those strings as compatibility-sensitive output.
- Use `Write-Progress` only for a long foreground operation where useful progress can be measured. Do not add noisy per-item logging to fast loops.
- For reusable commands, accept pipeline input and return records as they become available when that makes composition materially better. Do not bolt pipeline semantics onto a task-runner script with one fixed operation.
- When a state-changing reusable function normally emits nothing, add `-PassThru` only if callers need the resulting object. Keep the default output quiet and predictable.
- Compare user-facing identifiers case-insensitively while preserving their original case, unless the external protocol or file format explicitly requires ordinal case-sensitive comparison.

## Handle changes, failures, and external tools safely

- Prefer PowerShell cmdlets for filesystem, process, service, registry, and web operations. Use a required external tool such as `dotnet`, `git`, `csc.exe`, or `makensis.exe` directly; check `$LASTEXITCODE` in Windows PowerShell 5.1 paths and throw a specific failure when it is nonzero.
- Use .NET APIs when they provide behavior PowerShell 5.1 lacks or when exact encoding, cryptography, archive handling, path validation, native interop, or disposal requires them. Add a comment when the reason is not evident from the code.
- Never construct executable command text from input or use `Invoke-Expression`. Quote paths, pass arguments as arguments, and use splatting for long or conditional parameter lists.
- Use `SupportsShouldProcess` and `$PSCmdlet.ShouldProcess()` for reusable commands that alter user or system state, such as install, uninstall, registry, service, process, or destructive filesystem operations. Do not add confirmation prompts to deterministic CI scripts that write only to an explicitly requested build-output directory.
- Before a recursive delete or move, resolve the absolute target and verify that it is inside the intended task-owned root. Use `-LiteralPath`, and keep discovery and mutation in the same PowerShell process.
- Use `try`/`finally` to dispose native or managed resources and to restore locations, environment variables, temporary files, or other process state. Pair `Push-Location` with `Pop-Location` in `finally`.
- At script entrypoints, use terminating behavior such as `$ErrorActionPreference = 'Stop'` when partial continuation would produce an invalid artifact. Do not change preference variables in a dot-sourced library without restoring them.
- Do not repurpose common automatic or environment variables such as `$HOME` or `$PROFILE`. Choose a task-specific variable name.

## Validate proportionately

1. Parse every changed PowerShell file without executing it:

```powershell
$tokens = $null
$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile(
    $Path,
    [ref]$tokens,
    [ref]$parseErrors
) | Out-Null
if ($parseErrors.Count -gt 0) {
    $parseErrors | ForEach-Object { Write-Error $_ }
}
```

2. Run PSScriptAnalyzer with the repository settings when the module and configuration are already available. Do not install tooling or change machine policy merely to lint a change.
3. Add or revise Pester tests for reusable PowerShell logic when they can exercise meaningful success, failure, cleanup, and idempotency behavior. Do not test a script by matching its source text.
4. Run the narrowest safe script check first. For prerequisite, publish-layout, packaging, startup, or distribution changes, use the relevant checks under `scripts/windows/`. Run `scripts/windows/Test-WindowsBuild.ps1` only when its publish, GUI-startup, and possible prerequisite-install effects are within the user's authorized scope.
5. When Windows PowerShell 5.1 compatibility matters and PowerShell 7 is also a supported caller, parse and exercise the script in both available hosts. Report a missing host as a validation gap rather than silently changing the support target.
6. Run `git diff --check`, inspect every changed path against the branch base, and confirm no macOS or newly mixed shared paths entered the change.

Report the compatibility target, stable output or side-effect contracts preserved, validation run, results, and any remaining host-, installer-, or elevation-dependent checks.
