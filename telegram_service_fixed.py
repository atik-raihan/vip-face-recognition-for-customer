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
            "<b>VIP Customer Alert</b>

"
            "Customer: " + str(customer_name) + "
"
            "Total Purchase: BDT " + str(total_purchase) + "
"
            "Arrived at: " + arrived_at.strftime("%Y-%m-%d %H:%M")
        )
        if phone:
            message += "
Phone: " + str(phone)

        return self.send_message(self.manager_chat_id, message)


telegram_service = TelegramService()
