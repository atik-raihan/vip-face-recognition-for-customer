"""
face_recognition_app/services/recognition_events.py

Fires whenever a customer (or unknown face) is recognized by the live
camera.

Features:
1. WhatsApp notification for VIP arrivals
2. AI-generated VIP messages (optional)
3. Prevent duplicate notifications
4. Debug logging for troubleshooting
"""

import logging

from django.utils import timezone

from .whatsapp_service import whatsapp_service
from .ai_vip_message_service import generate_vip_arrival_message

logger = logging.getLogger(__name__)


def on_customer_recognized(log_entry):

    print("\n" + "=" * 60)
    print("VIP RECOGNITION EVENT")
    print("=" * 60)

    print("Recognition Log ID :", log_entry.id)
    print("Customer           :", log_entry.customer)
    print("VIP                :", log_entry.was_vip_at_time)
    print("Already Notified   :", log_entry.whatsapp_notified)

    # -------------------------
    # Unknown face
    # -------------------------

    if log_entry.customer is None:
        print("[STOP] Unknown face detected.")
        return

    # -------------------------
    # Not VIP
    # -------------------------

    if not log_entry.was_vip_at_time:
        print("[STOP] Customer is not VIP.")
        return

    # -------------------------
    # Already notified
    # -------------------------

    if log_entry.whatsapp_notified:
        print("[STOP] WhatsApp already sent.")
        return

    customer = log_entry.customer

    print("\nCustomer Details")
    print("-----------------------------")
    print("Name            :", customer.name)
    print("Phone           :", customer.phone)
    print("Total Purchase  :", customer.total_purchase)

    # -------------------------
    # AI Message Setting
    # -------------------------

    ai_enabled = False

    try:
        from face_recognition_app.models_settings import SystemSettings

        ai_enabled = bool(
            getattr(
                SystemSettings.load(),
                "ai_vip_messages_enabled",
                False,
            )
        )

    except Exception as e:
        print("AI Settings Error:", e)

    print("AI Enabled :", ai_enabled)

    # -------------------------
    # Send WhatsApp
    # -------------------------

    try:

        if ai_enabled:

            print("\nGenerating AI message...")

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

            print("\nAI Message")
            print("--------------------------------")
            print(message)
            print("--------------------------------")

            sent = whatsapp_service.send_text(
                whatsapp_service.manager_number,
                message,
            )

        else:

            print("\nSending default VIP message...")

            sent = whatsapp_service.notify_vip_arrival(
                customer_name=customer.name,
                phone=customer.phone,
                total_purchase=customer.total_purchase,
                arrived_at=log_entry.recognized_at or timezone.now(),
            )

        print("\nWhatsApp Send Result :", sent)

    except Exception as e:

        print("\nERROR while sending WhatsApp")
        print(e)

        logger.exception(e)
        return

    # -------------------------
    # Save notification status
    # -------------------------

    if sent:

        log_entry.whatsapp_notified = True
        log_entry.save(update_fields=["whatsapp_notified"])

        print("[SUCCESS] Notification sent successfully.")
        print("[SUCCESS] Database updated.")

        logger.info(
            "WhatsApp VIP alert sent for %s (AI=%s)",
            customer.name,
            ai_enabled,
        )

    else:

        print("[FAILED] WhatsApp notification failed.")

        logger.warning(
            "WhatsApp VIP alert NOT sent for %s",
            customer.name,
        )

    print("=" * 60)