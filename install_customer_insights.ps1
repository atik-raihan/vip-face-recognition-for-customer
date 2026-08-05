# install_customer_insights.ps1
# Customer insights: visit history, recommendations, POS search
# Run from: D:\Downloads\vip-recognition-core\vip-recognition\dashboard\

$ErrorActionPreference = "Stop"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$appDir = "face_recognition_app"
$customerDir = "customers"
$templateDir = "templates\face_recognition_app"
$posDir = "templates\sales"

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

Write-Host "=== Installing Customer Insights + POS Search ===" -ForegroundColor Yellow

# ------------------------------------------------------------------
# 1. CUSTOMER VISIT HISTORY API
# ------------------------------------------------------------------
$visitHistoryView = @"

# ============================================================
# CUSTOMER INSIGHTS: Visit History, Recommendations
# ============================================================

from django.db.models import Count, Sum


@login_required
def customer_visit_history(request, customer_id):
    """Return last 10 visits for a customer."""
    from customers.models import Customer
    customer = get_object_or_404(Customer, id=customer_id)

    visits = (
        RecognitionLog.objects.filter(customer=customer)
        .order_by("-recognized_at")[:10]
    )

    history = []
    for v in visits:
        history.append({
            "id": v.id,
            "date": v.recognized_at.strftime("%Y-%m-%d %H:%M") if v.recognized_at else None,
            "confidence": round(v.confidence, 2) if v.confidence else None,
            "camera": v.camera_name or "Default",
            "snapshot": v.image_snapshot.url if v.image_snapshot else None,
        })

    return JsonResponse({
        "customer_name": customer.name,
        "total_visits": RecognitionLog.objects.filter(customer=customer).count(),
        "history": history,
    })


@login_required
def customer_purchase_recommendations(request, customer_id):
    """Return top 5 frequently bought products for a customer."""
    from customers.models import Customer
    customer = get_object_or_404(Customer, id=customer_id)

    try:
        from sales.models import SaleItem
        frequent = (
            SaleItem.objects.filter(sale__customer=customer)
            .values("product__name", "product__id")
            .annotate(count=Count("id"), total_qty=Sum("quantity"))
            .order_by("-count")[:5]
        )
        items = [
            {
                "product_id": f["product__id"],
                "name": f["product__name"],
                "times_bought": f["count"],
                "total_quantity": f["total_qty"],
            }
            for f in frequent
        ]
    except Exception:
        items = []

    return JsonResponse({
        "customer_name": customer.name,
        "recommendations": items,
    })
"@

$viewsPath = "$appDir\views.py"
Backup-File $viewsPath
Add-Content -Path $viewsPath -Value $visitHistoryView -Encoding ASCII
Write-Host "[APPEND] Customer insights views added" -ForegroundColor Green

# ------------------------------------------------------------------
# 2. POS SEARCH API
# ------------------------------------------------------------------
$posSearchView = @"

# ============================================================
# POS CUSTOMER SEARCH API
# ============================================================

@login_required
def pos_customer_search(request):
    """Search customers by name or phone for POS dropdown."""
    query = request.GET.get("q", "").strip()
    if not query or len(query) < 2:
        return JsonResponse({"results": []})

    from customers.models import Customer
    customers = Customer.objects.filter(
        models.Q(name__icontains=query) | models.Q(phone__icontains=query)
    )[:10]

    results = []
    for c in customers:
        results.append({
            "id": c.id,
            "name": c.name,
            "phone": getattr(c, "phone", "") or "",
            "total_purchase": getattr(c, "total_purchase", 0) or 0,
            "is_vip": getattr(c, "is_vip", False) or getattr(c, "vip", False),
        })

    return JsonResponse({"results": results})
"@

Add-Content -Path $viewsPath -Value $posSearchView -Encoding ASCII
Write-Host "[APPEND] POS search view added" -ForegroundColor Green

# ------------------------------------------------------------------
# 3. CUSTOMER VISIT HISTORY TEMPLATE (for dashboard popup)
# ------------------------------------------------------------------
$visitHistoryTemplate = @'
{% extends "base.html" %}

{% block title %}Customer Visit History{% endblock %}

{% block content %}
<div class="content-wrapper">
  <section class="content-header">
    <h1>Visit History: {{ customer.name }}</h1>
    <ol class="breadcrumb">
      <li><a href="{% url 'dashboard' %}">Home</a></li>
      <li><a href="{% url 'recognition_dashboard' %}">Dashboard</a></li>
      <li class="active">Visit History</li>
    </ol>
  </section>

  <section class="content">
    <div class="row">
      <div class="col-md-4">
        <div class="box box-primary">
          <div class="box-header">
            <h3 class="box-title">Customer Info</h3>
          </div>
          <div class="box-body">
            <p><strong>Name:</strong> {{ customer.name }}</p>
            <p><strong>Phone:</strong> {{ customer.phone|default:"-" }}</p>
            <p><strong>Total Purchase:</strong> BDT {{ customer.total_purchase|default:"0" }}</p>
            <p><strong>VIP:</strong> {% if customer.is_vip or customer.vip %}<span class="label label-warning">Yes</span>{% else %}<span class="label label-default">No</span>{% endif %}</p>
            <p><strong>Total Visits:</strong> <span class="badge bg-blue">{{ total_visits }}</span></p>
          </div>
        </div>

        <div class="box box-warning">
          <div class="box-header">
            <h3 class="box-title">Frequently Buys</h3>
          </div>
          <div class="box-body">
            {% if recommendations %}
            <ul class="list-group">
              {% for item in recommendations %}
              <li class="list-group-item">
                <span class="badge">{{ item.times_bought }}x</span>
                {{ item.name }}
                <small class="text-muted">(qty: {{ item.total_quantity }})</small>
              </li>
              {% endfor %}
            </ul>
            {% else %}
            <p class="text-muted">No purchase history yet.</p>
            {% endif %}
          </div>
        </div>
      </div>

      <div class="col-md-8">
        <div class="box">
          <div class="box-header">
            <h3 class="box-title">Last 10 Visits</h3>
          </div>
          <div class="box-body table-responsive">
            <table class="table table-hover">
              <thead>
                <tr>
                  <th>#</th>
                  <th>Date & Time</th>
                  <th>Camera</th>
                  <th>Confidence</th>
                  <th>Snapshot</th>
                </tr>
              </thead>
              <tbody>
                {% for visit in history %}
                <tr>
                  <td>{{ forloop.counter }}</td>
                  <td>{{ visit.date }}</td>
                  <td>{{ visit.camera }}</td>
                  <td>{{ visit.confidence|default:"-" }}</td>
                  <td>
                    {% if visit.snapshot %}
                    <a href="{{ visit.snapshot }}" target="_blank"><img src="{{ visit.snapshot }}" style="height: 40px; border-radius: 4px;"></a>
                    {% else %}-{% endif %}
                  </td>
                </tr>
                {% empty %}
                <tr><td colspan="5" class="text-center text-muted">No visits recorded.</td></tr>
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
'@

Write-TemplateFile "$templateDir\customer_visit_history.html" $visitHistoryTemplate

# ------------------------------------------------------------------
# 4. UNKNOWN VISITOR GALLERY TEMPLATE
# ------------------------------------------------------------------
$unknownGalleryTemplate = @'
{% extends "base.html" %}

{% block title %}Unknown Visitor Gallery{% endblock %}

{% block content %}
<div class="content-wrapper">
  <section class="content-header">
    <h1>Unknown Visitor Gallery</h1>
    <ol class="breadcrumb">
      <li><a href="{% url 'dashboard' %}">Home</a></li>
      <li class="active">Unknown Visitors</li>
    </ol>
  </section>

  <section class="content">
    <div class="box">
      <div class="box-header">
        <h3 class="box-title">Unrecognized Faces (Last 50)</h3>
        <div class="box-tools">
          <span class="label label-default">{{ unknown_count }} total unknowns</span>
        </div>
      </div>
      <div class="box-body">
        <div class="row">
          {% for log in unknown_logs %}
          <div class="col-md-2 col-sm-3 col-xs-6" style="margin-bottom: 20px;">
            <div class="thumbnail" style="border-radius: 10px; overflow: hidden; box-shadow: 0 2px 10px rgba(0,0,0,0.1);">
              {% if log.image_snapshot %}
              <img src="{{ log.image_snapshot.url }}" style="width: 100%; height: 150px; object-fit: cover;" alt="Unknown">
              {% else %}
              <div style="width: 100%; height: 150px; background: #ddd; display: flex; align-items: center; justify-content: center;">
                <i class="fa fa-user-secret fa-3x text-muted"></i>
              </div>
              {% endif %}
              <div class="caption" style="padding: 10px;">
                <small class="text-muted">{{ log.recognized_at|date:"M d, H:i" }}</small><br>
                <small>Camera: {{ log.camera_name|default:"Default" }}</small><br>
                <small>Conf: {{ log.confidence|floatformat:2|default:"-" }}</small><br>
                <a href="{% url 'customer_add' %}?from_unknown={{ log.id }}" class="btn btn-xs btn-success btn-block" style="margin-top: 5px;">
                  <i class="fa fa-plus"></i> Register
                </a>
              </div>
            </div>
          </div>
          {% empty %}
          <div class="col-xs-12 text-center">
            <p class="text-muted" style="padding: 50px;">No unknown visitors recorded yet.</p>
          </div>
          {% endfor %}
        </div>
      </div>
    </div>
  </section>
</div>
{% endblock %}
'@

Write-TemplateFile "$templateDir\unknown_visitor_gallery.html" $unknownGalleryTemplate

# ------------------------------------------------------------------
# 5. UNKNOWN VISITOR GALLERY VIEW
# ------------------------------------------------------------------
$unknownGalleryView = @"

# ============================================================
# UNKNOWN VISITOR GALLERY
# ============================================================

@login_required
def unknown_visitor_gallery(request):
    unknown_logs = (
        RecognitionLog.objects.filter(customer__isnull=True)
        .order_by("-recognized_at")[:50]
    )
    unknown_count = RecognitionLog.objects.filter(customer__isnull=True).count()

    return render(request, "face_recognition_app/unknown_visitor_gallery.html", {
        "unknown_logs": unknown_logs,
        "unknown_count": unknown_count,
    })
"@

Add-Content -Path $viewsPath -Value $unknownGalleryView -Encoding ASCII
Write-Host "[APPEND] Unknown visitor gallery view added" -ForegroundColor Green

# ------------------------------------------------------------------
# 6. CUSTOMER VISIT HISTORY PAGE VIEW
# ------------------------------------------------------------------
$customerHistoryView = @"

@login_required
def customer_visit_history_page(request, customer_id):
    from customers.models import Customer
    customer = get_object_or_404(Customer, id=customer_id)

    history = (
        RecognitionLog.objects.filter(customer=customer)
        .order_by("-recognized_at")[:10]
    )
    total_visits = RecognitionLog.objects.filter(customer=customer).count()

    try:
        from sales.models import SaleItem
        recommendations = (
            SaleItem.objects.filter(sale__customer=customer)
            .values("product__name", "product__id")
            .annotate(count=Count("id"), total_qty=Sum("quantity"))
            .order_by("-count")[:5]
        )
        recs = [
            {
                "name": r["product__name"],
                "times_bought": r["count"],
                "total_quantity": r["total_qty"],
            }
            for r in recommendations
        ]
    except Exception:
        recs = []

    return render(request, "face_recognition_app/customer_visit_history.html", {
        "customer": customer,
        "history": history,
        "total_visits": total_visits,
        "recommendations": recs,
    })
"@

Add-Content -Path $viewsPath -Value $customerHistoryView -Encoding ASCII
Write-Host "[APPEND] Customer history page view added" -ForegroundColor Green

# ------------------------------------------------------------------
# 7. URLS
# ------------------------------------------------------------------
$insightsUrls = @"

    # Customer insights
    path("customer/<int:customer_id>/visit-history/", views.customer_visit_history_page, name="customer_visit_history"),
    path("api/customer/<int:customer_id>/visits/", views.customer_visit_history, name="api_customer_visits"),
    path("api/customer/<int:customer_id>/recommendations/", views.customer_purchase_recommendations, name="api_customer_recommendations"),
    path("api/pos/customer-search/", views.pos_customer_search, name="pos_customer_search"),

    # Unknown visitors
    path("unknown-visitors/", views.unknown_visitor_gallery, name="unknown_visitor_gallery"),
"@

$urlsPath = "$appDir\urls.py"
Backup-File $urlsPath
$urlsContent = Get-Content $urlsPath -Raw
if ($urlsContent -notmatch "unknown_visitor_gallery") {
    $urlsContent = $urlsContent -replace "(\])", "$insightsUrls`$1"
    $urlsContent | Out-File -Encoding ASCII $urlsPath
    Write-Host "[APPEND] Insights URLs added" -ForegroundColor Green
} else {
    Write-Host "[SKIP] Insights URLs already present" -ForegroundColor Yellow
}

# ------------------------------------------------------------------
# 8. FINAL CHECK
# ------------------------------------------------------------------
Write-Host "`n=== Running Django system check ===" -ForegroundColor Yellow
python manage.py check face_recognition_app
if ($LASTEXITCODE -ne 0) {
    Write-Host "[FAIL] Django check failed" -ForegroundColor Red
    exit 1
}

Write-Host "`n=== Customer Insights + POS Search installed ===" -ForegroundColor Green
Write-Host "New URLs:" -ForegroundColor Cyan
Write-Host "  /unknown-visitors/                          - Unknown face gallery" -ForegroundColor White
Write-Host "  /customer/<id>/visit-history/               - Customer visit history page" -ForegroundColor White
Write-Host "  /api/customer/<id>/visits/                  - JSON: last 10 visits" -ForegroundColor White
Write-Host "  /api/customer/<id>/recommendations/         - JSON: frequent buys" -ForegroundColor White
Write-Host "  /api/pos/customer-search/?q=searchterm      - JSON: POS search" -ForegroundColor White
