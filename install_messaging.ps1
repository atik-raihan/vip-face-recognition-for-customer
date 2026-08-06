# install_messaging.ps1
# WhatsApp + Telegram messaging for VIP notifications
# Run from: D:\Downloads\vip-recognition-core\vip-recognition\dashboard\

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

Write-Host "=== Installing Messaging (WhatsApp + Telegram) ===" -ForegroundColor Yellow

# ------------------------------------------------------------------
# 1. WHATSAPP SERVICE
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
# 2. TELEGRAM SERVICE
# ------------------------------------------------------------------
$telegramService = @'
"""
Telegram Bot API service for VIP customer notifications.
Requires in config/settings.py:
    TELEGRAM_BOT_TOKEN = "your-bot-token"
    TELEGRAM_MANAGER_CHAT_ID = "your-chat-id"
"""
import logging
import requests
from django.conf import settings

logger = logging.getLogger(__name__)


class TelegramService:
    API_BASE = "https://api.telegram.org/bot"

    def __init__(self):
        self.bot_token = getattr(settings, "TELEGRAM_BOT_TOKEN", None)
        self.manager_chat_id = getattr(settings, "TELEGRAM_MANAGER_CHAT_ID", None)

    def send_message(self, chat_id, message):
        if not all([self.bot_token, chat_id]):
            logger.warning("Telegram not configured. Message not sent.")
            return False

        url = self.API_BASE + self.bot_token + "/sendMessage"
        payload = {
            "chat_id": chat_id,
            "text": message,
            "parse_mode": "HTML",
        }

        try:
            response = requests.post(url, json=payload, timeout=30)
            response.raise_for_status()
            logger.info("Telegram message sent to %s", chat_id)
            return True
        except requests.RequestException as exc:
            logger.error("Telegram send failed: %s", exc)
            return False

    def notify_vip_arrival(self, customer_name, phone=None, total_purchase=0, arrived_at=None):
        if not self.manager_chat_id:
            logger.warning("TELEGRAM_MANAGER_CHAT_ID not set.")
            return False

        from django.utils import timezone
        if arrived_at is None:
            arrived_at = timezone.now()

        message = (
            "<b>VIP Customer Alert</b>\n\n"
            "Customer: " + str(customer_name) + "\n"
            "Total Purchase: BDT " + str(total_purchase) + "\n"
            "Arrived at: " + arrived_at.strftime("%Y-%m-%d %H:%M")
        )
        if phone:
            message += "\nPhone: " + str(phone)

        return self.send_message(self.manager_chat_id, message)


telegram_service = TelegramService()
'@

Write-PythonFile "$appDir\services\telegram_service.py" $telegramService

# ------------------------------------------------------------------
# 3. RECOGNITION EVENTS (updated with both WhatsApp and Telegram)
# ------------------------------------------------------------------
$recognitionEvents = @'
"""
Fires whenever a customer is recognized by the live camera.
Handles: WhatsApp and Telegram notifications for VIPs.
"""
import logging
from django.utils import timezone

from .whatsapp_service import whatsapp_service
from .telegram_service import telegram_service

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
        logger.debug("Notification deduped for %s", customer.name)
        return

    if log_entry.whatsapp_notified:
        return

    # Try WhatsApp first
    whatsapp_sent = whatsapp_service.notify_vip_arrival(
        customer_name=customer.name,
        phone=getattr(customer, "phone", None),
        total_purchase=getattr(customer, "total_purchase", 0),
        arrived_at=log_entry.recognized_at or now,
    )

    # Fallback to Telegram if WhatsApp fails or not configured
    telegram_sent = False
    if not whatsapp_sent:
        telegram_sent = telegram_service.notify_vip_arrival(
            customer_name=customer.name,
            phone=getattr(customer, "phone", None),
            total_purchase=getattr(customer, "total_purchase", 0),
            arrived_at=log_entry.recognized_at or now,
        )

    if whatsapp_sent or telegram_sent:
        log_entry.whatsapp_notified = True
        log_entry.save(update_fields=["whatsapp_notified"])
        _notification_cache[customer.id] = now
        logger.info("VIP alert sent for %s (WhatsApp: %s, Telegram: %s)", customer.name, whatsapp_sent, telegram_sent)
    else:
        logger.warning("VIP alert NOT sent for %s (no messaging service configured)", customer.name)
'@

Write-PythonFile "$appDir\services\recognition_events.py" $recognitionEvents

# ------------------------------------------------------------------
# 4. SETTINGS TEMPLATE UPDATE (add messaging config section)
# ------------------------------------------------------------------
$settingsNote = @"

# ============================================================
# MESSAGING CONFIGURATION (add to config/settings.py)
# ============================================================
# WhatsApp Cloud API
WHATSAPP_PHONE_NUMBER_ID = ""      # Your WhatsApp Business Account phone number ID
WHATSAPP_ACCESS_TOKEN = ""          # Your Meta/Facebook access token
WHATSAPP_MANAGER_NUMBER = ""          # Manager's WhatsApp number with country code (e.g., 8801XXXXXXXXXX)

# Telegram Bot API
TELEGRAM_BOT_TOKEN = ""             # Your Telegram bot token from @BotFather
TELEGRAM_MANAGER_CHAT_ID = ""       # Manager's Telegram chat ID (get from @userinfobot)
"@

Write-Host "`n=== IMPORTANT ===" -ForegroundColor Yellow
Write-Host "Add the following to your config/settings.py:" -ForegroundColor Cyan
Write-Host $settingsNote -ForegroundColor White
Write-Host "`nGet credentials from:" -ForegroundColor Yellow
Write-Host "  WhatsApp: https://developers.facebook.com/docs/whatsapp/cloud-api/get-started" -ForegroundColor White
Write-Host "  Telegram: Message @BotFather to create a bot, @userinfobot to get chat ID" -ForegroundColor White

# ------------------------------------------------------------------
# 5. FINAL CHECK
# ------------------------------------------------------------------
Write-Host "`n=== Running Django system check ===" -ForegroundColor Yellow
python manage.py check face_recognition_app
if ($LASTEXITCODE -ne 0) {
    Write-Host "[FAIL] Django check failed" -ForegroundColor Red
    exit 1
}

Write-Host "`n=== Messaging installed ===" -ForegroundColor Green
Write-Host "Files:" -ForegroundColor Cyan
Write-Host "  services/whatsapp_service.py    - WhatsApp Cloud API" -ForegroundColor White
Write-Host "  services/telegram_service.py    - Telegram Bot API" -ForegroundColor White
Write-Host "  services/recognition_events.py - Event handler with both services" -ForegroundColor White
Write-Host "`nNext: Add credentials to config/settings.py and test with a VIP recognition" -ForegroundColor Yellow
