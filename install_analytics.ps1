# install_analytics.ps1
# Analytics Dashboard - daily, weekly, monthly charts
# Run from: D:\Downloads\vip-recognition-core\vip-recognition\dashboard\

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

function Write-PythonFile($path, $content) {
    Backup-File $path
    $dir = Split-Path $path
    if (!(Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $content | Out-File -Encoding ASCII $path
    Write-Host "[WRITE] $path" -ForegroundColor Green
    $syntaxCheck = python -c "import py_compile; py_compile.compile('$path', doraise=True)" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[FAIL] Syntax error in $path" -ForegroundColor Red
        Write-Host $syntaxCheck
        exit 1
    }
    Write-Host "[OK] Syntax check passed: $path" -ForegroundColor Green
}

function Write-TemplateFile($path, $content) {
    Backup-File $path
    $dir = Split-Path $path
    if (!(Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $content | Out-File -Encoding ASCII $path
    Write-Host "[WRITE] $path" -ForegroundColor Green
}

Write-Host "=== Installing Analytics Dashboard ===" -ForegroundColor Yellow

# ------------------------------------------------------------------
# 1. ANALYTICS VIEW
# ------------------------------------------------------------------
$analyticsView = @"

# ============================================================
# ANALYTICS DASHBOARD
# ============================================================

from django.db.models import Count, Q
from django.utils import timezone
from datetime import timedelta


@login_required
def analytics_dashboard(request):
    today = timezone.now().date()

    # --- Daily (last 7 days) ---
    daily_labels = []
    daily_total = []
    daily_vip = []
    for i in range(6, -1, -1):
        day = today - timedelta(days=i)
        daily_labels.append(day.strftime("%a"))
        day_start = timezone.make_aware(timezone.datetime.combine(day, timezone.datetime.min.time()))
        day_end = timezone.make_aware(timezone.datetime.combine(day, timezone.datetime.max.time()))
        logs = RecognitionLog.objects.filter(recognized_at__range=(day_start, day_end))
        daily_total.append(logs.count())
        daily_vip.append(logs.filter(was_vip_at_time=True).count())

    # --- Weekly (last 4 weeks) ---
    weekly_labels = []
    weekly_total = []
    weekly_vip = []
    for i in range(3, -1, -1):
        week_start = today - timedelta(weeks=i+1)
        week_end = today - timedelta(weeks=i)
        weekly_labels.append("Week " + str(4-i))
        logs = RecognitionLog.objects.filter(recognized_at__date__gte=week_start, recognized_at__date__lt=week_end)
        weekly_total.append(logs.count())
        weekly_vip.append(logs.filter(was_vip_at_time=True).count())

    # --- Monthly (last 6 months) ---
    monthly_labels = []
    monthly_total = []
    monthly_vip = []
    for i in range(5, -1, -1):
        month = today.replace(day=1) - timedelta(days=i*30)
        monthly_labels.append(month.strftime("%b"))
        month_start = month.replace(day=1)
        next_month = (month.replace(day=28) + timedelta(days=4)).replace(day=1)
        month_start_dt = timezone.make_aware(timezone.datetime.combine(month_start, timezone.datetime.min.time()))
        month_end_dt = timezone.make_aware(timezone.datetime.combine(next_month, timezone.datetime.min.time()))
        logs = RecognitionLog.objects.filter(recognized_at__range=(month_start_dt, month_end_dt))
        monthly_total.append(logs.count())
        monthly_vip.append(logs.filter(was_vip_at_time=True).count())

    # --- Summary stats ---
    total_all_time = RecognitionLog.objects.count()
    total_vip_all_time = RecognitionLog.objects.filter(was_vip_at_time=True).count()
    total_unknown_all_time = RecognitionLog.objects.filter(customer__isnull=True).count()
    vip_percentage = round((total_vip_all_time / total_all_time * 100), 1) if total_all_time > 0 else 0

    # Top customers by visit count
    top_customers = (
        RecognitionLog.objects.exclude(customer__isnull=True)
        .values("customer__name", "customer__id")
        .annotate(visit_count=Count("id"))
        .order_by("-visit_count")[:10]
    )

    context = {
        "daily_labels": daily_labels,
        "daily_total": daily_total,
        "daily_vip": daily_vip,
        "weekly_labels": weekly_labels,
        "weekly_total": weekly_total,
        "weekly_vip": weekly_vip,
        "monthly_labels": monthly_labels,
        "monthly_total": monthly_total,
        "monthly_vip": monthly_vip,
        "total_all_time": total_all_time,
        "total_vip_all_time": total_vip_all_time,
        "total_unknown_all_time": total_unknown_all_time,
        "vip_percentage": vip_percentage,
        "top_customers": top_customers,
    }
    return render(request, "face_recognition_app/analytics_dashboard.html", context)
"@

$viewsPath = "$appDir\views.py"
Backup-File $viewsPath
Add-Content -Path $viewsPath -Value $analyticsView -Encoding ASCII
Write-Host "[APPEND] Analytics view added" -ForegroundColor Green

# ------------------------------------------------------------------
# 2. ANALYTICS TEMPLATE
# ------------------------------------------------------------------
$analyticsTemplate = @'
{% extends "base.html" %}

{% block title %}Analytics Dashboard{% endblock %}

{% block content %}
<div class="content-wrapper">
  <section class="content-header">
    <h1>Analytics Dashboard</h1>
    <ol class="breadcrumb">
      <li><a href="{% url 'dashboard' %}">Home</a></li>
      <li class="active">Analytics</li>
    </ol>
  </section>

  <section class="content">
    <!-- Summary Cards -->
    <div class="row">
      <div class="col-lg-3 col-xs-6">
        <div class="small-box bg-aqua">
          <div class="inner">
            <h3>{{ total_all_time }}</h3>
            <p>Total Recognitions</p>
          </div>
          <div class="icon"><i class="fa fa-users"></i></div>
        </div>
      </div>
      <div class="col-lg-3 col-xs-6">
        <div class="small-box bg-yellow">
          <div class="inner">
            <h3>{{ total_vip_all_time }}</h3>
            <p>Total VIP Visits</p>
          </div>
          <div class="icon"><i class="fa fa-star"></i></div>
        </div>
      </div>
      <div class="col-lg-3 col-xs-6">
        <div class="small-box bg-red">
          <div class="inner">
            <h3>{{ total_unknown_all_time }}</h3>
            <p>Unknown Visitors</p>
          </div>
          <div class="icon"><i class="fa fa-user-secret"></i></div>
        </div>
      </div>
      <div class="col-lg-3 col-xs-6">
        <div class="small-box bg-green">
          <div class="inner">
            <h3>{{ vip_percentage }}%</h3>
            <p>VIP Percentage</p>
          </div>
          <div class="icon"><i class="fa fa-percent"></i></div>
        </div>
      </div>
    </div>

    <!-- Charts Row -->
    <div class="row">
      <div class="col-md-4">
        <div class="box box-primary">
          <div class="box-header"><h3 class="box-title">Daily (Last 7 Days)</h3></div>
          <div class="box-body"><canvas id="dailyChart" height="200"></canvas></div>
        </div>
      </div>
      <div class="col-md-4">
        <div class="box box-success">
          <div class="box-header"><h3 class="box-title">Weekly (Last 4 Weeks)</h3></div>
          <div class="box-body"><canvas id="weeklyChart" height="200"></canvas></div>
        </div>
      </div>
      <div class="col-md-4">
        <div class="box box-info">
          <div class="box-header"><h3 class="box-title">Monthly (Last 6 Months)</h3></div>
          <div class="box-body"><canvas id="monthlyChart" height="200"></canvas></div>
        </div>
      </div>
    </div>

    <!-- Top Customers -->
    <div class="row">
      <div class="col-md-6">
        <div class="box">
          <div class="box-header"><h3 class="box-title">Top 10 Customers by Visits</h3></div>
          <div class="box-body table-responsive">
            <table class="table table-hover">
              <thead><tr><th>#</th><th>Customer</th><th>Visits</th></tr></thead>
              <tbody>
                {% for c in top_customers %}
                <tr>
                  <td>{{ forloop.counter }}</td>
                  <td><a href="{% url 'customer_visit_history' c.customer__id %}">{{ c.customer__name }}</a></td>
                  <td><span class="badge bg-blue">{{ c.visit_count }}</span></td>
                </tr>
                {% empty %}
                <tr><td colspan="3" class="text-center text-muted">No data yet.</td></tr>
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
const chartOptions = {
  responsive: true,
  scales: { y: { beginAtZero: true, ticks: { stepSize: 1 } } }
};

new Chart(document.getElementById('dailyChart'), {
  type: 'line',
  data: {
    labels: {{ daily_labels|safe }},
    datasets: [
      { label: 'Total', data: {{ daily_total|safe }}, borderColor: 'rgba(0,123,255,1)', backgroundColor: 'rgba(0,123,255,0.1)', fill: true, tension: 0.4 },
      { label: 'VIP', data: {{ daily_vip|safe }}, borderColor: 'rgba(255,193,7,1)', backgroundColor: 'rgba(255,193,7,0.1)', fill: true, tension: 0.4 }
    ]
  },
  options: chartOptions
});

new Chart(document.getElementById('weeklyChart'), {
  type: 'bar',
  data: {
    labels: {{ weekly_labels|safe }},
    datasets: [
      { label: 'Total', data: {{ weekly_total|safe }}, backgroundColor: 'rgba(40,167,69,0.6)' },
      { label: 'VIP', data: {{ weekly_vip|safe }}, backgroundColor: 'rgba(255,193,7,0.6)' }
    ]
  },
  options: chartOptions
});

new Chart(document.getElementById('monthlyChart'), {
  type: 'bar',
  data: {
    labels: {{ monthly_labels|safe }},
    datasets: [
      { label: 'Total', data: {{ monthly_total|safe }}, backgroundColor: 'rgba(23,162,184,0.6)' },
      { label: 'VIP', data: {{ monthly_vip|safe }}, backgroundColor: 'rgba(255,193,7,0.6)' }
    ]
  },
  options: chartOptions
});
</script>
{% endblock %}
'@

Write-TemplateFile "$templateDir\analytics_dashboard.html" $analyticsTemplate

# ------------------------------------------------------------------
# 3. URLS
# ------------------------------------------------------------------
$analyticsUrls = @"

    # Analytics
    path("analytics/", views.analytics_dashboard, name="analytics_dashboard"),
"@

$urlsPath = "$appDir\urls.py"
Backup-File $urlsPath
$urlsContent = Get-Content $urlsPath -Raw
if ($urlsContent -notmatch "analytics_dashboard") {
    $urlsContent = $urlsContent -replace "(\])", "$analyticsUrls`$1"
    $urlsContent | Out-File -Encoding ASCII $urlsPath
    Write-Host "[APPEND] Analytics URL added" -ForegroundColor Green
} else {
    Write-Host "[SKIP] Analytics URL already present" -ForegroundColor Yellow
}

# ------------------------------------------------------------------
# 4. FINAL CHECK
# ------------------------------------------------------------------
Write-Host "`n=== Running Django system check ===" -ForegroundColor Yellow
python manage.py check face_recognition_app
if ($LASTEXITCODE -ne 0) {
    Write-Host "[FAIL] Django check failed" -ForegroundColor Red
    exit 1
}

Write-Host "`n=== Analytics Dashboard installed ===" -ForegroundColor Green
Write-Host "New URL:" -ForegroundColor Cyan
Write-Host "  /analytics/  - Full analytics with daily/weekly/monthly charts" -ForegroundColor White
