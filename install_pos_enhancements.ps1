# install_pos_enhancements.ps1
# POS enhancements: better popup, voice, sound, browser notify, visit count, last visit, recommendations, search
# Run from: D:\Downloads\vip-recognition-core\vip-recognition\dashboard\

$ErrorActionPreference = "Stop"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$appDir = "face_recognition_app"
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

Write-Host "=== Installing POS Enhancements ===" -ForegroundColor Yellow

# ------------------------------------------------------------------
# 1. ENHANCED LATEST_RECOGNITION API (returns visit count, last visit, recommendations)
# ------------------------------------------------------------------
$enhancedApi = @"

# ============================================================
# ENHANCED POLLING API - visit count, last visit, recommendations
# ============================================================

from django.db.models import Count, Sum


@login_required
def latest_recognition_enhanced(request):
    since_id = request.GET.get("since_id")

    qs = RecognitionLog.objects.select_related("customer", "camera")
    if since_id:
        qs = qs.filter(id__gt=since_id)

    log = qs.order_by("-recognized_at").first()

    if not log:
        return JsonResponse({"new": False})

    customer = log.customer
    data = {
        "new": True,
        "log_id": log.id,
        "customer_id": customer.id if customer else None,
        "customer_name": customer.name if customer else "Unknown",
        "photo": log.image_snapshot.url if log.image_snapshot else None,
        "confidence": round(log.confidence, 2) if log.confidence else None,
        "is_vip": log.was_vip_at_time,
        "total_purchase": getattr(customer, "total_purchase", 0) if customer else 0,
        "recognized_at": log.recognized_at.isoformat() if log.recognized_at else None,
        "camera_name": log.camera_name or "Default",
    }

    if customer:
        visit_count = RecognitionLog.objects.filter(customer=customer).count()
        data["visit_count"] = visit_count
        last_visit = RecognitionLog.objects.filter(customer=customer).exclude(id=log.id).order_by("-recognized_at").first()
        data["last_visit"] = last_visit.recognized_at.isoformat() if last_visit else None

        try:
            from sales.models import SaleItem
            frequent_items = (
                SaleItem.objects.filter(sale__customer=customer)
                .values("product__name")
                .annotate(count=Count("id"))
                .order_by("-count")[:3]
            )
            data["frequent_items"] = [item["product__name"] for item in frequent_items]
        except Exception:
            data["frequent_items"] = []
    else:
        data["visit_count"] = 0
        data["last_visit"] = None
        data["frequent_items"] = []

    return JsonResponse(data)
"@

$viewsPath = "$appDir\views.py"
Backup-File $viewsPath

# Check if already present
$viewsContent = Get-Content $viewsPath -Raw
if ($viewsContent -notmatch "latest_recognition_enhanced") {
    Add-Content -Path $viewsPath -Value $enhancedApi -Encoding ASCII
    Write-Host "[APPEND] Enhanced API view added" -ForegroundColor Green
} else {
    Write-Host "[SKIP] Enhanced API already present" -ForegroundColor Yellow
}

# ------------------------------------------------------------------
# 2. POS SEARCH API
# ------------------------------------------------------------------
$posSearchApi = @"

@login_required
def pos_customer_search(request):
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

if ($viewsContent -notmatch "pos_customer_search") {
    Add-Content -Path $viewsPath -Value $posSearchApi -Encoding ASCII
    Write-Host "[APPEND] POS search API added" -ForegroundColor Green
} else {
    Write-Host "[SKIP] POS search API already present" -ForegroundColor Yellow
}

# ------------------------------------------------------------------
# 3. BETTER POPUP CSS
# ------------------------------------------------------------------
$popupCSS = @'
/* VIP Welcome Popup - Modern Card */
#welcome-back-modal {
    display: none;
    position: fixed;
    top: 0; left: 0;
    width: 100%; height: 100%;
    background: rgba(0,0,0,0.7);
    z-index: 9999;
    align-items: center;
    justify-content: center;
    backdrop-filter: blur(4px);
}
#welcome-back-modal.active {
    display: flex;
    animation: fadeIn 0.3s ease;
}
.wb-card {
    background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
    border-radius: 20px;
    padding: 0;
    max-width: 420px;
    width: 90%;
    text-align: center;
    box-shadow: 0 25px 80px rgba(0,0,0,0.5);
    overflow: hidden;
    animation: slideUp 0.4s ease;
    border: 1px solid rgba(255,215,0,0.2);
}
.wb-header {
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    padding: 25px 20px 15px;
    position: relative;
}
.wb-vip-crown {
    position: absolute;
    top: -15px;
    left: 50%;
    transform: translateX(-50%);
    font-size: 36px;
    filter: drop-shadow(0 2px 4px rgba(0,0,0,0.3));
}
.wb-header h2 {
    margin: 10px 0 5px;
    color: #fff;
    font-size: 1.6em;
    text-transform: uppercase;
    letter-spacing: 2px;
}
.wb-customer-name {
    margin: 0;
    color: #ffd700;
    font-size: 1.8em;
    font-weight: bold;
    text-shadow: 0 2px 10px rgba(255,215,0,0.3);
}
.wb-body {
    padding: 25px 30px;
    color: #e0e0e0;
}
.wb-stats {
    display: flex;
    justify-content: space-around;
    margin: 20px 0;
}
.wb-stat {
    text-align: center;
}
.wb-stat-value {
    font-size: 1.5em;
    font-weight: bold;
    color: #ffd700;
}
.wb-stat-label {
    font-size: 0.8em;
    color: #888;
    text-transform: uppercase;
}
.wb-snapshot {
    width: 120px;
    height: 120px;
    border-radius: 50%;
    object-fit: cover;
    border: 3px solid #ffd700;
    margin: 15px auto;
    box-shadow: 0 0 20px rgba(255,215,0,0.3);
}
.wb-confidence {
    display: inline-block;
    background: rgba(255,255,255,0.1);
    padding: 5px 15px;
    border-radius: 20px;
    font-size: 0.9em;
    margin: 10px 0;
}
.wb-btn {
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    color: #fff;
    border: none;
    padding: 12px 40px;
    border-radius: 30px;
    cursor: pointer;
    font-size: 1em;
    margin-top: 15px;
    transition: transform 0.2s, box-shadow 0.2s;
}
.wb-btn:hover {
    transform: translateY(-2px);
    box-shadow: 0 10px 30px rgba(102,126,234,0.4);
}
@keyframes fadeIn {
    from { opacity: 0; }
    to { opacity: 1; }
}
@keyframes slideUp {
    from { transform: translateY(50px); opacity: 0; }
    to { transform: translateY(0); opacity: 1; }
}
'@

Write-TemplateFile "$posDir\pos_popup.css" $popupCSS

# ------------------------------------------------------------------
# 4. ENHANCED POPUP HTML/JS
# ------------------------------------------------------------------
$popupHTML = @'
<div id="welcome-back-modal">
  <div class="wb-card">
    <div class="wb-header">
      <div class="wb-vip-crown" id="wb-crown" style="display:none;">[VIP]</div>
      <h2>WELCOME BACK</h2>
      <h3 class="wb-customer-name" id="wb-customer-name"></h3>
    </div>
    <div class="wb-body">
      <img id="wb-snapshot" class="wb-snapshot" src="" alt="Snapshot" style="display:none;">
      <div class="wb-confidence" id="wb-confidence"></div>
      <div class="wb-stats">
        <div class="wb-stat">
          <div class="wb-stat-value" id="wb-total-purchase">0</div>
          <div class="wb-stat-label">Total Purchase (BDT)</div>
        </div>
        <div class="wb-stat">
          <div class="wb-stat-value" id="wb-visit-count">-</div>
          <div class="wb-stat-label">Visit #</div>
        </div>
        <div class="wb-stat">
          <div class="wb-stat-value" id="wb-last-visit">-</div>
          <div class="wb-stat-label">Last Visit</div>
        </div>
      </div>
      <div id="wb-recommendations" style="display:none; margin: 15px 0; padding: 10px; background: rgba(255,215,0,0.1); border-radius: 10px;">
        <strong style="color:#ffd700;">Frequently Buys:</strong>
        <span id="wb-frequent-items"></span>
      </div>
      <button class="wb-btn" onclick="closeWelcomeBackModal()">Continue</button>
    </div>
  </div>
</div>

<link rel="stylesheet" href="{% static 'sales/pos_popup.css' %}">

<script>
(function() {
  var CUSTOMER_SELECT_ID = "customer";
  var LATEST_RECOGNITION_URL = "/camera/latest-recognition/";
  var POLL_INTERVAL_MS = 3000;
  var lastSeenLogId = null;
  var audioCtx = null;

  function initAudio() {
    if (!audioCtx) audioCtx = new (window.AudioContext || window.webkitAudioContext)();
  }

  function playBeep() {
    initAudio();
    var osc = audioCtx.createOscillator();
    var gain = audioCtx.createGain();
    osc.connect(gain);
    gain.connect(audioCtx.destination);
    osc.frequency.value = 800;
    gain.gain.setValueAtTime(0.1, audioCtx.currentTime);
    gain.gain.exponentialRampToValueAtTime(0.001, audioCtx.currentTime + 0.3);
    osc.start(audioCtx.currentTime);
    osc.stop(audioCtx.currentTime + 0.3);
  }

  function speakText(text) {
    if ('speechSynthesis' in window) {
      var utter = new SpeechSynthesisUtterance(text);
      utter.rate = 0.9;
      utter.pitch = 1.1;
      window.speechSynthesis.speak(utter);
    }
  }

  function showBrowserNotify(title, body, icon) {
    if ("Notification" in window && Notification.permission === "granted") {
      new Notification(title, { body: body, icon: icon });
    }
  }

  function formatDate(dateStr) {
    if (!dateStr) return "First visit!";
    var d = new Date(dateStr);
    var now = new Date();
    var diff = Math.floor((now - d) / (1000 * 60 * 60 * 24));
    if (diff === 0) return "Today " + d.toLocaleTimeString([], {hour:'2-digit', minute:'2-digit'});
    if (diff === 1) return "Yesterday";
    return diff + " days ago";
  }

  function showWelcomeBackModal(data) {
    document.getElementById("wb-customer-name").textContent = data.customer_name;
    document.getElementById("wb-total-purchase").textContent = Number(data.total_purchase).toLocaleString();
    document.getElementById("wb-confidence").textContent = data.confidence ? "Confidence: " + (data.confidence * 100).toFixed(0) + "%" : "";

    var crown = document.getElementById("wb-crown");
    crown.style.display = data.is_vip ? "block" : "none";

    var snapshot = document.getElementById("wb-snapshot");
    if (data.photo) {
      snapshot.src = data.photo;
      snapshot.style.display = "block";
    } else {
      snapshot.style.display = "none";
    }

    document.getElementById("wb-visit-count").textContent = data.visit_count || "-";
    document.getElementById("wb-last-visit").textContent = formatDate(data.last_visit);

    var recDiv = document.getElementById("wb-recommendations");
    if (data.frequent_items && data.frequent_items.length > 0) {
      document.getElementById("wb-frequent-items").textContent = data.frequent_items.join(", ");
      recDiv.style.display = "block";
    } else {
      recDiv.style.display = "none";
    }

    document.getElementById("welcome-back-modal").classList.add("active");

    playBeep();
    if (data.is_vip) {
      speakText("Welcome back, VIP customer " + data.customer_name);
      showBrowserNotify("VIP Customer Entered", data.customer_name + " is here!", data.photo);
    } else {
      speakText("Welcome back, " + data.customer_name);
    }

    setTimeout(closeWelcomeBackModal, 5000);
  }

  window.closeWelcomeBackModal = function() {
    document.getElementById("welcome-back-modal").classList.remove("active");
  };

  function autoSelectCustomer(customerId) {
    var select = document.getElementById(CUSTOMER_SELECT_ID);
    if (!select) return;
    select.value = String(customerId);
    select.dispatchEvent(new Event("change", { bubbles: true }));
  }

  if ("Notification" in window && Notification.permission === "default") {
    Notification.requestPermission();
  }

  async function pollRecognition() {
    try {
      var url = new URL(LATEST_RECOGNITION_URL, window.location.origin);
      if (lastSeenLogId) url.searchParams.set("since_id", lastSeenLogId);

      var response = await fetch(url);
      if (!response.ok) return;

      var data = await response.json();
      if (data.new) {
        lastSeenLogId = data.log_id;
        autoSelectCustomer(data.customer_id);
        showWelcomeBackModal(data);
      }
    } catch (err) {
      console.debug("Recognition poll failed:", err);
    }
  }

  setInterval(pollRecognition, POLL_INTERVAL_MS);
})();
</script>
'@

Write-TemplateFile "$posDir\_pos_popup_enhanced.html" $popupHTML

# ------------------------------------------------------------------
# 5. URLS
# ------------------------------------------------------------------
$enhancedUrls = @"

    # Enhanced polling API
    path("latest-recognition-enhanced/", views.latest_recognition_enhanced, name="latest_recognition_enhanced"),
    path("api/pos/customer-search/", views.pos_customer_search, name="pos_customer_search"),
"@

$urlsPath = "$appDir\urls.py"
Backup-File $urlsPath
$urlsContent = Get-Content $urlsPath -Raw
if ($urlsContent -notmatch "latest_recognition_enhanced") {
    $urlsContent = $urlsContent -replace "(\])", "$enhancedUrls`$1"
    $urlsContent | Out-File -Encoding ASCII $urlsPath
    Write-Host "[APPEND] Enhanced API URLs added" -ForegroundColor Green
} else {
    Write-Host "[SKIP] Enhanced API URLs already present" -ForegroundColor Yellow
}

# ------------------------------------------------------------------
# 6. FINAL CHECK
# ------------------------------------------------------------------
Write-Host "`n=== Running Django system check ===" -ForegroundColor Yellow
python manage.py check face_recognition_app
if ($LASTEXITCODE -ne 0) {
    Write-Host "[FAIL] Django check failed" -ForegroundColor Red
    exit 1
}

Write-Host "`n=== POS Enhancements installed ===" -ForegroundColor Green
Write-Host "Files:" -ForegroundColor Cyan
Write-Host "  templates/sales/pos_popup.css              - Modern popup styles" -ForegroundColor White
Write-Host "  templates/sales/_pos_popup_enhanced.html   - Enhanced popup with voice/sound/browser notify" -ForegroundColor White
Write-Host "`nNext: Copy popup HTML into your pos.html, add CSS link" -ForegroundColor Yellow
