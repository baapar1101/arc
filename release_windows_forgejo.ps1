# Publish / attach the Windows MSI as a Forgejo release asset for hesabix/arc.
#
# Version from hesabixUI/hesabix_ui/pubspec.yaml (MAJOR.MINOR.PATCH).
# Asset name: hesabix-windows.<version>.msi
#
# Unlike the Android release script, this script:
#   - Creates the release if missing
#   - If the release already exists (e.g. Android published first), attaches/replaces
#     ONLY the Windows MSI asset — it does not delete the whole release or the APK.
#
# Auth:
#   $env:FORGEJO_TOKEN = '...'
#   or $env:FORGEJO_USER / $env:FORGEJO_PASSWORD
#
# Examples:
#   .\release_windows_forgejo.ps1
#   .\release_windows_forgejo.ps1 -MsiPath installer\windows\dist\hesabix-windows.70.11.380.msi
#   .\release_windows_forgejo.ps1 -DryRun

param(
    [string]$MsiPath = "",
    [string]$PubspecPath = "",
    [string]$Body = "",
    [string]$BodyFile = "",
    [string]$User = $env:FORGEJO_USER,
    [string]$Password = $env:FORGEJO_PASSWORD,
    [string]$Token = $env:FORGEJO_TOKEN,
    [string]$ApiBase = $(if ($env:FORGEJO_API_BASE) { $env:FORGEJO_API_BASE } else { "https://source.hesabix.ir/api/v1" }),
    [string]$Owner = $(if ($env:FORGEJO_OWNER) { $env:FORGEJO_OWNER } else { "hesabix" }),
    [string]$Repo = $(if ($env:FORGEJO_REPO) { $env:FORGEJO_REPO } else { "arc" }),
    [string]$Target = $(if ($env:FORGEJO_TARGET) { $env:FORGEJO_TARGET } else { "master" }),
    [switch]$ForceAsset,
    [switch]$DryRun,
    [switch]$Help
)

$ErrorActionPreference = "Stop"

$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$REPO_ROOT = $SCRIPT_DIR
$DEFAULT_PUBSPEC = Join-Path $REPO_ROOT "hesabixUI\hesabix_ui\pubspec.yaml"
$DEFAULT_MSI_DIR = Join-Path $REPO_ROOT "installer\windows\dist"

function Write-Usage {
    Write-Host @"
Usage: .\release_windows_forgejo.ps1 [options]

Options:
  -MsiPath PATH       MSI file (default: installer\windows\dist\hesabix-windows.<ver>.msi)
  -PubspecPath PATH   pubspec.yaml
  -Body TEXT          Release notes (used only when creating a new release)
  -BodyFile PATH      Read release notes from file
  -User / -Password   Forgejo basic auth
  -Token TOKEN        Forgejo API token (preferred)
  -ForceAsset         Replace existing Windows MSI asset on the same tag
  -DryRun             Print actions only
  -Help               Show help
"@
}

if ($Help) {
    Write-Usage
    exit 0
}

function Get-PubspecVersionName {
    param([string]$Path)
    $line = Get-Content -LiteralPath $Path -ErrorAction Stop |
        Where-Object { $_ -match '^\s*version:\s*' } |
        Select-Object -First 1
    if (-not $line) { throw "No version: line in $Path" }
    if ($line -match '^\s*version:\s*([^\s#]+)') {
        $full = $Matches[1].Trim().Trim(([char[]]@(34, 39)))
        $name = ($full -split '\+', 2)[0].Trim()
        $parts = $name -split '\.'
        if ($parts.Count -ne 3 -or ($parts | Where-Object { $_ -notmatch '^\d+$' })) {
            throw "versionName must be MAJOR.MINOR.PATCH, got: $name"
        }
        return $name
    }
    throw "Could not parse version from $Path"
}

function Get-AuthHeaders {
    if ($User -and $Password) {
        $pair = "{0}:{1}" -f $User, $Password
        $bytes = [System.Text.Encoding]::ASCII.GetBytes($pair)
        $b64 = [Convert]::ToBase64String($bytes)
        return @{ Authorization = "Basic $b64" }
    }
    if ($Token) {
        return @{ Authorization = "token $Token" }
    }
    throw "Auth required: set FORGEJO_TOKEN or FORGEJO_USER+FORGEJO_PASSWORD"
}

if (-not $PubspecPath) { $PubspecPath = $DEFAULT_PUBSPEC }
if (-not (Test-Path -LiteralPath $PubspecPath)) {
    throw "pubspec not found: $PubspecPath"
}

$VERSION = Get-PubspecVersionName -Path $PubspecPath
$ASSET_NAME = "hesabix-windows.$VERSION.msi"

if (-not $MsiPath) {
    $MsiPath = Join-Path $DEFAULT_MSI_DIR $ASSET_NAME
}
if (-not (Test-Path -LiteralPath $MsiPath)) {
    throw "MSI not found: $MsiPath (run .\build_windows_installer.ps1 first)"
}

if ($BodyFile) {
    if (-not (Test-Path -LiteralPath $BodyFile)) { throw "body file not found: $BodyFile" }
    $Body = Get-Content -LiteralPath $BodyFile -Raw -Encoding UTF8
}
if (-not $Body) {
    $Body = @"
- انتشار نسخه ویندوز $VERSION
- به‌روزرسانی از ریلیزهای رسمی حسابیکس (MSI)
"@
}

$headers = Get-AuthHeaders
$headers["Accept"] = "application/json"

Write-Host "INFO: Version (tag): $VERSION"
Write-Host "INFO: MSI:           $MsiPath"
Write-Host "INFO: Asset name:    $ASSET_NAME"
Write-Host "INFO: Repo:          $Owner/$Repo @ $Target"
Write-Host "INFO: API:           $ApiBase"

if ($DryRun) {
    Write-Host "INFO: Dry-run only - no release will be created/updated."
    exit 0
}

function Invoke-ForgejoJson {
    param(
        [string]$Method,
        [string]$Url,
        [hashtable]$ExtraHeaders = @{},
        [string]$BodyJson = $null,
        [string]$InFile = $null,
        [string]$ContentType = $null
    )
    $h = @{}
    foreach ($k in $headers.Keys) { $h[$k] = $headers[$k] }
    foreach ($k in $ExtraHeaders.Keys) { $h[$k] = $ExtraHeaders[$k] }
    if ($ContentType) { $h["Content-Type"] = $ContentType }

    $params = @{
        Method  = $Method
        Uri     = $Url
        Headers = $h
    }
    if ($BodyJson) { $params["Body"] = $BodyJson }
    if ($InFile) {
        $params["InFile"] = $InFile
    }

    try {
        return Invoke-RestMethod @params
    } catch {
        $resp = $_.Exception.Response
        if ($resp -and [int]$resp.StatusCode -eq 404) {
            return $null
        }
        throw
    }
}

$tagUrl = "$ApiBase/repos/$Owner/$Repo/releases/tags/$VERSION"
$existing = Invoke-ForgejoJson -Method GET -Url $tagUrl
if ($null -eq $existing) {
    Write-Host "INFO: No existing release found for tag $VERSION."
}

$releaseId = $null
if ($null -ne $existing -and $null -ne $existing.id -and "$($existing.id)" -ne "") {
    $releaseId = $existing.id
    Write-Host ("INFO: Release {0} already exists (id={1}) - attaching Windows asset only." -f $VERSION, $releaseId)

    $winAssets = @($existing.assets | Where-Object {
            $_.name -and (
                $_.name.ToString() -eq $ASSET_NAME -or
                ($ForceAsset -and (
                    $_.name.ToString().ToLower().EndsWith('.msi') -or
                    $_.name.ToString().ToLower().StartsWith('hesabix-windows')
                ))
            )
        })
    foreach ($a in $winAssets) {
        if ($a.name -eq $ASSET_NAME -or $ForceAsset) {
            Write-Host "WARN: Deleting existing asset $($a.name) (id=$($a.id))"
            $deleted = $false
            foreach ($delUri in @(
                    "$ApiBase/repos/$Owner/$Repo/releases/$releaseId/assets/$($a.id)",
                    "$ApiBase/repos/$Owner/$Repo/releases/assets/$($a.id)"
                )) {
                try {
                    $null = Invoke-WebRequest -Method DELETE -Uri $delUri -Headers $headers -UseBasicParsing
                    $deleted = $true
                    break
                } catch {
                    $code = $null
                    if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
                    # Forgejo may return 404 even when the asset is gone; re-check below.
                    Write-Host ("WARN: Delete via {0} failed ({1}); trying next." -f $delUri, $(if ($code) { $code } else { $_.Exception.Message }))
                }
            }
            if (-not $deleted) {
                Write-Host "WARN: Could not confirm delete for $($a.name); will re-check before upload."
            }
        }
    }
    $existing = Invoke-ForgejoJson -Method GET -Url $tagUrl
    $dup = @($existing.assets | Where-Object { $_.name -eq $ASSET_NAME })
    if ($dup.Count -gt 0) {
        if (-not $ForceAsset) {
            throw "Asset $ASSET_NAME already exists on release $VERSION. Use -ForceAsset to replace."
        }
        throw ("Asset {0} still present after delete attempts (id={1}). Delete it in the Forgejo UI, then re-run." -f $ASSET_NAME, $dup[0].id)
    }
} else {
    Write-Host "INFO: Creating release $VERSION..."
    $payload = @{
        tag_name         = $VERSION
        target_commitish = $Target
        name             = $VERSION
        body             = $Body
        draft            = $false
        prerelease       = $false
    } | ConvertTo-Json -Compress -Depth 5
    $created = Invoke-ForgejoJson -Method POST -Url "$ApiBase/repos/$Owner/$Repo/releases" `
        -BodyJson $payload -ContentType "application/json; charset=utf-8"
    if (-not $created.id) { throw "Failed to create release: $($created | ConvertTo-Json -Compress)" }
    $releaseId = $created.id
    Write-Host ("INFO: Release id={0} {1}" -f $releaseId, $created.html_url)
}

Write-Host "INFO: Uploading $ASSET_NAME..."
$uploadUrl = "$ApiBase/repos/$Owner/$Repo/releases/$releaseId/assets?name=$ASSET_NAME"
$uploadHeaders = @{
    Authorization = $headers.Authorization
    "Content-Type" = "application/octet-stream"
}
# Large MSIs often exceed the default WebRequest timeout on Forgejo.
$uploaded = Invoke-RestMethod -Method POST -Uri $uploadUrl -Headers $uploadHeaders -InFile $MsiPath -TimeoutSec 900
if (-not $uploaded.id) {
    throw "Upload failed: $($uploaded | ConvertTo-Json -Compress)"
}
Write-Host "INFO: Asset uploaded: $($uploaded.name) size=$($uploaded.size)"
Write-Host "INFO: Download: $($uploaded.browser_download_url)"

$latest = Invoke-RestMethod -Method GET -Uri "$ApiBase/repos/$Owner/$Repo/releases/latest" -Headers $headers
Write-Host "INFO: Latest release is now: $($latest.tag_name)"
foreach ($a in @($latest.assets)) {
    Write-Host "INFO:  - $($a.name) $($a.browser_download_url)"
}
Write-Host "INFO: Done."
