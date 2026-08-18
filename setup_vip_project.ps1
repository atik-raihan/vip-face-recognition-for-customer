$ErrorActionPreference = "Continue"

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host " VIP RECOGNITION PROJECT STATUS CHECKER" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

$ProjectRoot = (Get-Location).Path
$StatusFile = Join-Path $ProjectRoot "PROJECT_STATUS.txt"

$results = @()

function Add-Result {
    param(
        [string]$Name,
        [string]$Status,
        [string]$Details
    )

    $script:results += [PSCustomObject]@{
        Check = $Name
        Status = $Status
        Details = $Details
    }

    if ($Status -eq "PASS") {
        Write-Host "[PASS] $Name" -ForegroundColor Green
    }
    elseif ($Status -eq "WARN") {
        Write-Host "[WARN] $Name" -ForegroundColor Yellow
    }
    else {
        Write-Host "[FAIL] $Name" -ForegroundColor Red
    }

    if ($Details) {
        Write-Host "       $Details"
    }
}

Write-Host "Project folder:"
Write-Host "  $ProjectRoot"
Write-Host ""

# --------------------------------------------------
# 1. Django project
# --------------------------------------------------

$manage = Join-Path $ProjectRoot "manage.py"

if (Test-Path $manage) {
    Add-Result `
        "Django manage.py" `
        "PASS" `
        "Found: $manage"
}
else {
    Add-Result `
        "Django manage.py" `
        "FAIL" `
        "manage.py was not found in the current folder."
}

# --------------------------------------------------
# 2. Python
# --------------------------------------------------

try {
    $pythonVersion = python --version 2>&1
    Add-Result `
        "Python" `
        "PASS" `
        "$pythonVersion"
}
catch {
    Add-Result `
        "Python" `
        "FAIL" `
        "Python command could not be executed."
}

# --------------------------------------------------
# 3. Django check
# --------------------------------------------------

if (Test-Path $manage) {

    Write-Host ""
    Write-Host "Running Django system check..." -ForegroundColor Cyan

    $djangoCheck = python manage.py check 2>&1

    if ($LASTEXITCODE -eq 0) {

        Add-Result `
            "Django system check" `
            "PASS" `
            "python manage.py check completed successfully."

    }
    else {

        Add-Result `
            "Django system check" `
            "FAIL" `
            (($djangoCheck | Out-String).Trim())
    }
}

# --------------------------------------------------
# 4. POS URL / latest recognition source
# --------------------------------------------------

$viewsFiles = @(
    "face_recognition_app\views.py",
    "face_recognition_app\views_pos.py",
    "face_recognition_app\views_camera.py"
)

$latestFound = $false

foreach ($file in $viewsFiles) {

    $full = Join-Path $ProjectRoot $file

    if (Test-Path $full) {

        $content = Get-Content $full -Raw

        if ($content -match "def\s+latest_recognition\s*\(") {

            $latestFound = $true

            Add-Result `
                "latest_recognition()" `
                "PASS" `
                "Found in $file"

            break
        }
    }
}

if (-not $latestFound) {

    Add-Result `
        "latest_recognition()" `
        "WARN" `
        "Function was not found in the common view files."
}

# --------------------------------------------------
# 5. RecognitionLog
# --------------------------------------------------

$modelsFiles = Get-ChildItem `
    -Path $ProjectRoot `
    -Filter "*.py" `
    -Recurse `
    -ErrorAction SilentlyContinue

$recognitionLogFound = $false

foreach ($file in $modelsFiles) {

    try {

        $content = Get-Content $file.FullName -Raw

        if ($content -match "class\s+RecognitionLog\s*\(") {

            $recognitionLogFound = $true

            Add-Result `
                "RecognitionLog model" `
                "PASS" `
                "Found in $($file.FullName)"

            break
        }

    }
    catch {
    }
}

if (-not $recognitionLogFound) {

    Add-Result `
        "RecognitionLog model" `
        "WARN" `
        "RecognitionLog class was not found."
}

# --------------------------------------------------
# 6. POS template
# --------------------------------------------------

$templates = Get-ChildItem `
    -Path $ProjectRoot `
    -Filter "*.html" `
    -Recurse `
    -ErrorAction SilentlyContinue

$posFound = $false
$popupFound = $false
$pollFound = $false

foreach ($file in $templates) {

    try {

        $content = Get-Content $file.FullName -Raw

        if ($content -match "Point of Sale|POS") {

            $posFound = $true

            if ($content -match "welcome-back-modal") {
                $popupFound = $true
            }

            if ($content -match "latest-recognition") {
                $pollFound = $true
            }

            Add-Result `
                "POS template" `
                "PASS" `
                "Possible POS template: $($file.FullName)"

            break
        }

    }
    catch {
    }
}

if (-not $posFound) {

    Add-Result `
        "POS template" `
        "WARN" `
        "POS HTML template was not automatically located."
}

if ($popupFound) {

    Add-Result `
        "Welcome Back popup" `
        "PASS" `
        "welcome-back-modal was found in the POS template."

}
else {

    Add-Result `
        "Welcome Back popup" `
        "WARN" `
        "welcome-back-modal was not found automatically."
}

if ($pollFound) {

    Add-Result `
        "Recognition polling" `
        "PASS" `
        "latest-recognition endpoint reference found in POS HTML."

}
else {

    Add-Result `
        "Recognition polling" `
        "WARN" `
        "latest-recognition reference was not found."
}

# --------------------------------------------------
# 7. Camera recognition pipeline
# --------------------------------------------------

$cameraFile = Join-Path `
    $ProjectRoot `
    "face_recognition_app\camera\live_ai_camera.py"

if (Test-Path $cameraFile) {

    $cameraContent = Get-Content $cameraFile -Raw

    $hasGenFrames = $cameraContent -match "def\s+gen_frames"
    $hasRecognition = $cameraContent -match "RecognitionLog"
    $hasDedupe = $cameraContent -match "DEDUPE_WINDOW_SECONDS"
    $hasEvent = $cameraContent -match "on_customer_recognized"

    if ($hasGenFrames -and $hasRecognition) {

        Add-Result `
            "AI camera pipeline" `
            "PASS" `
            "gen_frames and RecognitionLog logic found."

    }
    else {

        Add-Result `
            "AI camera pipeline" `
            "WARN" `
            "Camera file exists but expected recognition logic was incomplete."
    }

    if ($hasDedupe) {

        Add-Result `
            "Recognition de-duplication" `
            "PASS" `
            "DEDUPE_WINDOW_SECONDS found."

    }
    else {

        Add-Result `
            "Recognition de-duplication" `
            "WARN" `
            "Deduplication setting was not found."
    }

    if ($hasEvent) {

        Add-Result `
            "Recognition event hook" `
            "PASS" `
            "on_customer_recognized hook found."

    }
    else {

        Add-Result `
            "Recognition event hook" `
            "WARN" `
            "Recognition event hook was not found."
    }

}
else {

    Add-Result `
        "AI camera pipeline" `
        "WARN" `
        "live_ai_camera.py was not found at the expected location."
}

# --------------------------------------------------
# 8. Customer model
# --------------------------------------------------

$customerFound = $false

foreach ($file in $modelsFiles) {

    try {

        $content = Get-Content $file.FullName -Raw

        if ($content -match "class\s+Customer\s*\(") {

            $customerFound = $true

            $vip = $content -match "is_vip"
            $purchase = $content -match "total_purchase"

            if ($vip -and $purchase) {

                Add-Result `
                    "Customer VIP system" `
                    "PASS" `
                    "Customer model contains total_purchase and is_vip."

            }
            else {

                Add-Result `
                    "Customer VIP system" `
                    "WARN" `
                    "Customer model found but VIP fields were incomplete."
            }

            break
        }

    }
    catch {
    }
}

if (-not $customerFound) {

    Add-Result `
        "Customer model" `
        "WARN" `
        "Customer model was not automatically located."
}

# --------------------------------------------------
# 9. Latest database recognition
# --------------------------------------------------

if (Test-Path $manage) {

    Write-Host ""
    Write-Host "Checking latest RecognitionLog..." -ForegroundColor Cyan

    $latestLog = python manage.py shell -c "from face_recognition_app.models import RecognitionLog; x=RecognitionLog.objects.order_by('-id').first(); print(x)" 2>&1

    if ($LASTEXITCODE -eq 0) {

        Add-Result `
            "Latest RecognitionLog" `
            "PASS" `
            (($latestLog | Out-String).Trim())

    }
    else {

        Add-Result `
            "Latest RecognitionLog" `
            "WARN" `
            (($latestLog | Out-String).Trim())
    }
}

# --------------------------------------------------
# 10. Database count
# --------------------------------------------------

if (Test-Path $manage) {

    $count = python manage.py shell -c "from face_recognition_app.models import RecognitionLog; print(RecognitionLog.objects.count())" 2>&1

    if ($LASTEXITCODE -eq 0) {

        Add-Result `
            "RecognitionLog database" `
            "PASS" `
            "RecognitionLog count: $count"

    }
    else {

        Add-Result `
            "RecognitionLog database" `
            "WARN" `
            "Could not read RecognitionLog count."
    }
}

# --------------------------------------------------
# 11. Migrations
# --------------------------------------------------

if (Test-Path $manage) {

    $migrationCheck = python manage.py showmigrations --plan 2>&1

    if ($LASTEXITCODE -eq 0) {

        Add-Result `
            "Django migrations" `
            "PASS" `
            "Migration plan loaded successfully."

    }
    else {

        Add-Result `
            "Django migrations" `
            "WARN" `
            "Could not inspect migrations."
    }
}

# --------------------------------------------------
# 12. Write project status
# --------------------------------------------------

$lines = @()

$lines += "VIP RECOGNITION PROJECT STATUS"
$lines += "Generated: $(Get-Date)"
$lines += ""
$lines += "PROJECT ROOT:"
$lines += $ProjectRoot
$lines += ""
$lines += "RESULTS:"
$lines += ""

foreach ($result in $results) {

    $lines += "[$($result.Status)] $($result.Check)"

    if ($result.Details) {
        $lines += "    $($result.Details)"
    }

    $lines += ""
}

$passCount = ($results | Where-Object {$_.Status -eq "PASS"}).Count
$warnCount = ($results | Where-Object {$_.Status -eq "WARN"}).Count
$failCount = ($results | Where-Object {$_.Status -eq "FAIL"}).Count

$lines += "SUMMARY"
$lines += "-------"
$lines += "PASS: $passCount"
$lines += "WARN: $warnCount"
$lines += "FAIL: $failCount"

$lines | Set-Content -Path $StatusFile -Encoding UTF8

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host " CHECK COMPLETE" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "PASS: $passCount" -ForegroundColor Green
Write-Host "WARN: $warnCount" -ForegroundColor Yellow
Write-Host "FAIL: $failCount" -ForegroundColor Red
Write-Host ""
Write-Host "Status file created:" -ForegroundColor Cyan
Write-Host $StatusFile -ForegroundColor White
Write-Host ""