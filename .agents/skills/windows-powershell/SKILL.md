---
name: windows-powershell
description: Create or revise Windows-owned PowerShell under windows, scripts/windows, or Windows workflow logic. Preserve Windows PowerShell 5.1 and PowerShell 7 caller contracts, streams, native exit handling, safe side effects, and repository validation routes. Do not use for review-only requests, merely running unchanged scripts, prose-only work, or PowerShell outside Windows-owned behavior.
---

# Windows PowerShell

Write PowerShell that remains compatible with its real callers and safe in unattended Windows builds.

## Establish the contract

1. Read the repository-root `AGENTS.md` and `windows/AGENTS.md`. Determine branch and path ownership from those instructions and the repository workflow; using this skill does not make a shared workflow file Windows-owned.
2. Read the target script, direct callers, neighboring scripts, and the relevant CI steps before editing. Include `.ps1`, `.psm1`, `.psd1`, and embedded PowerShell in Windows workflow logic.
3. Record supported hosts, parameters, output streams, exit behavior, filesystem and process effects, machine-state effects, and stable text consumed by CI or another script.
4. Preserve Windows PowerShell 5.1 where `powershell.exe`, `#requires -Version 5.1`, MSBuild, or installer-build callers require it. Preserve PowerShell 7 behavior where workflows invoke a script under `pwsh`. A script reached by both paths must work in both hosts.
5. Do not add a version, module, edition, or elevation requirement unless every caller supports and needs it.

## Write compatible PowerShell

- Use complete cmdlet and parameter names, approved `Verb-SingularNoun` names for reusable functions, PascalCase parameters, four-space indentation, and one statement per line.
- Give entry scripts and reusable functions `[CmdletBinding()]` and an explicit `param` block. A verified dot-sourced library may omit them to preserve its loading contract.
- Type inputs narrowly and reject invalid values at the boundary with appropriate validation attributes. Use `[switch]` for optional Boolean choices.
- Use `Path` only when wildcard and provider semantics are intentional. Use `LiteralPath` and `-LiteralPath` for generated or user-supplied filesystem locations.
- Preserve surrounding style in touched code. Do not reformat unrelated script sections merely to apply this skill.

## Preserve streams and native exit behavior

- Keep structured data on the success stream. Use `Write-Verbose` for optional operational detail, `Write-Debug` for diagnostics, `Write-Warning` for recoverable risk, and `throw` or `Write-Error` for failures according to whether execution can continue.
- Do not replace stable human-facing or `Key=Value` `Write-Host` output without checking its callers. Treat CI-consumed text as a compatibility contract.
- Invoke native tools with arguments, never constructed command text or `Invoke-Expression`. Check `$LASTEXITCODE` when the active host does not reliably turn a native failure into a terminating error. Prefer the repository's `Invoke-SideyNativeCommand` helper where its contract fits.
- Keep task-runner output quiet and predictable. Add pipeline input or `PassThru` only when callers benefit from it.

## Bound side effects

- Set terminating error behavior at entrypoints when partial continuation could create an invalid artifact. Do not leave preference or environment changes behind after dot-sourcing or execution.
- Resolve deletion and move targets to absolute paths, prove they are inside the intended temporary or explicit output root, and use `-LiteralPath`. Keep discovery and mutation in the same PowerShell process.
- Use `try`/`finally` for processes, managed resources, locations, environment variables, and temporary files. Pair `Push-Location` with `Pop-Location`.
- Use `SupportsShouldProcess` and `$PSCmdlet.ShouldProcess()` for reusable commands that alter user or system state. Do not add interactive confirmation to deterministic CI scripts that write only to an explicitly requested build-output directory.
- Inspect a check before running it. Installation, prerequisite provisioning, elevation, GUI launch, release access, network download, or machine-state changes require authorization appropriate to the task.
- Preserve the product boundary that shipped Setup uses compiled helpers rather than PowerShell. Repository build and verification scripts are a separate execution environment.

## Validate with repository routes

Parse every changed PowerShell file without executing it in each supported host that is available. Make parse failures terminating:

```powershell
$tokens = $null
$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile(
    $changedScriptPath,
    [ref]$tokens,
    [ref]$parseErrors
) | Out-Null
if ($parseErrors.Count -gt 0) {
    throw (($parseErrors | ForEach-Object Message) -join [Environment]::NewLine)
}
```

Then use the narrowest maintained route that covers the changed contract:

- For `scripts/windows/Sidey.PowerShell.psm1`, run `powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File scripts/windows/tests/Test-PowerShellSupport.ps1`.
- For prerequisite detection, error mapping, or migration cleanup, run `powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File scripts/windows/tests/Test-RuntimePrerequisites.ps1`.
- For an existing publish tree, run `scripts/windows/Test-FrameworkDependentPublish.ps1 -PublishDirectory <path>` and `scripts/windows/tests/Test-FrameworkPublishGuard.ps1 -PublishDirectory <path>`. These checks also require current restored project assets.
- For startup behavior, use `windows/installer/Sidey.Setup/SetupRuntime.ps1` and `scripts/windows/Test-PublishedApplication.ps1 -PublishDirectory <path>` only when starting and stopping actual SIDEY processes is in scope.
- For installer or helper-generation changes, run `scripts/windows/New-WindowsInstaller.ps1` with an explicit publish and output directory. It requires NSIS and exercises helper reproducibility, install transactions, prerequisite behavior, and the ban on PowerShell in the shipped installer runtime.
- Treat `scripts/windows/Test-WindowsBuild.ps1` as an extended machine-level route: it restores, builds, tests, publishes, may install missing prerequisites, and starts the application. Do not use it as the default local check.
- Treat update-design, installer-UI, and release verification scripts as manual or authorized routes because they can start UI, change prerequisites, or use the network.

Run the non-installing solution checks from `windows/AGENTS.md` when the change can affect the application. Finish with `git diff --check` and inspect every changed path against the branch base. Report the caller and compatibility contracts preserved, files changed, commands and results, and any missing Windows PowerShell 5.1, PowerShell 7, installer, GUI, elevation, or machine-level evidence.
