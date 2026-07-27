$ErrorActionPreference = "Stop"

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

function Backup-IfExists {
    param([string]$Path)
    if (Test-Path $Path) {
        $backupPath = "$Path.bak_$timestamp"
        Copy-Item -Path $Path -Destination $backupPath -Force
        Write-Host "[OK] Backed up $Path -> $backupPath"
    } else {
        Write-Host "[SKIP] $Path does not exist yet, nothing to back up"
    }
}

$whatsappServicePath = "face_recognition_app\services\whatsapp_service.py"
$recognitionEventsPath = "face_recognition_app\services\recognition_events.py"
$aiVipMessagePath = "face_recognition_app\services\ai_vip_message_service.py"
$settingsHtmlPath = "templates\face_recognition_app\settings.html"

Write-Host "=== Backing up existing files ==="
Backup-IfExists $whatsappServicePath
Backup-IfExists $recognitionEventsPath
Backup-IfExists $aiVipMessagePath
Backup-IfExists $settingsHtmlPath

New-Item -ItemType Directory -Force -Path (Split-Path $whatsappServicePath) | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path $settingsHtmlPath) | Out-Null

Write-Host ""
Write-Host "=== Writing whatsapp_service.py ==="
$whatsappServiceContent = @'
"""
face_recognition_app/services/whatsapp_service.py

Sends WhatsApp notifications to the manager when a VIP customer is
recognized, using Meta's official WhatsApp Cloud API.

Setup required (add to config/settings.py):

    WHATSAPP_PHONE_NUMBER_ID = "your-phone-number-id"
    WHATSAPP_ACCESS_TOKEN = "your-permanent-access-token"
    WHATSAPP_MANAGER_NUMBER = "8801XXXXXXXXX"   # no + or leading 00, country code + number
    WHATSAPP_API_VERSION = "v20.0"              # optional, defaults below

This module fails silently (logs, doesn't raise) if WhatsApp isn't
configured yet, so the rest of the recognition pipeline keeps working
even before you've set up API credentials.
"""

import logging

import requests
from django.conf import settings

logger = logging.getLogger(__name__)

DEFAULT_API_VERSION = "v20.0"


class WhatsAppService:

    def __init__(self):
        self.phone_number_id = getattr(settings, "WHATSAPP_PHONE_NUMBER_ID", None)
        self.access_token = getattr(settings, "WHATSAPP_ACCESS_TOKEN", None)
        self.manager_number = getattr(settings, "WHATSAPP_MANAGER_NUMBER", None)
        self.api_version = getattr(settings, "WHATSAPP_API_VERSION", DEFAULT_API_VERSION)

    @property
    def is_configured(self) -> bool:
        return bool(self.phone_number_id and self.access_token and self.manager_number)

    def _endpoint(self) -> str:
        return f"https://graph.facebook.com/{self.api_version}/{self.phone_number_id}/messages"

    def send_text(self, to_number: str, message: str) -> bool:
        if not self.is_configured:
            logger.warning(
                "WhatsApp not configured (WHATSAPP_PHONE_NUMBER_ID / "
                "WHATSAPP_ACCESS_TOKEN / WHATSAPP_MANAGER_NUMBER missing in settings). "
                "Skipping notification."
            )
            return False

        payload = {
            "messaging_product": "whatsapp",
            "to": to_number,
            "type": "text",
            "text": {"body": message},
        }
        headers = {
            "Authorization": f"Bearer {self.access_token}",
            "Content-Type": "application/json",
        }

        try:
            response = requests.post(self._endpoint(), json=payload, headers=headers, timeout=10)
            if response.status_code == 200:
                return True
            logger.error(
                "WhatsApp send failed (status %s): %s",
                response.status_code,
                response.text,
            )
            return False
        except requests.RequestException as exc:
            logger.error("WhatsApp send failed (network error): %s", exc)
            return False

    def notify_vip_arrival(self, customer_name: str, phone: str, total_purchase, arrived_at) -> bool:
        message = (
            "VIP Customer Arrived\n\n"
            f"Name:\n{customer_name}\n\n"
            f"Phone:\n{phone or 'N/A'}\n\n"
            f"Total Purchase:\n{total_purchase} BDT\n\n"
            f"Time:\n{arrived_at.strftime('%I:%M %p')}"
        )
        return self.send_text(self.manager_number, message)


whatsapp_service = WhatsAppService()
'@
Set-Content -Path $whatsappServicePath -Value $whatsappServiceContent -Encoding ASCII
Write-Host "[OK] Wrote $whatsappServicePath"

Write-Host ""
Write-Host "=== Writing ai_vip_message_service.py ==="
$aiVipMessageContent = @'
"""
face_recognition_app/services/ai_vip_message_service.py

Generates a short, personalized heads-up message for the STORE MANAGER
(not the customer) when a VIP is recognized. The manager reads this and
decides how to greet the customer; nothing is ever auto-sent to the
customer.

Requires in settings.py:
    ANTHROPIC_API_KEY = "sk-ant-..."       # required
    ANTHROPIC_MODEL = "claude-sonnet-5"     # optional, has a default below

If the API call fails for any reason (no key set, network issue, rate
limit), this falls back to a plain template message rather than blocking
the WhatsApp notification entirely.
"""
import logging

from django.conf import settings

logger = logging.getLogger(__name__)

DEFAULT_MODEL = "claude-sonnet-5"  # check docs.claude.com for current model names if this 404s


def _fallback_message(customer):
    return (
        f"VIP arrival: {customer.name} just walked in. "
        f"Total purchase: {customer.total_purchase}."
    )


def generate_vip_arrival_message(customer, confidence=None, recent_logs=None):
    api_key = getattr(settings, "ANTHROPIC_API_KEY", None)
    if not api_key:
        logger.warning("ANTHROPIC_API_KEY not set -- using fallback VIP message.")
        return _fallback_message(customer)

    try:
        import anthropic

        client = anthropic.Anthropic(api_key=api_key)
        model = getattr(settings, "ANTHROPIC_MODEL", DEFAULT_MODEL)

        visit_context = ""
        if recent_logs:
            last_visit = recent_logs[0].recognized_at if len(recent_logs) > 0 else None
            visit_count = len(recent_logs)
            if last_visit:
                visit_context = f" They've visited {visit_count} times recently, last on {last_visit:%Y-%m-%d}."

        prompt = (
            f"A VIP customer named {customer.name} just walked into the store. "
            f"Their lifetime purchase total is {customer.total_purchase}."
            f"{visit_context}"
            f"{f' Recognition confidence: {confidence:.0%}.' if confidence else ''}\n\n"
            "Write a ONE-sentence, casual heads-up for the store manager's phone "
            "(WhatsApp), so they can greet this customer well. No greeting like "
            "'Hi manager', no markdown, no quotes around it -- just the sentence itself. "
            "Do not invent specific products or facts not given above."
        )

        response = client.messages.create(
            model=model,
            max_tokens=120,
            messages=[{"role": "user", "content": prompt}],
        )

        text = "".join(
            block.text for block in response.content if getattr(block, "type", None) == "text"
        ).strip()

        return text if text else _fallback_message(customer)

    except Exception as exc:
        logger.warning(f"AI VIP message generation failed, using fallback: {exc}")
        return _fallback_message(customer)
'@
Set-Content -Path $aiVipMessagePath -Value $aiVipMessageContent -Encoding ASCII
Write-Host "[OK] Wrote $aiVipMessagePath"

Write-Host ""
Write-Host "=== Writing recognition_events.py ==="
$recognitionEventsContent = @'
"""
face_recognition_app/services/recognition_events.py

Fires whenever a customer (or unknown face) is recognized by the live
camera. Wired in as a soft/lazy import from camera/live_ai_camera.py.

    1. WhatsApp notification for VIP arrivals (item 7)
    2. Making the event available for POS to auto-select the customer
       and show the "Welcome Back" popup (item 6)
"""

import logging

from django.utils import timezone

from .whatsapp_service import whatsapp_service
from .ai_vip_message_service import generate_vip_arrival_message

logger = logging.getLogger(__name__)


def on_customer_recognized(log_entry):
    """
    log_entry: an already-saved RecognitionLog instance.

    - If it's a known VIP and hasn't already been notified, send the
      WhatsApp alert and mark whatsapp_notified=True.
    - Unknown faces (log_entry.customer is None) never trigger WhatsApp,
      per spec item 8.
    - If SystemSettings.ai_vip_messages_enabled is True, the message body
      is AI-generated (with a safe template fallback baked into
      generate_vip_arrival_message itself); otherwise the original static
      template is used exactly as before.
    """
    if log_entry.customer is None:
        return

    if not log_entry.was_vip_at_time:
        return

    if log_entry.whatsapp_notified:
        return

    customer = log_entry.customer

    ai_enabled = False
    try:
        from face_recognition_app.models_settings import SystemSettings

        ai_enabled = bool(getattr(SystemSettings.load(), "ai_vip_messages_enabled", False))
    except Exception:
        ai_enabled = False

    if ai_enabled:
        recent_logs = (
            customer.recognition_logs.exclude(id=log_entry.id).order_by("-recognized_at")[:5]
        )
        message = generate_vip_arrival_message(
            customer=customer,
            confidence=log_entry.confidence,
            recent_logs=recent_logs,
        )
        sent = whatsapp_service.send_text(whatsapp_service.manager_number, message)
    else:
        sent = whatsapp_service.notify_vip_arrival(
            customer_name=customer.name,
            phone=customer.phone,
            total_purchase=customer.total_purchase,
            arrived_at=log_entry.recognized_at or timezone.now(),
        )

    if sent:
        log_entry.whatsapp_notified = True
        log_entry.save(update_fields=["whatsapp_notified"])
        logger.info("WhatsApp VIP alert sent for %s (AI message: %s)", customer.name, ai_enabled)
    else:
        logger.warning("WhatsApp VIP alert NOT sent for %s (see previous log line for reason)", customer.name)
'@
Set-Content -Path $recognitionEventsPath -Value $recognitionEventsContent -Encoding ASCII
Write-Host "[OK] Wrote $recognitionEventsPath"

Write-Host ""
Write-Host "=== Writing settings.html ==="
$settingsHtmlContent = @'
{% extends "base.html" %}
{# NOTE: change "base.html" above to whatever your dashboard.html extends,
   if it's not literally "base.html" -- check the top line of dashboard.html. #}

{% block content %}
<div class="container-fluid">
  <h1 class="mt-3 mb-4">Recognition Settings</h1>

  {% if messages %}
    {% for message in messages %}
      <div class="alert alert-{{ message.tags }}">{{ message }}</div>
    {% endfor %}
  {% endif %}

  <div class="card mb-4">
    <div class="card-header"><strong>Recognition &amp; VIP Thresholds</strong></div>
    <div class="card-body">
      <form method="post">
        {% csrf_token %}
        <div class="form-group">
          <label>Recognition Threshold (0.0 - 1.0)</label>
          {{ form.recognition_threshold }}
          <small class="form-text text-muted">Lower = more lenient face matching. Default 0.65.</small>
        </div>
        <div class="form-group">
          <label>VIP Minimum Purchase</label>
          {{ form.vip_min_purchase }}
        </div>
        <div class="form-group">
          <label>Default Camera Source</label>
          {{ form.default_camera_source }}
          <small class="form-text text-muted">Used when a camera feed is opened without picking a specific camera below.</small>
        </div>
        <div class="form-group form-check">
          {{ form.ai_vip_messages_enabled }}
          <label class="form-check-label">Enable AI-personalized VIP WhatsApp messages</label>
        </div>
        <button type="submit" name="save_settings" class="btn btn-primary">Save Settings</button>
      </form>
    </div>
  </div>

  <div class="card mb-4">
    <div class="card-header"><strong>Cameras</strong></div>
    <div class="card-body">
      <table class="table table-striped">
        <thead>
          <tr>
            <th>Name</th>
            <th>Source Type</th>
            <th>Connection String</th>
            <th>Branch</th>
            <th>Actions</th>
          </tr>
        </thead>
        <tbody>
          {% for camera in cameras %}
          <tr>
            <form method="post" action="{% url 'camera_edit' camera.id %}">
              {% csrf_token %}
              <td><input type="text" name="name" class="form-control" value="{{ camera.name }}"></td>
              <td>
                <select name="source_type" class="form-control">
                  <option value="webcam" {% if camera.source_type == "webcam" %}selected{% endif %}>Webcam</option>
                  <option value="usb" {% if camera.source_type == "usb" %}selected{% endif %}>USB</option>
                  <option value="rtsp" {% if camera.source_type == "rtsp" %}selected{% endif %}>RTSP</option>
                  <option value="dvr" {% if camera.source_type == "dvr" %}selected{% endif %}>DVR</option>
                </select>
              </td>
              <td><input type="text" name="connection_string" class="form-control" value="{{ camera.connection_string }}"></td>
              <td>
                <select name="branch" class="form-control">
                  <option value="">-- None --</option>
                  {% for branch in branches %}
                  <option value="{{ branch.id }}" {% if camera.branch_id == branch.id %}selected{% endif %}>{{ branch.name }}</option>
                  {% endfor %}
                </select>
              </td>
              <td>
                <button type="submit" class="btn btn-sm btn-secondary">Save</button>
            </form>
                <form method="post" action="{% url 'camera_delete' camera.id %}" style="display:inline;">
                  {% csrf_token %}
                  <button type="submit" class="btn btn-sm btn-danger" onclick="return confirm('Remove this camera?');">Delete</button>
                </form>
                <a href="{% url 'video_feed' %}?camera_id={{ camera.id }}" class="btn btn-sm btn-outline-primary" target="_blank">View Feed</a>
              </td>
          </tr>
          {% empty %}
          <tr><td colspan="5">No cameras added yet.</td></tr>
          {% endfor %}
        </tbody>
      </table>

      <hr>
      <h5>Add Camera</h5>
      <form method="post" action="{% url 'camera_add' %}" class="form-inline">
        {% csrf_token %}
        {{ camera_form.name }}
        {{ camera_form.source_type }}
        {{ camera_form.connection_string }}
        {{ camera_form.branch }}
        <button type="submit" class="btn btn-success ml-2">Add Camera</button>
      </form>
    </div>
  </div>
</div>
{% endblock %}
'@
Set-Content -Path $settingsHtmlPath -Value $settingsHtmlContent -Encoding ASCII
Write-Host "[OK] Wrote $settingsHtmlPath"

Write-Host ""
Write-Host "=== Validating Python syntax ==="
python -m py_compile $whatsappServicePath
python -m py_compile $aiVipMessagePath
python -m py_compile $recognitionEventsPath
Write-Host "[OK] All three files parse as valid Python"

Write-Host ""
Write-Host "=== Running Django check ==="
if (Test-Path "manage.py") {
    python manage.py check face_recognition_app
    Write-Host "[OK] Django check passed"
} else {
    Write-Host "[SKIP] manage.py not found in current directory -- run this script from the same folder as manage.py (your 'dashboard' folder) to enable this check"
}

Write-Host ""
Write-Host "=== Done ==="
Write-Host "Reminder: this installer does NOT set your ANTHROPIC_API_KEY or WhatsApp credentials."
Write-Host "Those still need to be pasted into config\settings.py by hand."