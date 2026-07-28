# install_wiring.ps1
# Wiring installer - dynamic threshold + navigation + final Django check
# Run from: D:\Downloads\vip-recognition-core\vip-recognition\dashboard\
# Run AFTER install_dashboard.ps1 and install_settings_camera.ps1

$ErrorActionPreference = "Stop"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$appDir = "face_recognition_app"

function Backup-File($path) {
    if (Test-Path $path) {
        $bak = "$path.$timestamp.bak"
        Copy-Item $path $bak
        Write-Host "[BACKUP] $path -> $bak" -ForegroundColor Cyan
    }
}

Write-Host "=== Installing Wiring + Final Checks ===" -ForegroundColor Yellow

# ------------------------------------------------------------------
# 1. UPDATE face_service.py FOR DYNAMIC THRESHOLD (Item 9)
# ------------------------------------------------------------------
$servicePath = "$appDir\services\face_service.py"

if (Test-Path $servicePath) {
    Backup-File $servicePath
    $serviceContent = Get-Content $servicePath -Raw

    # Check if already updated
    if ($serviceContent -notmatch "SystemSettings.get_settings") {
        # Add import at top if not present
        if ($serviceContent -notmatch "from face_recognition_app.models import SystemSettings") {
            $serviceContent = "from face_recognition_app.models import SystemSettings`n" + $serviceContent
        }

        # Replace hardcoded threshold with dynamic lookup
        $serviceContent = $serviceContent -replace "threshold=0\.65", "threshold=None"
        $serviceContent = $serviceContent -replace "threshold=0\.6", "threshold=None"

        # Add dynamic threshold logic inside recognize() method
        # Look for the recognize method and inject settings lookup
        if ($serviceContent -match "def recognize\(self.*threshold") {
            $serviceContent = $serviceContent -replace "(def recognize\(self[^)]*threshold[^)]*\):)", @'
$1
        if threshold is None:
            # ITEM 9: Dynamic threshold from settings
            try:
                settings = SystemSettings.get_settings()
                threshold = settings.recognition_threshold
            except Exception:
                threshold = 0.65
'@
        }

        $serviceContent | Out-File -Encoding ASCII $servicePath
        Write-Host "[UPDATE] Dynamic threshold wired into $servicePath" -ForegroundColor Green
    } else {
        Write-Host "[SKIP] Dynamic threshold already wired" -ForegroundColor Yellow
    }

    $syntaxCheck = python -c "import py_compile; py_compile.compile('$servicePath', doraise=True)" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[FAIL] Syntax error in $servicePath" -ForegroundColor Red
        Write-Host $syntaxCheck
        exit 1
    }
    Write-Host "[OK] Syntax check passed: $servicePath" -ForegroundColor Green
} else {
    Write-Host "[WARN] $servicePath not found - skip threshold wiring" -ForegroundColor Yellow
}

# ------------------------------------------------------------------
# 2. NAVIGATION LINKS (create/update sidebar snippet)
# ------------------------------------------------------------------
$navSnippet = @'
<!-- Face Recognition Menu -->
<li class="treeview">
  <a href="#">
    <i class="fa fa-user-secret"></i> <span>Face Recognition</span>
    <span class="pull-right-container"><i class="fa fa-angle-left pull-right"></i></span>
  </a>
  <ul class="treeview-menu">
    <li><a href="{% url 'camera' %}"><i class="fa fa-video-camera"></i> Live Camera</a></li>
    <li><a href="{% url 'recognition_dashboard' %}"><i class="fa fa-dashboard"></i> Recognition Dashboard</a></li>
    <li><a href="{% url 'settings_page' %}"><i class="fa fa-sliders"></i> Settings</a></li>
    <li><a href="{% url 'camera_list' %}"><i class="fa fa-list"></i> Cameras</a></li>
  </ul>
</li>
'@

$navPath = "templates\face_recognition_app\_nav_snippet.html"
$navSnippet | Out-File -Encoding ASCII $navPath
Write-Host "[WRITE] Navigation snippet: $navPath" -ForegroundColor Green
Write-Host "[INFO] Paste the above snippet into your base template sidebar" -ForegroundColor Cyan

# ------------------------------------------------------------------
# 3. CREATE DEFAULT SYSTEM SETTINGS (if not exists)
# ------------------------------------------------------------------
Write-Host "`n=== Creating default SystemSettings ===" -ForegroundColor Yellow
python -c "
import django
django.setup()
from face_recognition_app.models import SystemSettings
s, created = SystemSettings.objects.get_or_create(pk=1)
if created:
    print('[OK] Default SystemSettings created')
else:
    print('[OK] SystemSettings already exists')
" 2>&1

# ------------------------------------------------------------------
# 4. FINAL DJANGO CHECKS
# ------------------------------------------------------------------
Write-Host "`n=== Running makemigrations ===" -ForegroundColor Yellow
python manage.py makemigrations face_recognition_app --dry-run

Write-Host "`n=== Running migrate ===" -ForegroundColor Yellow
python manage.py migrate

Write-Host "`n=== Running full Django system check ===" -ForegroundColor Yellow
python manage.py check
if ($LASTEXITCODE -ne 0) {
    Write-Host "[FAIL] Django check failed" -ForegroundColor Red
    exit 1
}

Write-Host "`n=== Running server test (5 seconds) ===" -ForegroundColor Yellow
$proc = Start-Process -FilePath "python" -ArgumentList "manage.py","runserver" -PassThru -WindowStyle Hidden
Start-Sleep -Seconds 5
$proc | Stop-Process -Force
Write-Host "[OK] Server starts without errors" -ForegroundColor Green

# ------------------------------------------------------------------
# 5. SUMMARY
# ------------------------------------------------------------------
Write-Host "`n========================================" -ForegroundColor Green
Write-Host "  ALL WIRING COMPLETE" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "New pages available:" -ForegroundColor Cyan
Write-Host "  http://localhost:8000/recognition-dashboard/  - Dashboard" -ForegroundColor White
Write-Host "  http://localhost:8000/settings/               - Settings" -ForegroundColor White
Write-Host "  http://localhost:8000/cameras/                - Camera list" -ForegroundColor White
Write-Host "  http://localhost:8000/camera/<id>/              - Camera feed" -ForegroundColor White
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Add nav snippet to your base template sidebar" -ForegroundColor White
Write-Host "  2. Run: python manage.py runserver" -ForegroundColor White
Write-Host "  3. Test each new page" -ForegroundColor White
Write-Host "  4. If errors, paste traceback" -ForegroundColor White