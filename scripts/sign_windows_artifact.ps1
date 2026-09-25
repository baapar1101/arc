# Sign Windows release artifacts (EXE/DLL/MSI) with an Authenticode certificate.
#
# Certificate sources (first match wins):
#   -PfxPath / $env:WIN_CODESIGN_PFX / $env:HESABIX_WIN_CODESIGN_PFX
#   -Thumbprint / $env:WIN_CODESIGN_THUMBPRINT
#   -SubjectContains / $env:WIN_CODESIGN_SUBJECT (certificate store lookup)
#
# Password:
#   -PfxPassword / $env:WIN_CODESIGN_PASSWORD / $env:HESABIX_WIN_CODESIGN_PASSWORD
#
# Examples:
#   .\scripts\sign_windows_artifact.ps1 -Path installer\windows\dist\hesabix-windows.1.2.3.msi
#   $env:WIN_CODESIGN_PFX='C:\secrets\hesabix.pfx'; $env:WIN_CODESIGN_PASSWORD='...'
#   .\scripts\sign_windows_artifact.ps1 -Path build\...\hesabix_ui.exe -Verify

param(
    [Parameter(Mandatory = $true)]
    [string[]]$Path,
    [string]$PfxPath = "",
    [string]$PfxPassword = "",
    [string]$Thumbprint = "",
    [string]$SubjectContains = "",
    [string]$TimestampUrl = "",
    [string]$Description = "Hesabix",
    [string]$HashAlgorithm = "SHA256",
    [switch]$Verify,
    [switch]$DryRun,
    [switch]$Help
)

$ErrorActionPreference = "Stop"

function Write-Usage {
    Write-Host @"
Usage: .\scripts\sign_windows_artifact.ps1 -Path <file|folder> [-Path <more> ...] [options]

Options:
  -PfxPath PATH           PFX certificate file
  -PfxPassword TEXT       PFX password (or env WIN_CODESIGN_PASSWORD)
  -Thumbprint HEX         Certificate thumbprint from Windows store
  -SubjectContains TEXT   Find code-signing cert in store by subject substring
  -TimestampUrl URL       RFC3161 timestamp server (default: DigiCert)
  -Description TEXT       Signature description (default: Hesabix)
  -HashAlgorithm ALG      SHA256 (default) or SHA1
  -Verify                 Fail if signature is missing or not Valid
  -DryRun                 Print actions only
  -Help                   Show help

Environment:
  WIN_CODESIGN_PFX / HESABIX_WIN_CODESIGN_PFX
  WIN_CODESIGN_PASSWORD / HESABIX_WIN_CODESIGN_PASSWORD
  WIN_CODESIGN_THUMBPRINT
  WIN_CODESIGN_SUBJECT
  WIN_CODESIGN_TIMESTAMP_URL
"@
}

if ($Help) {
    Write-Usage
    exit 0
}

function Resolve-FirstNonEmpty {
    param([string[]]$Values)
    foreach ($v in $Values) {
        if ($v -and $v.Trim()) { return $v.Trim() }
    }
    return ""
}

function Find-SignToolExe {
    $cmd = Get-Command signtool.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $roots = @(
        "${env:ProgramFiles(x86)}\Windows Kits\10\bin",
        "${env:ProgramFiles}\Windows Kits\10\bin"
    )
    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        $found = Get-ChildItem -Path $root -Recurse -Filter signtool.exe -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending |
            Select-Object -First 1
        if ($found) { return $found.FullName }
    }
    return $null
}

function Get-CodeSignCertificate {
    param(
        [string]$Pfx,
        [string]$Password,
        [string]$Thumb,
        [string]$Subject
    )

    if ($Pfx) {
        if (-not (Test-Path -LiteralPath $Pfx)) {
            throw "PFX not found: $Pfx"
        }
        if (-not $Password) {
            throw "PFX password required for $Pfx (set WIN_CODESIGN_PASSWORD or -PfxPassword)"
        }
        $secure = ConvertTo-SecureString $Password -AsPlainText -Force
        return New-Object System.Security.Cryptography.X509Certificates.X509Certificate2(
            $Pfx, $secure, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable
        )
    }

    if ($Thumb) {
        $stores = @(
            "Cert:\CurrentUser\My",
            "Cert:\LocalMachine\My"
        )
        foreach ($storePath in $stores) {
            $cert = Get-ChildItem -Path $storePath -CodeSigningCert -ErrorAction SilentlyContinue |
                Where-Object { $_.Thumbprint -eq $Thumb } |
                Select-Object -First 1
            if ($cert) { return $cert }
        }
        throw "Code-signing certificate not found for thumbprint: $Thumb"
    }

    if ($Subject) {
        $stores = @(
            "Cert:\CurrentUser\My",
            "Cert:\LocalMachine\My"
        )
        foreach ($storePath in $stores) {
            $cert = Get-ChildItem -Path $storePath -CodeSigningCert -ErrorAction SilentlyContinue |
                Where-Object { $_.Subject -like "*$Subject*" } |
                Sort-Object NotAfter -Descending |
                Select-Object -First 1
            if ($cert) { return $cert }
        }
        throw "Code-signing certificate not found in store for subject containing: $Subject"
    }

    return $null
}

function Expand-SignTargets {
    param([string[]]$Inputs)
    $targets = New-Object System.Collections.Generic.List[string]
    foreach ($item in $Inputs) {
        if (-not $item) { continue }
        $resolved = $item
        if (-not [System.IO.Path]::IsPathRooted($resolved)) {
            $resolved = Join-Path (Get-Location) $resolved
        }
        if (-not (Test-Path -LiteralPath $resolved)) {
            throw "Path not found: $item"
        }
        if ((Get-Item -LiteralPath $resolved).PSIsContainer) {
            foreach ($ext in @("*.exe", "*.dll", "*.msi", "*.msp", "*.cab")) {
                Get-ChildItem -LiteralPath $resolved -Recurse -File -Filter $ext -ErrorAction SilentlyContinue |
                    ForEach-Object { $targets.Add($_.FullName) }
            }
        } else {
            $targets.Add((Resolve-Path -LiteralPath $resolved).Path)
        }
    }
    return @($targets | Select-Object -Unique)
}

function Invoke-SignToolSign {
    param(
        [string]$SignTool,
        [string]$Target,
        [string]$Pfx,
        [string]$Password,
        [string]$Timestamp,
        [string]$Desc,
        [string]$HashAlg
    )
    $args = @(
        "sign",
        "/f", $Pfx,
        "/p", $Password,
        "/fd", $HashAlg,
        "/tr", $Timestamp,
        "/td", $HashAlg,
        "/d", $Desc,
        "/v",
        $Target
    )
    Write-Host "[sign] signtool $($args -join ' ')" -ForegroundColor DarkGray
    if ($DryRun) { return 0 }
    $p = Start-Process -FilePath $SignTool -ArgumentList $args -Wait -PassThru -NoNewWindow
    return $p.ExitCode
}

function Invoke-AuthenticodeSign {
    param(
        [string]$Target,
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,
        [string]$Timestamp,
        [string]$HashAlg
    )
    Write-Host "[sign] Set-AuthenticodeSignature $Target" -ForegroundColor DarkGray
    if ($DryRun) { return $true }
    $sig = Set-AuthenticodeSignature -FilePath $Target -Certificate $Certificate `
        -TimestampServer $Timestamp -HashAlgorithm $HashAlg
    if ($sig.Status -ne "Valid" -and $sig.Status -ne "UnknownError") {
        throw "Signing failed for $Target : $($sig.Status) - $($sig.StatusMessage)"
    }
    return $true
}

function Test-SignatureHealthy {
    param(
        [string]$Target,
        [switch]$StrictTrusted
    )
    $sig = Get-AuthenticodeSignature -LiteralPath $Target
    if ($sig.Status -eq "NotSigned") {
        return @{ Ok = $false; Message = "Not signed" }
    }
    if ($sig.Status -eq "Valid") {
        return @{ Ok = $true; Message = "Valid ($($sig.SignerCertificate.Subject))" }
    }
    if (-not $StrictTrusted -and $sig.SignatureType -eq "Authenticode" -and $sig.SignerCertificate) {
        return @{ Ok = $true; Message = "$($sig.Status) ($($sig.SignerCertificate.Subject))" }
    }
    return @{ Ok = $false; Message = "$($sig.Status) - $($sig.StatusMessage)" }
}

$PfxPath = Resolve-FirstNonEmpty @(
    $PfxPath,
    $env:WIN_CODESIGN_PFX,
    $env:HESABIX_WIN_CODESIGN_PFX
)
$PfxPassword = Resolve-FirstNonEmpty @(
    $PfxPassword,
    $env:WIN_CODESIGN_PASSWORD,
    $env:HESABIX_WIN_CODESIGN_PASSWORD
)
$Thumbprint = Resolve-FirstNonEmpty @(
    $Thumbprint,
    $env:WIN_CODESIGN_THUMBPRINT
)
$SubjectContains = Resolve-FirstNonEmpty @(
    $SubjectContains,
    $env:WIN_CODESIGN_SUBJECT
)
if (-not $TimestampUrl) {
    $TimestampUrl = Resolve-FirstNonEmpty @(
        $env:WIN_CODESIGN_TIMESTAMP_URL,
        "http://timestamp.digicert.com"
    )
}

$targets = Expand-SignTargets -Inputs $Path
if ($targets.Count -eq 0) {
    throw "No signable files found under: $($Path -join ', ')"
}

$cert = Get-CodeSignCertificate -Pfx $PfxPath -Password $PfxPassword -Thumb $Thumbprint -Subject $SubjectContains
if (-not $cert) {
    throw @"
No code-signing certificate configured.
Set WIN_CODESIGN_PFX + WIN_CODESIGN_PASSWORD, or WIN_CODESIGN_THUMBPRINT, or WIN_CODESIGN_SUBJECT.
For production releases you need an OV/EV Authenticode certificate from a public CA.
"@
}

$signTool = Find-SignToolExe
$usePfxWithSignTool = [bool]($PfxPath -and $PfxPassword -and $signTool)
if ($PfxPath -and $PfxPassword -and -not $signTool) {
    Write-Host "[warn] signtool.exe not found; using Set-AuthenticodeSignature fallback." -ForegroundColor Yellow
    Write-Host "       Install 'Windows SDK Signing Tools' for best compatibility with Advanced Installer." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Signing $($targets.Count) file(s) with: $($cert.Subject)" -ForegroundColor Cyan
Write-Host "Timestamp: $TimestampUrl"
Write-Host ""

$failures = @()
foreach ($target in $targets) {
    try {
        if ($usePfxWithSignTool) {
            $code = Invoke-SignToolSign -SignTool $signTool -Target $target -Pfx $PfxPath `
                -Password $PfxPassword -Timestamp $TimestampUrl -Desc $Description -HashAlg $HashAlgorithm
            if ($code -ne 0) { throw "signtool exit $code" }
        } else {
            [void](Invoke-AuthenticodeSign -Target $target -Certificate $cert -Timestamp $TimestampUrl -HashAlg $HashAlgorithm)
        }

        $check = Test-SignatureHealthy -Target $target
        if ($Verify -and -not $check.Ok) {
            throw $check.Message
        }
        Write-Host "[ok] $target -> $($check.Message)" -ForegroundColor Green
    } catch {
        $failures += "$target : $_"
        Write-Host "[error] $target : $_" -ForegroundColor Red
    }
}

if ($failures.Count -gt 0) {
    throw "Signing failed for $($failures.Count) file(s)."
}

Write-Host ""
Write-Host "Signing completed." -ForegroundColor Green
exit 0
