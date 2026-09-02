[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string[]]$Path,

    [string]$CertificateOutPath,

    [string]$CertificatePfxPath,

    [string]$CertificatePassword
)

$ErrorActionPreference = 'Stop'
$subject = 'CN=SIDEY'
$friendlyName = 'SIDEY Self-Signed Code Signing'
$minimumExpiry = (Get-Date).AddDays(30)
$certificate = $null
$resolvedPfxPath = $null
if (-not [string]::IsNullOrWhiteSpace($CertificatePfxPath)) {
    if ([string]::IsNullOrWhiteSpace($CertificatePassword)) {
        throw 'CertificatePassword is required when CertificatePfxPath is used.'
    }

    $resolvedPfxPath = [System.IO.Path]::GetFullPath($CertificatePfxPath)
    if (Test-Path -LiteralPath $resolvedPfxPath -PathType Leaf) {
        $pfxBytes = [System.IO.File]::ReadAllBytes($resolvedPfxPath)
        $certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
            $pfxBytes,
            $CertificatePassword,
            [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet)
    }
}

if ($null -eq $certificate) {
    $certificate = Get-ChildItem -Path Cert:\CurrentUser\My -CodeSigningCert |
        Where-Object {
            $_.Subject -eq $subject `
                -and $_.HasPrivateKey `
                -and $_.NotAfter -gt $minimumExpiry
        } |
        Sort-Object -Property NotAfter -Descending |
        Select-Object -First 1
}

if ($null -eq $certificate) {
    try {
        $certificate = New-SelfSignedCertificate `
            -Type CodeSigningCert `
            -Subject $subject `
            -FriendlyName $friendlyName `
            -CertStoreLocation Cert:\CurrentUser\My `
            -KeyAlgorithm RSA `
            -KeyLength 3072 `
            -HashAlgorithm SHA256 `
            -NotAfter (Get-Date).AddYears(3)
    }
    catch {
        $rsa = [System.Security.Cryptography.RSACng]::new(3072)
        $request = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
            $subject,
            $rsa,
            [System.Security.Cryptography.HashAlgorithmName]::SHA256,
            [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
        $request.CertificateExtensions.Add(
            [System.Security.Cryptography.X509Certificates.X509KeyUsageExtension]::new(
                [System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]::DigitalSignature,
                $true))
        $usages = [System.Security.Cryptography.OidCollection]::new()
        [void]$usages.Add([System.Security.Cryptography.Oid]::new('1.3.6.1.5.5.7.3.3'))
        $request.CertificateExtensions.Add(
            [System.Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]::new(
                $usages,
                $false))
        $created = $request.CreateSelfSigned(
            [DateTimeOffset]::Now.AddMinutes(-5),
            [DateTimeOffset]::Now.AddYears(3))
        $certificate = $created
    }
}

if ($null -ne $resolvedPfxPath `
    -and -not (Test-Path -LiteralPath $resolvedPfxPath -PathType Leaf)) {
    [System.IO.Directory]::CreateDirectory(
        [System.IO.Path]::GetDirectoryName($resolvedPfxPath)) | Out-Null
    $pfxBytes = $certificate.Export(
        [System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx,
        $CertificatePassword)
    [System.IO.File]::WriteAllBytes($resolvedPfxPath, $pfxBytes)
}

foreach ($candidate in $Path) {
    $resolvedPath = (Resolve-Path -LiteralPath $candidate).Path
    $signature = Set-AuthenticodeSignature `
        -LiteralPath $resolvedPath `
        -Certificate $certificate `
        -HashAlgorithm SHA256
    if ($null -eq $signature.SignerCertificate `
        -or $signature.SignerCertificate.Thumbprint -ne $certificate.Thumbprint) {
        throw "SIDEY Authenticode signature was not written: $resolvedPath"
    }

    Write-Host "Signed=$resolvedPath"
}

if (-not [string]::IsNullOrWhiteSpace($CertificateOutPath)) {
    $certificatePath = [System.IO.Path]::GetFullPath($CertificateOutPath)
    [System.IO.Directory]::CreateDirectory(
        [System.IO.Path]::GetDirectoryName($certificatePath)) | Out-Null
    Export-Certificate `
        -Cert $certificate `
        -FilePath $certificatePath `
        -Type CERT `
        -Force | Out-Null
    Write-Host "Certificate=$certificatePath"
}

Write-Host "Signer=$($certificate.Subject)"
Write-Host "Thumbprint=$($certificate.Thumbprint)"
