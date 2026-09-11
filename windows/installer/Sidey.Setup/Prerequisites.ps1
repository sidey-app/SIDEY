# Runs in Windows PowerShell 5.1 / the OS .NET Framework, before .NET 10 exists.
function Test-SideyDotNetVersion {
    param([string[]]$Versions, [version]$MinimumVersion)
    foreach ($candidate in $Versions) {
        $parsed = $null
        if ([version]::TryParse($candidate, [ref]$parsed) -and
            $parsed.Major -eq $MinimumVersion.Major -and
            $parsed.Minor -eq $MinimumVersion.Minor -and $parsed -ge $MinimumVersion) {
            return $true
        }
    }
    return $false
}

function Test-SideyVisualCppVersion {
    param([string]$Candidate, [version]$MinimumVersion)
    $parsed = $null
    return -not [string]::IsNullOrWhiteSpace($Candidate) -and
        [version]::TryParse($Candidate.Trim().TrimStart('v'), [ref]$parsed) -and
        $parsed.Major -eq 14 -and $parsed -ge $MinimumVersion
}

function Test-SideyVisualCpp {
    param($Requirement)
    # Microsoft documents this key under Wow6432Node on x64 Windows. Opening the
    # 32-bit registry view avoids depending on the setup process architecture.
    $registry = [Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine', 'Registry32')
    $key = $null
    try {
        $key = $registry.OpenSubKey('SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64')
        if ($null -eq $key -or [int]$key.GetValue('Installed', 0) -ne 1) { return $false }
        return Test-SideyVisualCppVersion ([string]$key.GetValue('Version')) ([version]$Requirement.minimumVersion)
    }
    finally {
        if ($null -ne $key) { $key.Dispose() }
        $registry.Dispose()
    }
}

function Test-SideyDotNet {
    param($Requirement)
    # The x64 installation is registered in the 32-bit registry view on Windows.
    # Do not trust PATH (which may resolve an x86 host or a private SDK).
    $registry = [Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine', 'Registry32')
    $key = $null
    try {
        $key = $registry.OpenSubKey('SOFTWARE\dotnet\Setup\InstalledVersions\x64')
        if ($null -eq $key) { return $false }
        $location = [string]$key.GetValue('InstallLocation')
        if ([string]::IsNullOrWhiteSpace($location)) { return $false }
        $hostPath = Join-Path $location 'dotnet.exe'
        if (-not (Test-Path -LiteralPath $hostPath -PathType Leaf)) { return $false }
        $runtimes = @(& $hostPath --list-runtimes)
        if ($LASTEXITCODE -ne 0) { return $false }
        $versions = @($runtimes | ForEach-Object {
            if ($_ -match '^Microsoft\.NETCore\.App (\d+\.\d+\.\d+) \[') { $Matches[1] }
        })
        return Test-SideyDotNetVersion $versions ([version]$Requirement.minimumVersion)
    }
    finally {
        if ($null -ne $key) { $key.Dispose() }
        $registry.Dispose()
    }
}

function Test-SideyRuntimePackages {
    param([object[]]$Packages, [object[]]$Requirements)
    foreach ($required in $Requirements) {
        $matching = @($Packages | Where-Object {
            $_.PackageFamilyName -ceq $required.family -and
            [string]$_.Architecture -eq 'X64' -and
            [version]$_.Version -ge [version]$required.minimumVersion -and
            [string]$_.Status -eq 'Ok'
        })
        if ($matching.Count -eq 0) { return $false }
    }
    return $true
}

function Test-SideyWindowsAppRuntime {
    param($Requirement)
    # Query the calling user, not just staged files or another user's packages.
    $packages = @(Get-AppxPackage -PackageTypeFilter Framework, Main -ErrorAction Stop)
    return Test-SideyRuntimePackages $packages $Requirement.packages
}

function Assert-SideyMicrosoftUri {
    param([uri]$Uri)
    if ($Uri.Scheme -cne 'https' -or $Uri.Port -ne 443 -or
        $Uri.UserInfo -ne '' -or
        $Uri.DnsSafeHost -notin @('aka.ms', 'builds.dotnet.microsoft.com',
            'download.visualstudio.microsoft.com', 'download.microsoft.com')) {
        throw "Unexpected Microsoft download URL: $Uri"
    }
}

function Save-SideyMicrosoftInstaller {
    param([uri]$Uri, [string]$Destination)
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    for ($redirect = 0; $redirect -lt 10; $redirect++) {
        Assert-SideyMicrosoftUri $Uri
        $request = [Net.HttpWebRequest]::Create($Uri)
        $request.AllowAutoRedirect = $false
        $request.Timeout = 120000
        $request.ReadWriteTimeout = 120000
        $response = $request.GetResponse()
        try {
            if ([int]$response.StatusCode -in @(301, 302, 303, 307, 308)) {
                $Uri = [uri]::new($Uri, $response.Headers['Location'])
                continue
            }
            if ([int]$response.StatusCode -ne 200) { throw 'Runtime download failed.' }
            $file = [IO.File]::Create($Destination)
            try { $response.GetResponseStream().CopyTo($file) }
            finally { $file.Dispose() }
            return
        }
        finally { $response.Dispose() }
    }
    throw 'Too many Microsoft download redirects.'
}

function Test-SideyMicrosoftSignerSubject {
    param([string]$Subject)
    # Microsoft uses product-specific common names for some signed binaries
    # (for example, CN=.NET). The verified publisher organization is the
    # stable identity; do not require a particular product/common name.
    return -not [string]::IsNullOrWhiteSpace($Subject) -and
        $Subject -match '(^|,\s*)O=Microsoft Corporation(,|$)'
}

function Assert-SideyMicrosoftSignature {
    param([string]$Path)
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ($signature.Status -ne 'Valid' -or $null -eq $signature.SignerCertificate -or
        -not (Test-SideyMicrosoftSignerSubject $signature.SignerCertificate.Subject)) {
        throw 'Runtime installer does not have a valid Microsoft Corporation signature.'
    }
}

function Invoke-SideyRuntimeInstaller {
    param([string]$Path, [string]$Arguments)
    $process = Start-Process -FilePath $Path -ArgumentList $Arguments -WindowStyle Hidden -PassThru -Wait
    try { return $process.ExitCode }
    finally { $process.Dispose() }
}

function Enable-SideyRuntimeForAllUsers {
    param($Requirement)
    # The official installer skips provisioning when packages already exist and
    # can report success despite a provisioning failure. Ensure machine-wide
    # availability explicitly for NSIS, including over-the-shoulder elevation.
    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    $manager = [Windows.Management.Deployment.PackageManager, Windows.Management.Deployment, ContentType = WindowsRuntime]::new()
    $resultType = [Windows.Management.Deployment.DeploymentResult, Windows.Management.Deployment, ContentType = WindowsRuntime]
    $progressType = [Windows.Management.Deployment.DeploymentProgress, Windows.Management.Deployment, ContentType = WindowsRuntime]
    $asTask = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
        $_.Name -eq 'AsTask' -and $_.GetGenericArguments().Count -eq 2 -and $_.GetParameters().Count -eq 1
    } | Select-Object -First 1
    foreach ($package in $Requirement.packages) {
        # Frameworks are registered through the provisioned Main/DDLM package's
        # dependencies; Windows does not support provisioning frameworks directly.
        if ($package.family -like 'Microsoft.WindowsAppRuntime.*') { continue }
        $operation = $manager.ProvisionPackageForAllUsersAsync($package.family)
        $task = $asTask.MakeGenericMethod($resultType, $progressType).Invoke($null, @($operation))
        $result = $task.GetAwaiter().GetResult()
        if ($result.ExtendedErrorCode -and $result.ExtendedErrorCode.HResult -ne 0) {
            throw "Windows App Runtime provisioning failed: $($result.ErrorText)"
        }
    }
}

function Install-SideyPrerequisites {
    param($Configuration, [string]$DownloadDirectory, [switch]$CheckOnly, [switch]$ProvisionAllUsers)
    $requirements = @(
        @{ Name = 'Visual C++ v14 x64 Redistributable'; Config = $Configuration.visualCpp;
            Test = 'Test-SideyVisualCpp'; File = 'vc_redist.x64.exe'; Arguments = '/install /quiet /norestart' },
        @{ Name = '.NET 10 x64 Runtime'; Config = $Configuration.dotnet;
            Test = 'Test-SideyDotNet'; File = 'dotnet-runtime-x64.exe'; Arguments = '/install /quiet /norestart' },
        @{ Name = 'Windows App Runtime x64'; Config = $Configuration.windowsAppRuntime;
            Test = 'Test-SideyWindowsAppRuntime'; File = 'windowsappruntimeinstall-x64.exe'; Arguments = '--quiet' }
    )
    foreach ($requirement in $requirements) {
        if (& $requirement.Test $requirement.Config) {
            Write-Host "$($requirement.Name): available"
            continue
        }
        if ($CheckOnly) { throw "$($requirement.Name): missing" }
        Write-Host "$($requirement.Name): downloading from Microsoft"
        $download = Join-Path $DownloadDirectory $requirement.File
        try {
            Save-SideyMicrosoftInstaller $requirement.Config.url $download
            Assert-SideyMicrosoftSignature $download
            $code = Invoke-SideyRuntimeInstaller $download $requirement.Arguments
            # Never restart the machine automatically or remove the old SIDEY yet.
            if ($code -in @(3010, 1641)) { return 3010 }
            if ($code -ne 0) { throw "$($requirement.Name) installation failed (exit=$code)." }
            if (-not (& $requirement.Test $requirement.Config)) {
                throw "$($requirement.Name) is still unavailable after installation."
            }
        }
        finally {
            if (Test-Path -LiteralPath $download -PathType Leaf) {
                Remove-Item -LiteralPath $download -Force
            }
        }
    }
    if ($ProvisionAllUsers -and -not $CheckOnly) {
        Enable-SideyRuntimeForAllUsers $Configuration.windowsAppRuntime
    }
    return 0
}

function Remove-SideyPrivateRuntime {
    param([string]$InstallDirectory)
    $installRoot = [IO.Path]::GetFullPath($InstallDirectory).TrimEnd('\')
    if ($installRoot -eq [IO.Path]::GetPathRoot($installRoot).TrimEnd('\')) {
        throw 'The installation directory cannot be a drive root.'
    }
    # Reject junctions/symlinks in both ancestors and the entire private tree
    # before deleting anything; never follow a link into a shared runtime.
    $ancestor = [IO.DirectoryInfo]::new($installRoot)
    while ($null -ne $ancestor) {
        if ($ancestor.Exists -and ($ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw 'The installation path contains a reparse point.'
        }
        $ancestor = $ancestor.Parent
    }
    $runtime = Join-Path $installRoot 'Runtime'
    if (-not (Test-Path -LiteralPath $runtime)) { return }
    $pending = [Collections.Generic.Queue[string]]::new()
    $pending.Enqueue($runtime)
    $directories = [Collections.Generic.List[string]]::new()
    $files = [Collections.Generic.List[string]]::new()
    while ($pending.Count -gt 0) {
        $directory = $pending.Dequeue()
        $item = Get-Item -LiteralPath $directory -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw 'The private Runtime tree contains a reparse point.'
        }
        $directories.Add($directory)
        foreach ($child in Get-ChildItem -LiteralPath $directory -Force) {
            if ($child.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw 'The private Runtime tree contains a reparse point.'
            }
            if ($child.PSIsContainer) { $pending.Enqueue($child.FullName) }
            else { $files.Add($child.FullName) }
        }
    }
    foreach ($file in $files) { Remove-Item -LiteralPath $file -Force }
    for ($index = $directories.Count - 1; $index -ge 0; $index--) {
        Remove-Item -LiteralPath $directories[$index] -Force
    }
}
