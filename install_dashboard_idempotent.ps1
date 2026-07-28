# install_dashboard_idempotent.ps1
# Safe, idempotent dashboard installer

$ErrorActionPreference = 'Stop'
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'

$appDir = 'face_recognition_app'
$templateDir = 'templates\face_recognition_app'

function Backup-File($path) {
    if (Test-Path $path) {
        $bak = "$path.$timestamp.bak"
        Copy-Item $path $bak -Force
        Write-Host "[BACKUP] $path -> $bak" -ForegroundColor Cyan
    }
}

function Ensure-Directory($path) {
    if (!(Test-Path $path)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
    }
}

function Write-FileIfChanged($path, $content) {
    $existing = if (Test-Path $path) { Get-Content $path -Raw } else { '' }

    if ($existing -ne $content) {
        Backup-File $path
        $content | Out-File -FilePath $path -Encoding ASCII
        Write-Host "[WRITE] $path" -ForegroundColor Green
    }
    else {
        Write-Host "[SKIP] $path already up to date" -ForegroundColor Yellow
    }
}

Write-Host "=== Installing Recognition Dashboard (Idempotent) ===" -ForegroundColor Yellow

# ------------------------------------------------------------
# 1. views_dashboard.py
# ------------------------------------------------------------

$dashboardView = @'
from django.contrib.auth.decorators import login_required
from django.db.models import Count
from django.http import JsonResponse
from django.shortcuts import render
from django.utils import timezone

from .models import RecognitionLog


@login_required
def recognition_dashboard(request):
    today = timezone.localdate()
    today_logs = RecognitionLog.objects.filter(recognized_at__date=today)

    context = {
        "today_total": today_logs.count(),
        "today_vip": today_logs.filter(was_vip_at_time=True).count(),
        "today_normal": today_logs.filter(customer__isnull=False, was_vip_at_time=False).count(),
        "today_unknown": today_logs.filter(customer__isnull=True).count(),
        "recent_logs": RecognitionLog.objects.select_related("customer", "camera").order_by("-recognized_at")[:20],
    }

    return render(request, "face_recognition_app/recognition_dashboard.html", context)


@login_required
def recognition_dashboard_api(request):
    today = timezone.localdate()
    today_logs = RecognitionLog.objects.filter(recognized_at__date=today)

    latest = []
    for log in RecognitionLog.objects.select_related("customer", "camera").order_by("-recognized_at")[:10]:
        latest.append({
            "id": log.id,
            "customer_name": log.customer.name if log.customer else "Unknown",
            "was_vip": log.was_vip_at_time,
            "confidence": round(log.confidence, 2) if log.confidence else None,
            "camera_name": log.camera.name if log.camera else "Default",
            "timestamp": timezone.localtime(log.recognized_at).strftime("%H:%M:%S"),
            "snapshot_url": log.snapshot.url if log.snapshot else None,
        })

    return JsonResponse({
        "today_total": today_logs.count(),
        "today_vip": today_logs.filter(was_vip_at_time=True).count(),
        "today_normal": today_logs.filter(customer__isnull=False, was_vip_at_time=False).count(),
        "latest": latest,
    })
'@

Write-FileIfChanged "$appDir\views_dashboard.py" $dashboardView

# ------------------------------------------------------------
# 2. recognition_dashboard.html
# ------------------------------------------------------------

Ensure-Directory $templateDir

$dashboardTemplate = @'
{% extends "base.html" %}

{% block content %}
<div class="container">
  <h2>Recognition Dashboard</h2>

  <div class="row">
    <div class="col-md-3"><div class="panel panel-primary"><div class="panel-body"><h3>{{ today_total }}</h3><p>Today Total</p></div></div></div>
    <div class="col-md-3"><div class="panel panel-warning"><div class="panel-body"><h3>{{ today_vip }}</h3><p>VIP Visits</p></div></div></div>
    <div class="col-md-3"><div class="panel panel-success"><div class="panel-body"><h3>{{ today_normal }}</h3><p>Normal Visits</p></div></div></div>
    <div class="col-md-3"><div class="panel panel-default"><div class="panel-body"><h3>{{ today_unknown }}</h3><p>Unknown Faces</p></div></div></div>
  </div>

  <h3>Recent Recognitions</h3>
  <table class="table table-bordered table-striped">
    <thead>
      <tr>
        <th>Time</th>
        <th>Customer</th>
        <th>VIP</th>
        <th>Confidence</th>
        <th>Camera</th>
      </tr>
    </thead>
    <tbody>
      {% for log in recent_logs %}
      <tr>
        <td>{{ log.recognized_at|date:"Y-m-d H:i:s" }}</td>
        <td>{% if log.customer %}{{ log.customer.name }}{% else %}Unknown{% endif %}</td>
        <td>{% if log.was_vip_at_time %}YES{% else %}NO{% endif %}</td>
        <td>{{ log.confidence|floatformat:2 }}</td>
        <td>{{ log.camera.name|default:"Default" }}</td>
      </tr>
      {% empty %}
      <tr><td colspan="5">No recognitions yet.</td></tr>
      {% endfor %}
    </tbody>
  </table>
</div>
{% endblock %}
'@

Write-FileIfChanged "$templateDir\recognition_dashboard.html" $dashboardTemplate

# ------------------------------------------------------------
# 3. Update urls.py safely
# ------------------------------------------------------------

$urlsPath = "$appDir\urls.py"
Backup-File $urlsPath

$urlsContent = Get-Content $urlsPath -Raw

# Add import once
if ($urlsContent -notmatch 'from \. import views_dashboard') {
    $urlsContent = $urlsContent -replace 'from \. import views', "from . import views`r`nfrom . import views_dashboard"
    Write-Host '[PATCH] Added views_dashboard import' -ForegroundColor Green
}
else {
    Write-Host '[SKIP] views_dashboard import already present' -ForegroundColor Yellow
}

# Add dashboard URL once
if ($urlsContent -notmatch 'name="recognition_dashboard"') {
    $urlsContent = $urlsContent -replace '\]\s*$', @"
    path('recognition-dashboard/', views_dashboard.recognition_dashboard, name='recognition_dashboard'),
    path('recognition-dashboard/api/', views_dashboard.recognition_dashboard_api, name='recognition_dashboard_api'),
]
"@
    Write-Host '[PATCH] Added dashboard URL patterns' -ForegroundColor Green
}
else {
    Write-Host '[SKIP] Dashboard URL patterns already present' -ForegroundColor Yellow
}

$urlsContent | Out-File -FilePath $urlsPath -Encoding ASCII

# ------------------------------------------------------------
# 4. Validate Django project
# ------------------------------------------------------------

Write-Host 'Running Django system check...' -ForegroundColor Yellow

python manage.py check

if ($LASTEXITCODE -ne 0) {
    Write-Host '[FAIL] Django check failed' -ForegroundColor Red
    exit 1
}

Write-Host ''
Write-Host '[OK] Dashboard installation completed successfully.' -ForegroundColor Green
Write-Host 'Open: http://127.0.0.1:8000/recognition-dashboard/' -ForegroundColor Cyan