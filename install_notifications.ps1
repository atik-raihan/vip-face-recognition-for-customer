# install_notifications.ps1
# Notifications + Voice + Sound + Better Popup UI
# Run from: D:\Downloads\vip-recognition-core\vip-recognition\dashboard\

$ErrorActionPreference = "Stop"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$appDir = "face_recognition_app"
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

Write-Host "=== Installing Notifications + Voice + Sound + Better Popup ===" -ForegroundColor Yellow

# ------------------------------------------------------------------
# 1. WHATSAPP SERVICE (complete implementation)
# ------------------------------------------------------------------
$whatsappService = @'
"""
WhatsApp Cloud API service for VIP customer notifications.
Requires in config/settings.py:
    WHATSAPP_PHONE_NUMBER_ID = "your-phone-number-id"
    WHATSAPP_ACCESS_TOKEN = "your-access-token"
    WHATSAPP_MANAGER_NUMBER = "8801XXXXXXXXXX"
"""
import logging
import requests
from django.conf import settings

logger = logging.getLogger(__name__)


class WhatsAppService:
    API_BASE = "https://graph.facebook.com/v18.0"

    def __init__(self):
        self.phone_number_id = getattr(settings, "WHATSAPP_PHONE_NUMBER_ID", None)
        self.access_token = getattr(settings, "WHATSAPP_ACCESS_TOKEN", None)
        self.manager_number = getattr(settings, "WHATSAPP_MANAGER_NUMBER", None)

    def _headers(self):
        return {
            "Authorization": "Bearer " + str(self.access_token),
            "Content-Type": "application/json",
        }

    def send_text(self, to_number, message):
        if not all([self.phone_number_id, self.access_token, to_number]):
            logger.warning("WhatsApp not configured. Message not sent.")
            return False

        url = self.API_BASE + "/" + str(self.phone_number_id) + "/messages"
        payload = {
            "messaging_product": "whatsapp",
            "recipient_type": "individual",
            "to": to_number,
            "type": "text",
            "text": {"body": message},
        }

        try:
            response = requests.post(url, headers=self._headers(), json=payload, timeout=30)
            response.raise_for_status()
            logger.info("WhatsApp message sent to %s", to_number)
            return True
        except requests.RequestException as exc:
            logger.error("WhatsApp send failed: %s", exc)
            return False

    def notify_vip_arrival(self, customer_name, phone=None, total_purchase=0, arrived_at=None):
        if not self.manager_number:
            logger.warning("WHATSAPP_MANAGER_NUMBER not set.")
            return False

        from django.utils import timezone
        if arrived_at is None:
            arrived_at = timezone.now()

        message = (
            "Welcome! VIP Customer " + str(customer_name) + " has entered the shop.\n\n"
            "Total Purchase: BDT " + str(total_purchase) + "\n"
            "Arrived at: " + arrived_at.strftime("%Y-%m-%d %H:%M")
        )
        if phone:
            message += "\nPhone: " + str(phone)

        return self.send_text(self.manager_number, message)


whatsapp_service = WhatsAppService()
'@

Write-PythonFile "$appDir\services\whatsapp_service.py" $whatsappService

# ------------------------------------------------------------------
# 2. RECOGNITION EVENTS (complete with WhatsApp + dedupe)
# ------------------------------------------------------------------
$recognitionEvents = @'
"""
Fires whenever a customer is recognized by the live camera.
Handles: WhatsApp notification for VIPs.
"""
import logging
from django.utils import timezone

from .whatsapp_service import whatsapp_service

logger = logging.getLogger(__name__)

_notification_cache = {}
_DEDUPE_SECONDS = 300


def on_customer_recognized(log_entry):
    if log_entry.customer is None:
        return

    customer = log_entry.customer
    now = timezone.now()

    if not log_entry.was_vip_at_time:
        return

    last_notified = _notification_cache.get(customer.id)
    if last_notified and (now - last_notified).total_seconds() < _DEDUPE_SECONDS:
        logger.debug("WhatsApp deduped for %s", customer.name)
        return

    if log_entry.whatsapp_notified:
        return

    sent = whatsapp_service.notify_vip_arrival(
        customer_name=customer.name,
        phone=getattr(customer, "phone", None),
        total_purchase=getattr(customer, "total_purchase", 0),
        arrived_at=log_entry.recognized_at or now,
    )

    if sent:
        log_entry.whatsapp_notified = True
        log_entry.save(update_fields=["whatsapp_notified"])
        _notification_cache[customer.id] = now
        logger.info("WhatsApp VIP alert sent for %s", customer.name)
    else:
        logger.warning("WhatsApp VIP alert NOT sent for %s", customer.name)
'@

Write-PythonFile "$appDir\services\recognition_events.py" $recognitionEvents

# ------------------------------------------------------------------
# 3. VOICE GREETING SERVICE
# ------------------------------------------------------------------
$voiceService = @'
"""
Text-to-speech service for VIP welcome greetings.
Uses pyttsx3 offline. Falls back to browser TTS.
"""
import logging
import threading

logger = logging.getLogger(__name__)


def speak_greeting(text):
    def _speak():
        try:
            import pyttsx3
            engine = pyttsx3.init()
            engine.setProperty("rate", 150)
            engine.say(text)
            engine.runAndWait()
        except ImportError:
            logger.debug("pyttsx3 not installed, skipping server-side TTS")
        except Exception as exc:
            logger.warning("TTS failed: %s", exc)

    thread = threading.Thread(target=_speak, daemon=True)
    thread.start()


def build_greeting(customer_name, is_vip=False):
    if is_vip:
        return "Welcome back, VIP customer " + str(customer_name)
    return "Welcome back, " + str(customer_name)
'@

Write-PythonFile "$appDir\services\voice_service.py" $voiceService

# ------------------------------------------------------------------
# 4. ENHANCED POLLING API (adds visit count, last visit, recommendations)
# ------------------------------------------------------------------
$enhancedView = @"

# ============================================================
# ENHANCED POLLING API - visit count, last visit, recommendations
# ============================================================

from django.db.models import Count


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

    # Visit count and last visit
    if customer:
        visit_count = RecognitionLog.objects.filter(customer=customer).count()
        data["visit_count"] = visit_count
        last_visit = RecognitionLog.objects.filter(customer=customer).exclude(id=log.id).order_by("-recognized_at").first()
        data["last_visit"] = last_visit.recognized_at.isoformat() if last_visit else None

        # Purchase recommendations (top 3 products by frequency)
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
Add-Content -Path $viewsPath -Value $enhancedView -Encoding ASCII
Write-Host "[APPEND] Enhanced polling API added" -ForegroundColor Green

# ------------------------------------------------------------------
# 5. BETTER POPUP CSS
# ------------------------------------------------------------------
$popupCSS = @'
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
# 6. ENHANCED POS POPUP HTML/JS
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
  const CUSTOMER_SELECT_ID = "customer";
  const LATEST_RECOGNITION_URL = "/face-recognition/latest-recognition/";
  const POLL_INTERVAL_MS = 3000;
  let lastSeenLogId = null;
  let audioCtx = null;

  function initAudio() {
    if (!audioCtx) audioCtx = new (window.AudioContext || window.webkitAudioContext)();
  }

  function playBeep() {
    initAudio();
    const osc = audioCtx.createOscillator();
    const gain = audioCtx.createGain();
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
      const utter = new SpeechSynthesisUtterance(text);
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
    const d = new Date(dateStr);
    const now = new Date();
    const diff = Math.floor((now - d) / (1000 * 60 * 60 * 24));
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
# 7. URLS
# ------------------------------------------------------------------
$notifyUrls = @"

    # Enhanced polling API
    path("latest-recognition-enhanced/", views.latest_recognition_enhanced, name="latest_recognition_enhanced"),
"@

$urlsPath = "$appDir\urls.py"
Backup-File $urlsPath
$urlsContent = Get-Content $urlsPath -Raw
if ($urlsContent -notmatch "latest_recognition_enhanced") {
    $urlsContent = $urlsContent -replace "(\])", "$notifyUrls`$1"
    $urlsContent | Out-File -Encoding ASCII $urlsPath
    Write-Host "[APPEND] Enhanced API URL added" -ForegroundColor Green
} else {
    Write-Host "[SKIP] Enhanced API URL already present" -ForegroundColor Yellow
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

Write-Host "`n=== Notifications + Voice + Sound + Better Popup installed ===" -ForegroundColor Green
Write-Host "New files:" -ForegroundColor Cyan
Write-Host "  services/whatsapp_service.py       - WhatsApp Cloud API" -ForegroundColor White
Write-Host "  services/recognition_events.py     - Event handler with dedupe" -ForegroundColor White
Write-Host "  services/voice_service.py          - TTS greeting" -ForegroundColor White
Write-Host "  templates/sales/pos_popup.css      - Modern popup styles" -ForegroundColor White
Write-Host "  templates/sales/_pos_popup_enhanced.html - Enhanced popup" -ForegroundColor White
Write-Host "`nNext: Copy popup HTML into your pos.html, add CSS link" -ForegroundColor Yellow
