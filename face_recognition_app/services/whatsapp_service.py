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
            response = requests.post(
                self._endpoint(),
                json=payload,
                headers=headers,
                timeout=10,
            )

            print("=" * 50)
            print("Status Code:", response.status_code)
            print("Response:")
            print(response.text)
            print("=" * 50)

            if response.status_code in (200, 201):
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
