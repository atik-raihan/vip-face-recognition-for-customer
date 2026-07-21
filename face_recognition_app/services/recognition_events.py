"""
face_recognition_app/services/recognition_events.py

Fires whenever a customer (or unknown face) is recognized by the live
camera. Wired in as a soft/lazy import from camera/live_ai_camera.py, so
this file didn't need to exist for the camera pipeline to work earlier —
now it does the two remaining jobs:

    1. WhatsApp notification for VIP arrivals (item 7)
    2. Making the event available for POS to auto-select the customer
       and show the "Welcome Back" popup (item 6)

Item 2 is done by simply saving to RecognitionLog (already happening
in live_ai_camera.py) and exposing a small polling endpoint
(`latest_recognition`, see views.py) that the POS page's JavaScript
calls every couple of seconds.
"""

import logging

from django.utils import timezone

from .whatsapp_service import whatsapp_service

logger = logging.getLogger(__name__)


def on_customer_recognized(log_entry):
    """
    log_entry: an already-saved RecognitionLog instance.

    - If it's a known VIP and hasn't already been notified, send the
      WhatsApp alert and mark whatsapp_notified=True.
    - Unknown faces (log_entry.customer is None) never trigger WhatsApp,
      per spec item 8.
    """
    if log_entry.customer is None:
        return  # Unknown Customer — never notify, per spec.

    if not log_entry.was_vip_at_time:
        return  # Known but not VIP — no notification needed.

    if log_entry.whatsapp_notified:
        return  # Already notified for this event.

    customer = log_entry.customer
    sent = whatsapp_service.notify_vip_arrival(
        customer_name=customer.name,
        phone=customer.phone,
        total_purchase=customer.total_purchase,
        arrived_at=log_entry.recognized_at or timezone.now(),
    )

    if sent:
        log_entry.whatsapp_notified = True
        log_entry.save(update_fields=["whatsapp_notified"])
        logger.info("WhatsApp VIP alert sent for %s", customer.name)
    else:
        logger.warning("WhatsApp VIP alert NOT sent for %s (see previous log line for reason)", customer.name)
