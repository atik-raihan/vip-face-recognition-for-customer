@'
$ErrorActionPreference = "Stop"

$Root = (Get-Location).Path

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " VIP RECOGNITION - FINAL WARNING FIX" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# ------------------------------------------------------------
# FILES
# ------------------------------------------------------------

$checker = Join-Path $Root "finish_vip_features.ps1"
$faceUrls = Join-Path $Root "face_recognition_app\urls.py"
$productUrls = Join-Path $Root "products\urls.py"

if (-not (Test-Path $checker)) {
    throw "finish_vip_features.ps1 was not found."
}

if (-not (Test-Path $faceUrls)) {
    throw "face_recognition_app\urls.py was not found."
}

if (-not (Test-Path $productUrls)) {
    throw "products\urls.py was not found."
}

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"

# ------------------------------------------------------------
# BACKUPS
# ------------------------------------------------------------

Copy-Item $checker "$checker.backup_$stamp" -Force
Copy-Item $faceUrls "$faceUrls.backup_$stamp" -Force
Copy-Item $productUrls "$productUrls.backup_$stamp" -Force

Write-Host "[PASS] Backups created." -ForegroundColor Green

# ------------------------------------------------------------
# 1. FIX DASHBOARD TEMPLATE CHECK
# ------------------------------------------------------------

$checkerText = Get-Content $checker -Raw

$checkerText = [regex]::Replace(
    $checkerText,
    '(?m)^\s*\$dashboardTemplate\s*=.*$',
    '$dashboardTemplate = ".\templates\face_recognition_app\dashboard.html"'
)

Set-Content $checker $checkerText -Encoding UTF8

Write-Host "[PASS] Dashboard template check path fixed." -ForegroundColor Green

# ------------------------------------------------------------
# 2. FIX FACE RECOGNITION URL DUPLICATES
# ------------------------------------------------------------

$faceText = Get-Content $faceUrls -Raw

# Remove duplicate analytics dashboard route.
$analyticsRoute = @'
    path("analytics/", views.analytics_dashboard, name="analytics_dashboard"),
'@

$firstAnalytics = $faceText.IndexOf($analyticsRoute)

if ($firstAnalytics -ge 0) {

    $secondAnalytics = $faceText.IndexOf(
        $analyticsRoute,
        $firstAnalytics + $analyticsRoute.Length
    )

    if ($secondAnalytics -ge 0) {
        $faceText =
            $faceText.Remove(
                $secondAnalytics,
                $analyticsRoute.Length
            )

        Write-Host "[PASS] Duplicate analytics URL removed." -ForegroundColor Green
    }
}

# Remove duplicate POS customer-search route.
$customerRoute = '    path("api/pos/customer-search/", views.pos_customer_search, name="pos_customer_search"),'

$firstCustomer = $faceText.IndexOf($customerRoute)

if ($firstCustomer -ge 0) {

    $secondCustomer = $faceText.IndexOf(
        $customerRoute,
        $firstCustomer + $customerRoute.Length
    )

    if ($secondCustomer -ge 0) {
        $faceText =
            $faceText.Remove(
                $secondCustomer,
                $customerRoute.Length
            )

        Write-Host "[PASS] Duplicate customer-search URL removed." -ForegroundColor Green
    }
}

Set-Content $faceUrls $faceText -Encoding UTF8

# ------------------------------------------------------------
# 3. FIX PRODUCTS URL DUPLICATE
# ------------------------------------------------------------

$productText = Get-Content $productUrls -Raw

$productDeleteBlock = @'
        path(
        "delete/<int:pk>/",
        views.delete_product,
        name="delete_product"
    ),

'@

$firstDelete = $productText.IndexOf($productDeleteBlock)

if ($firstDelete -ge 0) {

    $secondDelete = $productText.IndexOf(
        $productDeleteBlock,
        $firstDelete + $productDeleteBlock.Length
    )

    if ($secondDelete -ge 0) {

        $productText =
            $productText.Remove(
                $secondDelete,
                $productDeleteBlock.Length
            )

        Write-Host "[PASS] Duplicate product-delete URL removed." -ForegroundColor Green
    }
}

Set-Content $productUrls $productText -Encoding UTF8

# ------------------------------------------------------------
# 4. DJANGO CHECK
# ------------------------------------------------------------

Write-Host ""
Write-Host "Running Django system check..." -ForegroundColor Cyan

python manage.py check

if ($LASTEXITCODE -ne 0) {
    throw "Django system check failed."
}

# ------------------------------------------------------------
# 5. RUN FINAL HEALTH CHECK
# ------------------------------------------------------------

Write-Host ""
Write-Host "Running final project health check..." -ForegroundColor Cyan
Write-Host ""

powershell -ExecutionPolicy Bypass -File ".\finish_vip_features.ps1"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host " WARNING FIX FINISHED" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
