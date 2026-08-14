$ErrorActionPreference = "Stop"

# Verify we're in the dashboard directory
if (-not (Test-Path "manage.py")) {
    Write-Error "ERROR: manage.py not found. Please cd to your dashboard folder first."
    exit 1
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  STEP 1: Git Add, Commit & Push" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Git status
git status

# Add all changes
Write-Host "Adding all changes..." -ForegroundColor Yellow
git add .

# Commit
Write-Host "Committing..." -ForegroundColor Yellow
git commit -m "feat: POS autocomplete search, stealth camera capture, auto-print invoice, live dashboard"

# Push
Write-Host "Pushing to origin main..." -ForegroundColor Yellow
git push origin main

Write-Host ""
Write-Host "Git push complete!" -ForegroundColor Green
Write-Host ""

# ========================================
# STEP 2: Delete Junk Files
# ========================================
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  STEP 2: Deleting Junk Files" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$deleted = 0

# Delete PowerShell scripts
$psFiles = Get-ChildItem -Path "." -Filter "*.ps1" -ErrorAction SilentlyContinue
foreach ($f in $psFiles) {
    Write-Host "  Deleting: $($f.Name)" -ForegroundColor Red
    Remove-Item -Path $f.FullName -Force
    $deleted++
}

# Delete backup files
$backupFiles = Get-ChildItem -Path "." -Filter "*.backup.*" -Recurse -ErrorAction SilentlyContinue
foreach ($f in $backupFiles) {
    Write-Host "  Deleting: $($f.FullName)" -ForegroundColor Red
    Remove-Item -Path $f.FullName -Force
    $deleted++
}

# Delete any .txt conversation dumps
$txtFiles = Get-ChildItem -Path "." -Filter "*.txt" -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*conversation*" -or $_.Name -like "*chat*" -or $_.Name -like "*New Chat*" }
foreach ($f in $txtFiles) {
    Write-Host "  Deleting: $($f.Name)" -ForegroundColor Red
    Remove-Item -Path $f.FullName -Force
    $deleted++
}

# Delete __pycache__ folders recursively
$pycacheFolders = Get-ChildItem -Path "." -Directory -Recurse -Filter "__pycache__" -ErrorAction SilentlyContinue
foreach ($f in $pycacheFolders) {
    Write-Host "  Deleting folder: $($f.FullName)" -ForegroundColor Red
    Remove-Item -Path $f.FullName -Recurse -Force
    $deleted++
}

# Delete .pyc files
$pycFiles = Get-ChildItem -Path "." -Filter "*.pyc" -Recurse -ErrorAction SilentlyContinue
foreach ($f in $pycFiles) {
    Write-Host "  Deleting: $($f.FullName)" -ForegroundColor Red
    Remove-Item -Path $f.FullName -Force
    $deleted++
}

Write-Host ""
if ($deleted -eq 0) {
    Write-Host "No junk files found." -ForegroundColor Green
} else {
    Write-Host "Deleted $deleted junk item(s)." -ForegroundColor Green
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  ALL DONE!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Clean files remaining:" -ForegroundColor Cyan
Write-Host "  - All Django app folders (accounts, customers, dashboard_app, etc.)" -ForegroundColor White
Write-Host "  - templates/, static/, media/" -ForegroundColor White
Write-Host "  - manage.py, db.sqlite3" -ForegroundColor White
Write-Host "  - .git/ (your repo)" -ForegroundColor White
Write-Host ""
