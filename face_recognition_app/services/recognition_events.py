"""
face_recognition_app/services/recognition_events.py

Fires whenever a customer (or unknown face) is recognized by the live
camera.

Features
--------
1. WhatsApp notification for VIP arrivals.
2. Optional AI-generated VIP messages.
3. Prevent duplicate notifications.
4. Detailed debug logging.
"""

import logging

from django.utils import timezone

from .ai_vip_message_service import generate_vip_arrival_message
from .whatsapp_service import whatsapp_service

logger = logging.getLogger(__name__)


def on_customer_recognized(log_entry):
    """
    Process a customer recognition event.

    Only VIP customers trigger a WhatsApp notification.
    Unknown customers and duplicate notifications are ignored.
    """

    print("\n" + "=" * 60)
    print("VIP RECOGNITION EVENT")
    print("=" * 60)

    print(f"Recognition Log ID : {log_entry.id}")
    print(f"Customer           : {log_entry.customer}")
    print(f"VIP                : {log_entry.was_vip_at_time}")
    print(f"Already Notified   : {log_entry.whatsapp_notified}")

    # --------------------------------------------------
    # Unknown customer
    # --------------------------------------------------

    if log_entry.customer is None:
        print("[STOP] Unknown face detected.")
        print("=" * 60)
        return

    # --------------------------------------------------
    # Not VIP
    # --------------------------------------------------

    if not log_entry.was_vip_at_time:
        print("[STOP] Customer is not VIP.")
        print("=" * 60)
        return

    # --------------------------------------------------
    # Already notified
    # --------------------------------------------------

    if log_entry.whatsapp_notified:
        print("[STOP] WhatsApp already sent.")
        print("=" * 60)
        return

    customer = log_entry.customer

    print("\nCustomer Details")
    print("-" * 40)
    print(f"ID              : {customer.id}")
    print(f"Name            : {customer.name}")
    print(f"Phone           : {customer.phone}")
    print(f"VIP             : {customer.is_vip}")
    print(f"Total Purchase  : {customer.total_purchase}")

    # --------------------------------------------------
    # AI Settings
    # --------------------------------------------------

    ai_enabled = False

    try:
        from face_recognition_app.models_settings import SystemSettings

        settings = SystemSettings.load()

        ai_enabled = bool(
            getattr(
                settings,
                "ai_vip_messages_enabled",
                False,
            )
        )

    except Exception as e:
        print("\nCould not load AI settings")
        print(e)
        logger.exception(e)

    print(f"\nAI Enabled : {ai_enabled}")

    # --------------------------------------------------
    # Send WhatsApp
    # --------------------------------------------------

    sent = False

    try:

        if ai_enabled:

            print("\nGenerating AI VIP message...")

            recent_logs = (
                customer.recognition_logs
                .exclude(id=log_entry.id)
                .order_by("-recognized_at")[:5]
            )

            message = generate_vip_arrival_message(
                customer=customer,
                confidence=log_entry.confidence,
                recent_logs=recent_logs,
            )

            print("\nGenerated AI Message")
            print("-" * 40)
            print(message)
            print("-" * 40)

            print("\nSending AI WhatsApp message...")

            sent = whatsapp_service.send_text(
                whatsapp_service.manager_number,
                message,
            )

        else:

            print("\nSending default VIP WhatsApp message...")

            sent = whatsapp_service.notify_vip_arrival(
                customer_name=customer.name,
                phone=customer.phone,
                total_purchase=customer.total_purchase,
                arrived_at=log_entry.recognized_at or timezone.now(),
            )

        print(f"\nWhatsApp Send Result : {sent}")

    except Exception as e:

        print("\nERROR while sending WhatsApp")
        print("-" * 40)
        print(type(e).__name__)
        print(e)
        print("-" * 40)

        logger.exception(e)
        print("=" * 60)
        return

    # --------------------------------------------------
    # Update notification status
    # --------------------------------------------------

    if sent:

        try:
            log_entry.whatsapp_notified = True
            log_entry.save(update_fields=["whatsapp_notified"])

            print("\n[SUCCESS] WhatsApp notification sent.")
            print("[SUCCESS] Recognition log updated.")

            logger.info(
                "WhatsApp VIP alert sent for %s (AI=%s)",
                customer.name,
                ai_enabled,
            )

        except Exception as e:

            print("\nERROR while updating RecognitionLog")
            print(type(e).__name__)
            print(e)

            logger.exception(e)

    else:

        print("\n[FAILED] WhatsApp notification was not sent.")

        logger.warning(
            "WhatsApp VIP alert NOT sent for %s",
            customer.name,
        )

    print("=" * 60)