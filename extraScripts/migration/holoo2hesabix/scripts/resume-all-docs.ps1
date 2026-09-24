# Resume remaining document modules after invoices (receipts/checks/expense/manual EI-fallback).
# Uses DebugBuild2 binary (latest) and existing checkpoint for business 6823.
param(
    [int]$BusinessId = 6823,
    [string]$ApiKeyFile = "",    [string]$Exe = "d:\hesabixArc\extraScripts\migration\holoo2hesabix\bin\DebugBuild2\Holoo2Hesabix.exe"
)
$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ApiKeyFile)) { $ApiKeyFile = if ($env:HESABIX_API_KEY_FILE) { $env:HESABIX_API_KEY_FILE } else { Join-Path $env:USERPROFILE '.hesabix\api_key.txt' } }
if (-not (Test-Path $Exe)) { throw "exe missing: $Exe" }
$apiKey = (Get-Content $ApiKeyFile -Raw).Trim()
$stdout = "d:\hesabixArc\.eyeban\e2e-alldocs-stdout.txt"
$stderr = "d:\hesabixArc\.eyeban\e2e-alldocs-stderr.txt"
$argList = @(
  "--e2e-opening","--docs-only","--with-all-docs",
  "--business-id", "$BusinessId",
  "--sql-server","localhost","--sql-user","sa","--sql-pass",($(if ($env:HOLOO_SQL_PASS) { $env:HOLOO_SQL_PASS } else { "" })),"--sql-db","Holoo1",
  "--api-key",$apiKey,"--base-url","https://api.hesabix.ir",
  "--result","d:\hesabixArc\.eyeban\e2e-alldocs-result.json"
)
Write-Host "Starting with-all-docs from checkpoint (invoices will resume/skip done)..."
$p = Start-Process -FilePath $Exe -ArgumentList $argList -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru -WindowStyle Hidden
Set-Content "d:\hesabixArc\.eyeban\e2e-alldocs-pid.txt" $p.Id
Write-Host "pid=$($p.Id) stdout=$stdout"

