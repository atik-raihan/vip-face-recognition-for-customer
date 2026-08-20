$ErrorActionPreference = "Stop"

$projectRoot = (Get-Location).Path
$target = Join-Path $projectRoot "sales\views.py"
$backup = "$target.backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"

if (-not (Test-Path $target)) {
    throw "Could not find $target. Run this from the dashboard project root."
}

Copy-Item $target $backup -Force

$source = Join-Path $PSScriptRoot "sales_views_fixed.py"
if (-not (Test-Path $source)) {
    throw "Could not find $source."
}

Copy-Item $source $target -Force

Write-Host ""
Write-Host "POS sales/views.py replaced successfully." -ForegroundColor Green
Write-Host "Backup created: $backup" -ForegroundColor Yellow
Write-Host ""

python manage.py check

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "Django check failed. Restoring backup..." -ForegroundColor Red
    Copy-Item $backup $target -Force
    throw "Replacement was rolled back."
}

Write-Host ""
Write-Host "POS backend setup completed successfully." -ForegroundColor Green
