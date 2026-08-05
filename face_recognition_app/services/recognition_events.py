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
