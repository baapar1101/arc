# Clear transient invoice failures from checkpoint (ASCII-safe).
param([int]$BusinessId = 6823, [string]$HolooDb = "Holoo1")
$ErrorActionPreference = "Stop"
$path = Join-Path $env:LOCALAPPDATA "Holoo2Hesabix\checkpoints\biz${BusinessId}_${HolooDb}.json"
if (-not (Test-Path $path)) { throw "checkpoint not found: $path" }
$cp = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json
$inv = $cp.Modules.Invoices; if (-not $inv) { $inv = $cp.modules.Invoices }
if (-not $inv) { throw "Invoices module missing" }
$failed = $inv.Failed; if (-not $failed) { $failed = $inv.failed }
$doneObj = $inv.Done; if (-not $doneObj) { $doneObj = $inv.done }
if (-not $failed) { Write-Host "No invoice failures."; exit 0 }
$removed = @()
foreach ($p in @($failed.PSObject.Properties)) {
  $msg = [string]$p.Value
  $isTransient = $msg -match "internal|timeout|502|503|504|\b500\b|Unavailable|canceled|cancelled|Task was canceled|A task was canceled"
  if ($isTransient) { $removed += $p.Name }
}
foreach ($name in $removed) {
  $failed.PSObject.Properties.Remove($name)
  Write-Host "cleared: $name"
}
[IO.File]::WriteAllText($path, ($cp | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false))
$remain = if ($failed) { @($failed.PSObject.Properties).Count } else { 0 }
$doneN = if ($doneObj) { @($doneObj.PSObject.Properties).Count } else { 0 }
Write-Host "Removed $($removed.Count); remaining=$remain; done=$doneN"
