# install_settings_camera.ps1
# Settings page + Camera management installer - Items 9, 10, 11
# Run from: D:\Downloads\vip-recognition-core\vip-recognition\dashboard\
# Requires: face_recognition_app with SystemSettings and Camera models

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

Write-Host "=== Installing Settings + Camera Management ===" -ForegroundColor Yellow

# ------------------------------------------------------------------
# 1. SETTINGS VIEW (append to views.py)
# ------------------------------------------------------------------
$settingsView = @"

# ============================================================
# ITEMS 9-11: SETTINGS & MULTI-CAMERA
# ============================================================

from django.contrib import messages
from django.shortcuts import redirect


@login_required
def settings_page(request):
    settings_obj = SystemSettings.get_settings()

    if request.method == "POST":
        try:
            settings_obj.recognition_threshold = float(
                request.POST.get("recognition_threshold", 0.65)
            )
            settings_obj.vip_minimum_purchase = Decimal(
                request.POST.get("vip_minimum_purchase", "5000.00")
            )

            camera_id = request.POST.get("default_camera")
            if camera_id:
                settings_obj.default_camera = Camera.objects.filter(id=camera_id).first()
            else:
                settings_obj.default_camera = None

            settings_obj.recognition_threshold = max(
                0.0, min(1.0, settings_obj.recognition_threshold)
            )

            settings_obj.save()
            messages.success(request, "Settings saved successfully.")
        except Exception as e:
            messages.error(request, "Error saving settings: " + str(e))

        return redirect("settings_page")

    cameras = Camera.objects.all().order_by("name")
    context = {
        "settings": settings_obj,
        "cameras": cameras,
        "threshold_min": 0.3,
        "threshold_max": 0.9,
    }
    return render(request, "face_recognition_app/settings.html", context)


@login_required
def camera_list(request):
    cameras = Camera.objects.all().order_by("name")
    settings_obj = SystemSettings.get_settings()
    return render(request, "face_recognition_app/camera_list.html", {
        "cameras": cameras,
        "settings": settings_obj,
    })


@login_required
def camera_add(request):
    if request.method == "POST":
        name = request.POST.get("name", "").strip()
        source_type = request.POST.get("source_type", "webcam")
        source_url = request.POST.get("source_url", "").strip()
        is_active = request.POST.get("is_active") == "on"

        if not name:
            messages.error(request, "Camera name is required.")
            return redirect("camera_add")

        Camera.objects.create(
            name=name,
            source_type=source_type,
            source_url=source_url if source_url else None,
            is_active=is_active,
        )
        messages.success(request, "Camera '" + name + "' added.")
        return redirect("camera_list")

    source_types = [
        ("webcam", "Webcam / USB"),
        ("rtsp", "RTSP Stream"),
        ("dvr", "DVR / NVR"),
        ("ip", "IP Camera"),
    ]
    return render(request, "face_recognition_app/camera_form.html", {
        "source_types": source_types,
    })


@login_required
def camera_edit(request, camera_id):
    camera = get_object_or_404(Camera, id=camera_id)
    if request.method == "POST":
        camera.name = request.POST.get("name", "").strip()
        camera.source_type = request.POST.get("source_type", "webcam")
        camera.source_url = request.POST.get("source_url", "").strip() or None
        camera.is_active = request.POST.get("is_active") == "on"
        camera.save()
        messages.success(request, "Camera '" + camera.name + "' updated.")
        return redirect("camera_list")

    source_types = [
        ("webcam", "Webcam / USB"),
        ("rtsp", "RTSP Stream"),
        ("dvr", "DVR / NVR"),
        ("ip", "IP Camera"),
    ]
    return render(request, "face_recognition_app/camera_form.html", {
        "camera": camera,
        "source_types": source_types,
    })


@login_required
def camera_delete(request, camera_id):
    camera = get_object_or_404(Camera, id=camera_id)
    if request.method == "POST":
        name = camera.name
        camera.delete()
        messages.success(request, "Camera '" + name + "' deleted.")
        return redirect("camera_list")
    return render(request, "face_recognition_app/camera_confirm_delete.html", {
        "camera": camera,
    })
"@

$viewsPath = "$appDir\views.py"
Backup-File $viewsPath
Add-Content -Path $viewsPath -Value $settingsView -Encoding ASCII
Write-Host "[APPEND] Settings + Camera views added to $viewsPath" -ForegroundColor Green

$syntaxCheck = python -c "import py_compile; py_compile.compile('$viewsPath', doraise=True)" 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "[FAIL] Syntax error after appending settings views" -ForegroundColor Red
    Write-Host $syntaxCheck
    exit 1
}
Write-Host "[OK] Syntax check passed: $viewsPath" -ForegroundColor Green

# ------------------------------------------------------------------
# 2. SETTINGS TEMPLATE
# ------------------------------------------------------------------
$settingsTemplate = @'
{% extends "base.html" %}

{% block title %}Face Recognition Settings{% endblock %}

{% block content %}
<div class="content-wrapper">
  <section class="content-header">
    <h1>Face Recognition Settings</h1>
    <ol class="breadcrumb">
      <li><a href="{% url 'dashboard' %}">Home</a></li>
      <li class="active">Settings</li>
    </ol>
  </section>

  <section class="content">
    <div class="row">
      <div class="col-md-6">
        <div class="box box-primary">
          <div class="box-header with-border">
            <h3 class="box-title"><i class="fa fa-sliders"></i> Recognition Parameters</h3>
          </div>
          <form method="post">
            {% csrf_token %}
            <div class="box-body">
              <div class="form-group">
                <label for="recognition_threshold">Recognition Threshold</label>
                <input type="range" class="form-control" id="threshold-slider"
                       min="{{ threshold_min }}" max="{{ threshold_max }}" step="0.01"
                       value="{{ settings.recognition_threshold }}"
                       oninput="document.getElementById('threshold-value').textContent = this.value">
                <p class="help-block">
                  Current: <strong id="threshold-value">{{ settings.recognition_threshold }}</strong>
                  - Lower = stricter matching. Recommended: 0.60 - 0.70
                </p>
                <input type="hidden" name="recognition_threshold" id="threshold-input"
                       value="{{ settings.recognition_threshold }}">
              </div>

              <div class="form-group">
                <label for="vip_minimum_purchase">VIP Minimum Purchase (BDT)</label>
                <input type="number" class="form-control" name="vip_minimum_purchase"
                       id="vip_minimum_purchase" step="0.01" min="0"
                       value="{{ settings.vip_minimum_purchase }}">
                <p class="help-block">
                  Customers with total purchase >= this amount are treated as VIP.
                </p>
              </div>

              <div class="form-group">
                <label for="default_camera">Default Camera for Live Feed</label>
                <select class="form-control" name="default_camera" id="default_camera">
                  <option value="">-- System Default (Webcam 0) --</option>
                  {% for cam in cameras %}
                  <option value="{{ cam.id }}" {% if settings.default_camera.id == cam.id %}selected{% endif %}>
                    {{ cam.name }} ({{ cam.source_type }})
                  </option>
                  {% endfor %}
                </select>
                <p class="help-block">
                  <a href="{% url 'camera_list' %}">Manage cameras -></a>
                </p>
              </div>
            </div>
            <div class="box-footer">
              <button type="submit" class="btn btn-primary">Save Settings</button>
            </div>
          </form>
        </div>
      </div>

      <div class="col-md-6">
        <div class="box box-info">
          <div class="box-header with-border">
            <h3 class="box-title"><i class="fa fa-info-circle"></i> Current Configuration</h3>
          </div>
          <div class="box-body">
            <table class="table table-bordered">
              <tr>
                <th>Recognition Threshold</th>
                <td><code>{{ settings.recognition_threshold }}</code></td>
              </tr>
              <tr>
                <th>VIP Minimum Purchase</th>
                <td>{{ settings.vip_minimum_purchase }} BDT</td>
              </tr>
              <tr>
                <th>Default Camera</th>
                <td>
                  {% if settings.default_camera %}
                    {{ settings.default_camera.name }}
                  {% else %}
                    <span class="text-muted">System Default (Webcam 0)</span>
                  {% endif %}
                </td>
              </tr>
              <tr>
                <th>Last Updated</th>
                <td>{{ settings.updated_at|date:"Y-m-d H:i:s" }}</td>
              </tr>
            </table>
          </div>
        </div>

        <div class="box box-warning">
          <div class="box-header with-border">
            <h3 class="box-title"><i class="fa fa-video-camera"></i> Camera Management</h3>
          </div>
          <div class="box-body">
            <p>Manage multiple camera sources (webcam, RTSP, DVR, IP cameras).</p>
            <a href="{% url 'camera_list' %}" class="btn btn-warning">
              <i class="fa fa-list"></i> View All Cameras
            </a>
            <a href="{% url 'camera_add' %}" class="btn btn-success">
              <i class="fa fa-plus"></i> Add Camera
            </a>
          </div>
        </div>
      </div>
    </div>
  </section>
</div>
{% endblock %}

{% block extra_js %}
<script>
document.getElementById('threshold-slider').addEventListener('input', function() {
  document.getElementById('threshold-input').value = this.value;
});
</script>
{% endblock %}
'@

Write-TemplateFile "$templateDir\settings.html" $settingsTemplate

# ------------------------------------------------------------------
# 3. CAMERA LIST TEMPLATE
# ------------------------------------------------------------------
$cameraListTemplate = @'
{% extends "base.html" %}

{% block title %}Cameras{% endblock %}

{% block content %}
<div class="content-wrapper">
  <section class="content-header">
    <h1>Camera Management</h1>
    <ol class="breadcrumb">
      <li><a href="{% url 'dashboard' %}">Home</a></li>
      <li><a href="{% url 'settings_page' %}">Settings</a></li>
      <li class="active">Cameras</li>
    </ol>
  </section>

  <section class="content">
    <div class="box">
      <div class="box-header">
        <h3 class="box-title">All Cameras</h3>
        <div class="box-tools">
          <a href="{% url 'camera_add' %}" class="btn btn-success btn-sm">
            <i class="fa fa-plus"></i> Add Camera
          </a>
        </div>
      </div>
      <div class="box-body table-responsive no-padding">
        <table class="table table-hover">
          <thead>
            <tr>
              <th>ID</th>
              <th>Name</th>
              <th>Type</th>
              <th>Source URL / Index</th>
              <th>Status</th>
              <th>Default?</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody>
            {% for cam in cameras %}
            <tr>
              <td>{{ cam.id }}</td>
              <td>{{ cam.name }}</td>
              <td><span class="label label-info">{{ cam.source_type }}</span></td>
              <td><code>{{ cam.source_url|default:"0" }}</code></td>
              <td>
                {% if cam.is_active %}
                  <span class="label label-success">Active</span>
                {% else %}
                  <span class="label label-default">Inactive</span>
                {% endif %}
              </td>
              <td>
                {% if settings.default_camera.id == cam.id %}
                  <span class="label label-primary">Default</span>
                {% else %}-{% endif %}
              </td>
              <td>
                <a href="{% url 'camera_with_id' cam.id %}" class="btn btn-xs btn-info" title="View Feed">
                  <i class="fa fa-eye"></i>
                </a>
                <a href="{% url 'video_feed_with_id' cam.id %}" class="btn btn-xs btn-default" title="Stream URL" target="_blank">
                  <i class="fa fa-video-camera"></i>
                </a>
                <a href="{% url 'camera_edit' cam.id %}" class="btn btn-xs btn-primary">
                  <i class="fa fa-edit"></i>
                </a>
                <a href="{% url 'camera_delete' cam.id %}" class="btn btn-xs btn-danger">
                  <i class="fa fa-trash"></i>
                </a>
              </td>
            </tr>
            {% empty %}
            <tr>
              <td colspan="7" class="text-center text-muted">
                No cameras configured. <a href="{% url 'camera_add' %}">Add one</a>.
              </td>
            </tr>
            {% endfor %}
          </tbody>
        </table>
      </div>
    </div>
  </section>
</div>
{% endblock %}
'@

Write-TemplateFile "$templateDir\camera_list.html" $cameraListTemplate

# ------------------------------------------------------------------
# 4. CAMERA FORM TEMPLATE
# ------------------------------------------------------------------
$cameraFormTemplate = @'
{% extends "base.html" %}

{% block title %}{% if camera %}Edit{% else %}Add{% endif %} Camera{% endblock %}

{% block content %}
<div class="content-wrapper">
  <section class="content-header">
    <h1>{% if camera %}Edit{% else %}Add{% endif %} Camera</h1>
    <ol class="breadcrumb">
      <li><a href="{% url 'dashboard' %}">Home</a></li>
      <li><a href="{% url 'camera_list' %}">Cameras</a></li>
      <li class="active">{% if camera %}Edit{% else %}Add{% endif %}</li>
    </ol>
  </section>

  <section class="content">
    <div class="row">
      <div class="col-md-6">
        <div class="box box-primary">
          <div class="box-header with-border">
            <h3 class="box-title">Camera Details</h3>
          </div>
          <form method="post">
            {% csrf_token %}
            <div class="box-body">
              <div class="form-group">
                <label for="name">Camera Name *</label>
                <input type="text" class="form-control" name="name" id="name"
                       value="{{ camera.name|default:'' }}" required>
              </div>
              <div class="form-group">
                <label for="source_type">Source Type</label>
                <select class="form-control" name="source_type" id="source_type">
                  {% for value, label in source_types %}
                  <option value="{{ value }}" {% if camera and camera.source_type == value %}selected{% endif %}>
                    {{ label }}
                  </option>
                  {% endfor %}
                </select>
              </div>
              <div class="form-group">
                <label for="source_url">Source URL / Device Index</label>
                <input type="text" class="form-control" name="source_url" id="source_url"
                       value="{{ camera.source_url|default:'' }}"
                       placeholder="e.g. 0 for webcam, rtsp://192.168.1.100:554/stream">
                <p class="help-block">
                  For webcam/USB: leave empty or enter 0, 1, etc.<br>
                  For RTSP/IP: enter the full URL.<br>
                  For DVR: enter the channel URL.
                </p>
              </div>
              <div class="form-group">
                <div class="checkbox">
                  <label>
                    <input type="checkbox" name="is_active" {% if not camera or camera.is_active %}checked{% endif %}>
                    Active
                  </label>
                </div>
              </div>
            </div>
            <div class="box-footer">
              <button type="submit" class="btn btn-primary">Save</button>
              <a href="{% url 'camera_list' %}" class="btn btn-default">Cancel</a>
            </div>
          </form>
        </div>
      </div>

      <div class="col-md-6">
        <div class="box box-info">
          <div class="box-header with-border">
            <h3 class="box-title">Source Type Guide</h3>
          </div>
          <div class="box-body">
            <table class="table table-bordered">
              <tr>
                <th>Webcam / USB</th>
                <td><code>0</code> or <code>1</code> (device index)</td>
              </tr>
              <tr>
                <th>RTSP Stream</th>
                <td><code>rtsp://user:pass@192.168.1.100:554/stream1</code></td>
              </tr>
              <tr>
                <th>IP Camera</th>
                <td><code>http://192.168.1.100:8080/video</code></td>
              </tr>
              <tr>
                <th>DVR / NVR</th>
                <td><code>rtsp://admin:password@dvr-ip:554/cam/realmonitor?channel=1&subtype=0</code></td>
              </tr>
            </table>
          </div>
        </div>
      </div>
    </div>
  </section>
</div>
{% endblock %}
'@

Write-TemplateFile "$templateDir\camera_form.html" $cameraFormTemplate

# ------------------------------------------------------------------
# 5. CAMERA DELETE CONFIRM TEMPLATE
# ------------------------------------------------------------------
$cameraDeleteTemplate = @'
{% extends "base.html" %}

{% block title %}Delete Camera{% endblock %}

{% block content %}
<div class="content-wrapper">
  <section class="content">
    <div class="row">
      <div class="col-md-6 col-md-offset-3">
        <div class="box box-danger">
          <div class="box-header with-border">
            <h3 class="box-title">Confirm Delete</h3>
          </div>
          <div class="box-body text-center">
            <p>Are you sure you want to delete camera <strong>"{{ camera.name }}"</strong>?</p>
            <p class="text-muted">This action cannot be undone.</p>
          </div>
          <div class="box-footer text-center">
            <form method="post" style="display: inline;">
              {% csrf_token %}
              <button type="submit" class="btn btn-danger">Delete</button>
            </form>
            <a href="{% url 'camera_list' %}" class="btn btn-default">Cancel</a>
          </div>
        </div>
      </div>
    </div>
  </section>
</div>
{% endblock %}
'@

Write-TemplateFile "$templateDir\camera_confirm_delete.html" $cameraDeleteTemplate

# ------------------------------------------------------------------
# 6. URL PATTERNS (append to urls.py)
# ------------------------------------------------------------------
$settingsUrls = @"

    # ITEMS 9-10: Settings
    path("settings/", views.settings_page, name="settings_page"),

    # ITEM 11: Multi-camera
    path("cameras/", views.camera_list, name="camera_list"),
    path("cameras/add/", views.camera_add, name="camera_add"),
    path("cameras/<int:camera_id>/edit/", views.camera_edit, name="camera_edit"),
    path("cameras/<int:camera_id>/delete/", views.camera_delete, name="camera_delete"),
    path("camera/<int:camera_id>/", views.camera, name="camera_with_id"),
    path("video-feed/<int:camera_id>/", views.video_feed, name="video_feed_with_id"),
"@

$urlsPath = "$appDir\urls.py"
Backup-File $urlsPath

$urlsContent = Get-Content $urlsPath -Raw
if ($urlsContent -notmatch "settings_page") {
    $urlsContent = $urlsContent -replace "(\])", "$settingsUrls`$1"
    $urlsContent | Out-File -Encoding ASCII $urlsPath
    Write-Host "[APPEND] Settings + Camera URLs added to $urlsPath" -ForegroundColor Green
} else {
    Write-Host "[SKIP] Settings + Camera URLs already present" -ForegroundColor Yellow
}

# ------------------------------------------------------------------
# 7. FINAL CHECK
# ------------------------------------------------------------------
Write-Host "`n=== Running Django system check ===" -ForegroundColor Yellow
python manage.py check face_recognition_app
if ($LASTEXITCODE -ne 0) {
    Write-Host "[FAIL] Django check failed" -ForegroundColor Red
    exit 1
}

Write-Host "`n=== Settings + Camera Management installed successfully ===" -ForegroundColor Green
Write-Host "New URLs:" -ForegroundColor Cyan
Write-Host "  /settings/              - Settings page" -ForegroundColor White
Write-Host "  /cameras/               - Camera list" -ForegroundColor White
Write-Host "  /cameras/add/           - Add camera" -ForegroundColor White
Write-Host "  /camera/<id>/           - View camera feed" -ForegroundColor White
Write-Host "  /video-feed/<id>/       - MJPEG stream for camera" -ForegroundColor White
