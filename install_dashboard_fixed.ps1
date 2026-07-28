# install_dashboard.ps1
# Recognition Dashboard installer - Item 5
# Run from: D:\Downloads\vip-recognition-core\vip-recognition\dashboard\
# Requires: Django project with face_recognition_app already set up

$ErrorActionPreference = "Stop"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$appDir = "face_recognition_app"
$templateDir = "templates\face_recognition_app"

function Backup-File($path) {
    if (Test-Path $path) {
        $bak = "$path.$timestamp.bak"
        Copy-Item $path $bak
        Write-Host "[BACKUP] $path -> $bak" -ForegroundColor Cyan
    }
}

function Write-TemplateFile($path, $content) {
    Backup-File $path
    $dir = Split-Path $path
    if (!(Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $content | Out-File -Encoding ASCII $path
    Write-Host "[WRITE] $path" -ForegroundColor Green
}

Write-Host "=== Installing Recognition Dashboard ===" -ForegroundColor Yellow

# ------------------------------------------------------------------
# 1. DASHBOARD VIEW (write as separate file, import in views.py)
# ------------------------------------------------------------------
$dashboardView = @"
from django.db.models import Count
from django.utils import timezone
from django.contrib.auth.decorators import login_required
from django.http import JsonResponse
from django.shortcuts import render
from .models import RecognitionLog


@login_required
def recognition_dashboard(request):
    today = timezone.now().date()
    today_start = timezone.make_aware(
        timezone.datetime.combine(today, timezone.datetime.min.time())
    )
    today_end = timezone.make_aware(
        timezone.datetime.combine(today, timezone.datetime.max.time())
    )

    today_logs = RecognitionLog.objects.filter(
        created_at__range=(today_start, today_end)
    )
    today_total = today_logs.count()
    today_vip = today_logs.filter(was_vip_at_time=True).count()
    today_normal = today_total - today_vip
    today_unique = (
        today_logs.exclude(customer__isnull=True)
        .values("customer")
        .distinct()
        .count()
    )

    all_time_total = RecognitionLog.objects.count()
    all_time_vip = RecognitionLog.objects.filter(was_vip_at_time=True).count()

    recent_logs = (
        RecognitionLog.objects.select_related("customer", "camera")
        .order_by("-created_at")[:50]
    )

    hourly_data = []
    for hour in range(24):
        h_start = today_start + timezone.timedelta(hours=hour)
        h_end = today_start + timezone.timedelta(hours=hour + 1)
        hourly_data.append(
            RecognitionLog.objects.filter(created_at__range=(h_start, h_end)).count()
        )

    context = {
        "today_total": today_total,
        "today_vip": today_vip,
        "today_normal": today_normal,
        "today_unique_customers": today_unique,
        "all_time_total": all_time_total,
        "all_time_vip": all_time_vip,
        "recent_logs": recent_logs,
        "hourly_data": hourly_data,
    }
    return render(request, "face_recognition_app/recognition_dashboard.html", context)


@login_required
def recognition_dashboard_api(request):
    today = timezone.now().date()
    today_start = timezone.make_aware(
        timezone.datetime.combine(today, timezone.datetime.min.time())
    )
    today_end = timezone.make_aware(
        timezone.datetime.combine(today, timezone.datetime.max.time())
    )

    today_logs = RecognitionLog.objects.filter(created_at__range=(today_start, today_end))
    today_total = today_logs.count()
    today_vip = today_logs.filter(was_vip_at_time=True).count()

    latest = (
        RecognitionLog.objects.select_related("customer")
        .order_by("-created_at")[:10]
    )
    latest_list = []
    for log in latest:
        latest_list.append({
            "id": log.id,
            "customer_name": log.customer.name if log.customer else "Unknown",
            "confidence": round(log.confidence, 2) if log.confidence else None,
            "was_vip": log.was_vip_at_time,
            "camera_name": log.camera.name if log.camera else "Default",
            "timestamp": log.created_at.strftime("%H:%M:%S"),
            "snapshot_url": log.snapshot.url if log.snapshot else None,
        })

    return JsonResponse({
        "today_total": today_total,
        "today_vip": today_vip,
        "today_normal": today_total - today_vip,
        "latest": latest_list,
    })
"@

# Write dashboard views as separate file
$dashboardPath = "$appDir\views_dashboard.py"
Backup-File $dashboardPath
$dashboardView | Out-File -Encoding ASCII $dashboardPath
Write-Host "[WRITE] Dashboard views: $dashboardPath" -ForegroundColor Green

# Syntax check the new file
try {
    python -m py_compile $dashboardPath
    Write-Host "[OK] Syntax check passed: $dashboardPath" -ForegroundColor Green
}
catch {
    Write-Host "[FAIL] Syntax error in $dashboardPath" -ForegroundColor Red
    Write-Host $_
    exit 1
}

Write-Host "[OK] Syntax check passed: $dashboardPath" -ForegroundColor Green

# ------------------------------------------------------------------
# 2. ADD IMPORT to views.py (if not already present)
# ------------------------------------------------------------------
$viewsPath = "$appDir\views.py"
Backup-File $viewsPath

$viewsContent = Get-Content $viewsPath -Raw
if ($viewsContent -notmatch "views_dashboard") {
    # Add import at the end of imports section
    $importLine = "from .views_dashboard import recognition_dashboard, recognition_dashboard_api"

    # Find a good place to insert (after existing imports)
    if ($viewsContent -match "(from .models import .+)" -or $viewsContent -match "(from django\.contrib import .+)") {
        $viewsContent = $viewsContent -replace "(from .+ import .+\n)", "`$1$importLine`n"
    } else {
        $viewsContent = $importLine + "`n" + $viewsContent
    }

    $viewsContent | Out-File -Encoding ASCII $viewsPath
    Write-Host "[UPDATE] Added dashboard import to $viewsPath" -ForegroundColor Green
} else {
    Write-Host "[SKIP] Dashboard import already present" -ForegroundColor Yellow
}

# ------------------------------------------------------------------
# 3. DASHBOARD TEMPLATE
# ------------------------------------------------------------------
$dashboardTemplate = @'
{% extends "base.html" %}

{% block title %}Recognition Dashboard{% endblock %}

{% block content %}
<div class="content-wrapper">
  <section class="content-header">
    <h1>Recognition Dashboard</h1>
    <ol class="breadcrumb">
      <li><a href="{% url 'dashboard' %}">Home</a></li>
      <li class="active">Recognition Dashboard</li>
    </ol>
  </section>

  <section class="content">
    <!-- Stat Cards -->
    <div class="row">
      <div class="col-lg-3 col-xs-6">
        <div class="small-box bg-aqua">
          <div class="inner">
            <h3 id="stat-total">{{ today_total }}</h3>
            <p>Today's Recognitions</p>
          </div>
          <div class="icon"><i class="fa fa-users"></i></div>
        </div>
      </div>
      <div class="col-lg-3 col-xs-6">
        <div class="small-box bg-yellow">
          <div class="inner">
            <h3 id="stat-vip">{{ today_vip }}</h3>
            <p>VIP Visits Today</p>
          </div>
          <div class="icon"><i class="fa fa-star"></i></div>
        </div>
      </div>
      <div class="col-lg-3 col-xs-6">
        <div class="small-box bg-green">
          <div class="inner">
            <h3 id="stat-normal">{{ today_normal }}</h3>
            <p>Normal Visits Today</p>
          </div>
          <div class="icon"><i class="fa fa-user"></i></div>
        </div>
      </div>
      <div class="col-lg-3 col-xs-6">
        <div class="small-box bg-red">
          <div class="inner">
            <h3>{{ today_unique_customers }}</h3>
            <p>Unique Customers Today</p>
          </div>
          <div class="icon"><i class="fa fa-id-card"></i></div>
        </div>
      </div>
    </div>

    <!-- Chart + Live Feed -->
    <div class="row">
      <div class="col-md-8">
        <div class="box box-primary">
          <div class="box-header with-border">
            <h3 class="box-title">Today's Recognition Activity (Hourly)</h3>
          </div>
          <div class="box-body">
            <canvas id="hourlyChart" height="100"></canvas>
          </div>
        </div>
      </div>
      <div class="col-md-4">
        <div class="box box-warning">
          <div class="box-header with-border">
            <h3 class="box-title">Live Feed <small class="text-muted">(auto-refresh)</small></h3>
          </div>
          <div class="box-body" id="live-feed" style="max-height: 400px; overflow-y: auto;">
            {% for log in recent_logs|slice:":10" %}
            <div class="media" style="margin-bottom: 10px; padding: 8px; border-radius: 6px; background: {% if log.was_vip_at_time %}#fff8e1{% else %}#f9f9f9{% endif %};">
              <div class="media-left">
                {% if log.snapshot %}
                <img src="{{ log.snapshot.url }}" style="width: 48px; height: 48px; object-fit: cover; border-radius: 4px;" alt="snapshot">
                {% else %}
                <div style="width: 48px; height: 48px; background: #ddd; border-radius: 4px; display: flex; align-items: center; justify-content: center;">
                  <i class="fa fa-user"></i>
                </div>
                {% endif %}
              </div>
              <div class="media-body">
                <h5 class="media-heading" style="margin: 0;">
                  {% if log.customer %}
                    {{ log.customer.name }}
                    {% if log.was_vip_at_time %}<span class="label label-warning">VIP</span>{% endif %}
                  {% else %}
                    <span class="text-muted">Unknown</span>
                  {% endif %}
                </h5>
                <small class="text-muted">
                  {{ log.created_at|time:"H:i:s" }} &middot;
                  {{ log.camera.name|default:"Default" }} &middot;
                  {% if log.confidence %}Confidence: {{ log.confidence|floatformat:2 }}{% endif %}
                </small>
              </div>
            </div>
            {% empty %}
            <p class="text-muted text-center">No recognitions yet today.</p>
            {% endfor %}
          </div>
        </div>
      </div>
    </div>

    <!-- Recent Recognitions Table -->
    <div class="row">
      <div class="col-xs-12">
        <div class="box">
          <div class="box-header">
            <h3 class="box-title">Recent Recognitions (Last 50)</h3>
          </div>
          <div class="box-body table-responsive no-padding">
            <table class="table table-hover">
              <thead>
                <tr>
                  <th>Time</th>
                  <th>Customer</th>
                  <th>VIP?</th>
                  <th>Confidence</th>
                  <th>Camera</th>
                  <th>WhatsApp Notified?</th>
                  <th>Snapshot</th>
                </tr>
              </thead>
              <tbody>
                {% for log in recent_logs %}
                <tr>
                  <td>{{ log.created_at|date:"Y-m-d H:i:s" }}</td>
                  <td>
                    {% if log.customer %}
                      <a href="{% url 'customer_detail' log.customer.id %}">{{ log.customer.name }}</a>
                    {% else %}
                      <span class="text-muted">Unknown</span>
                    {% endif %}
                  </td>
                  <td>
                    {% if log.was_vip_at_time %}
                      <span class="label label-warning">VIP</span>
                    {% else %}
                      <span class="label label-default">No</span>
                    {% endif %}
                  </td>
                  <td>{{ log.confidence|floatformat:2|default:"-" }}</td>
                  <td>{{ log.camera.name|default:"Default" }}</td>
                  <td>
                    {% if log.whatsapp_notified %}
                      <span class="label label-success"><i class="fa fa-check"></i> Sent</span>
                    {% else %}
                      <span class="label label-default">-</span>
                    {% endif %}
                  </td>
                  <td>
                    {% if log.snapshot %}
                      <a href="{{ log.snapshot.url }}" target="_blank"><img src="{{ log.snapshot.url }}" style="height: 40px; border-radius: 4px;"></a>
                    {% else %}-{% endif %}
                  </td>
                </tr>
                {% endfor %}
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
  </section>
</div>
{% endblock %}

{% block extra_js %}
<script src="https://cdn.jsdelivr.net/npm/chart.js@3.9.1/dist/chart.min.js"></script>
<script>
const ctx = document.getElementById('hourlyChart').getContext('2d');
const hourlyData = {{ hourly_data|safe }};
const labels = Array.from({length: 24}, (_, i) => String(i).padStart(2, '0') + ':00');

new Chart(ctx, {
  type: 'bar',
  data: {
    labels: labels,
    datasets: [{
      label: 'Recognitions',
      data: hourlyData,
      backgroundColor: 'rgba(0, 123, 255, 0.6)',
      borderColor: 'rgba(0, 123, 255, 1)',
      borderWidth: 1
    }]
  },
  options: {
    responsive: true,
    scales: { y: { beginAtZero: true, ticks: { stepSize: 1 } } }
  }
});

const LIVE_FEED_URL = "{% url 'recognition_dashboard_api' %}";

async function refreshLiveFeed() {
  try {
    const res = await fetch(LIVE_FEED_URL);
    if (!res.ok) return;
    const data = await res.json();

    document.getElementById('stat-total').textContent = data.today_total;
    document.getElementById('stat-vip').textContent = data.today_vip;
    document.getElementById('stat-normal').textContent = data.today_normal;

    const feedContainer = document.getElementById('live-feed');
    if (data.latest.length === 0) {
      feedContainer.innerHTML = '<p class="text-muted text-center">No recognitions yet today.</p>';
      return;
    }

    feedContainer.innerHTML = data.latest.map(log => `
      <div class="media" style="margin-bottom: 10px; padding: 8px; border-radius: 6px; background: ${log.was_vip ? '#fff8e1' : '#f9f9f9'};">
        <div class="media-left">
          ${log.snapshot_url
            ? `<img src="${log.snapshot_url}" style="width: 48px; height: 48px; object-fit: cover; border-radius: 4px;">`
            : `<div style="width: 48px; height: 48px; background: #ddd; border-radius: 4px; display: flex; align-items: center; justify-content: center;"><i class="fa fa-user"></i></div>`
          }
        </div>
        <div class="media-body">
          <h5 class="media-heading" style="margin: 0;">
            ${log.customer_name}
            ${log.was_vip ? '<span class="label label-warning">VIP</span>' : ''}
          </h5>
          <small class="text-muted">
            ${log.timestamp} &middot; ${log.camera_name}
            ${log.confidence ? '&middot; Confidence: ' + log.confidence : ''}
          </small>
        </div>
      </div>
    `).join('');
  } catch (e) {
    console.debug('Dashboard refresh failed:', e);
  }
}

setInterval(refreshLiveFeed, 5000);
</script>
{% endblock %}
'@

Write-TemplateFile "$templateDir\recognition_dashboard.html" $dashboardTemplate

# ------------------------------------------------------------------
# 4. URL PATTERNS (append to urls.py)
# ------------------------------------------------------------------
$dashboardUrls = @"

    # ITEM 5: Recognition Dashboard
    path("recognition-dashboard/", views_dashboard.recognition_dashboard, name="recognition_dashboard"),
    path("recognition-dashboard/api/", views_dashboard.recognition_dashboard_api, name="recognition_dashboard_api"),
"@

$urlsPath = "$appDir\urls.py"
Backup-File $urlsPath

$urlsContent = Get-Content $urlsPath -Raw
if ($urlsContent -notmatch "recognition_dashboard") {
    $urlsContent = $urlsContent -replace "(\])", "$dashboardUrls`$1"
    $urlsContent | Out-File -Encoding ASCII $urlsPath
    Write-Host "[APPEND] Dashboard URLs added to $urlsPath" -ForegroundColor Green
} else {
    Write-Host "[SKIP] Dashboard URLs already present" -ForegroundColor Yellow
}

# ------------------------------------------------------------------
# 5. FINAL CHECK
# ------------------------------------------------------------------
Write-Host "`n=== Running Django system check ===" -ForegroundColor Yellow
python manage.py check face_recognition_app
if ($LASTEXITCODE -ne 0) {
    Write-Host "[FAIL] Django check failed" -ForegroundColor Red
    exit 1
}

Write-Host "`n=== Recognition Dashboard installed successfully ===" -ForegroundColor Green
Write-Host "New URLs:" -ForegroundColor Cyan
Write-Host "  /recognition-dashboard/     - Dashboard page" -ForegroundColor White
Write-Host "  /recognition-dashboard/api/ - JSON API for live refresh" -ForegroundColor White