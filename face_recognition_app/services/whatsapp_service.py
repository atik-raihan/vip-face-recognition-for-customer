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
