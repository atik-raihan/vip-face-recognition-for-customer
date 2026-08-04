"""
face_recognition_app/camera/live_ai_camera.py

Full AI recognition pipeline that face_recognition_app/views.py wraps in a
StreamingHttpResponse:

    OpenCV --> Face Detection --> Embedding --> Compare --> Recognize
    --> Confidence % --> VIP Badge --> RecognitionLog entry

Includes a small in-process de-duplication cache so the same person
standing in front of the camera doesn't create a new RecognitionLog row
(and trigger a WhatsApp message) on every single frame.
"""

import time
import threading
from io import BytesIO

import cv2
from django.core.files.base import ContentFile
from django.utils import timezone

from face_recognition_app.services.face_service import FaceService
from face_recognition_app.models import RecognitionLog, Camera
from face_recognition_app.services.employee_recognition_service import EmployeeRecognitionService

# Colors (BGR) for overlay drawing
COLOR_VIP = (0, 215, 255)       # gold
COLOR_KNOWN = (0, 200, 0)       # green
COLOR_UNKNOWN = (0, 0, 220)     # red
COLOR_STAFF = (255, 165, 0)  # orange -- adjust to taste

# Avoid re-logging / re-notifying the same customer within this window (seconds)
DEDUPE_WINDOW_SECONDS = 60

_recent_recognitions_lock = threading.Lock()
_recent_recognitions = {}  # {customer_id_or_"unknown": last_seen_timestamp}


def _should_log(key: str) -> bool:
    now = time.time()
    with _recent_recognitions_lock:
        last_seen = _recent_recognitions.get(key)
        if last_seen is not None and (now - last_seen) < DEDUPE_WINDOW_SECONDS:
            return False
        _recent_recognitions[key] = now
        return True


def _draw_label(frame, bbox, text, color):
    x1, y1, x2, y2 = bbox

    # Face rectangle
    cv2.rectangle(
        frame,
        (x1, y1),
        (x2, y2),
        color,
        3,
    )

    font = cv2.FONT_HERSHEY_SIMPLEX
    font_scale = 0.65
    thickness = 2

    (tw, th), _ = cv2.getTextSize(
        text,
        font,
        font_scale,
        thickness,
    )

    # Background
    cv2.rectangle(
        frame,
        (x1, y1 - th - 12),
        (x1 + tw + 12, y1),
        color,
        -1,
    )

    text_color = (0, 0, 0) if color == COLOR_VIP else (255, 255, 255)

    cv2.putText(
        frame,
        text,
        (x1 + 6, y1 - 6),
        font,
        font_scale,
        text_color,
        thickness,
        cv2.LINE_AA,
    )


def _save_snapshot(frame, bbox, log_entry: RecognitionLog):
    """Crop the recognized face (with a small margin) and attach it to the log."""
    x1, y1, x2, y2 = bbox
    h, w = frame.shape[:2]
    margin_x = int((x2 - x1) * 0.25)
    margin_y = int((y2 - y1) * 0.25)
    x1c, y1c = max(0, x1 - margin_x), max(0, y1 - margin_y)
    x2c, y2c = min(w, x2 + margin_x), min(h, y2 + margin_y)

    crop = frame[y1c:y2c, x1c:x2c]
    success, buffer = cv2.imencode(".jpg", crop)
    if not success:
        return
    log_entry.image_snapshot.save(
        f"snapshot_{log_entry.pk or 'new'}.jpg",
        ContentFile(BytesIO(buffer).getvalue()),
        save=False,
    )


def _handle_recognition_event(frame, bbox, match, camera_obj):
    """
    Create a RecognitionLog row for this event. WhatsApp notification
    (item 7) and POS auto-select (item 6) hook in here via a lazily
    imported `on_customer_recognized` function once that piece is built —
    this file works standalone right now, before that module exists.
    """
    from customers.models import Customer  # local import avoids app-loading order issues

    customer_obj = None
    is_vip = False
    confidence = 0.0
    dedupe_key = "unknown"

    if match is not None:
        print("=" * 60)
        print("MATCH DATA")
        print(match)
        print("Customer ID:", match.get("customer_id"))

        customer_obj = Customer.objects.filter(id=match["customer_id"]).first()

        print("Customer Obj:", customer_obj)
        print("Customer Count:", Customer.objects.count())
        print("=" * 60)

        is_vip = match.get("vip", False)
        confidence = match["confidence"]
        dedupe_key = f"customer_{match['customer_id']}"
    from datetime import timedelta

    cutoff = timezone.now() - timedelta(seconds=DEDUPE_WINDOW_SECONDS)

    if customer_obj is not None:

        already_logged = RecognitionLog.objects.filter(
            customer=customer_obj,
            recognized_at__gte=cutoff,
        ).exists()

    else:

        already_logged = RecognitionLog.objects.filter(
            customer__isnull=True,
            recognized_at__gte=cutoff,
        ).exists()

    if already_logged:
        return
    log_entry = RecognitionLog(
        customer=customer_obj,
        confidence=confidence,
        camera=camera_obj,
        camera_name=camera_obj.name if camera_obj else "Default Camera",
        recognized_at=timezone.now(),
        was_vip_at_time=is_vip,
    )
    _save_snapshot(frame, bbox, log_entry)
    log_entry.save()

    try:
        from face_recognition_app.services.recognition_events import on_customer_recognized
        print("\nCalling on_customer_recognized()...")
        on_customer_recognized(log_entry)
        print("Finished on_customer_recognized()")
    except Exception as e:
        print("\nRecognition Event Error")
        print(type(e).__name__)
        print(e)

def gen_frames(camera_source=0, camera_obj: Camera = None):
    """
    Generator that yields MJPEG-encoded frames with recognition overlays.
    Opens the camera device fresh on each call (unlike the old global
    cv2.VideoCapture(0) opened once at import time) so it can be reused
    for multiple camera sources without blocking.
    """
    face_service = FaceService.get_instance()
    employee_recognition_service = EmployeeRecognitionService.get_instance()
    cap = cv2.VideoCapture(camera_source, cv2.CAP_DSHOW)

    if not cap.isOpened():
        raise RuntimeError(f"Unable to open camera source: {camera_source}")

    try:
        while True:
            success, frame = cap.read()
            if not success:
                break

            faces = face_service.detect_faces(frame)

            for face in faces:
                bbox = face["bbox"]
                match = face_service.recognize(face["embedding"])

                if match is not None and match.get("vip"):
                    color = COLOR_VIP
                    label = f"VIP: {match['customer_name']} ({match['confidence']*100:.1f}%)"
                elif match is not None:
                    color = COLOR_KNOWN
                    label = f"{match['customer_name']} ({match['confidence']*100:.1f}%)"
                else:
                    # Not a known customer -- check the employee pool before
                    # falling back to "Unknown" (Item 12).
                    employee, emp_confidence = employee_recognition_service.recognize(face["embedding"])
                    if employee is not None:
                        color = COLOR_STAFF
                        label = f"Staff: {employee.name} ({emp_confidence*100:.1f}%)"
                        employee_recognition_service.log_attendance(
                            employee,
                            emp_confidence,
                            camera=camera_obj,
                            camera_name=camera_obj.name if camera_obj else "",
                        )
                    else:
                        color = COLOR_UNKNOWN
                        label = "Unknown Customer"

                _draw_label(frame, bbox, label, color)
                _handle_recognition_event(frame, bbox, match, camera_obj)

            success, buffer = cv2.imencode(".jpg", frame)
            if not success:
                continue

            yield (
                b"--frame\r\n"
                b"Content-Type: image/jpeg\r\n\r\n" + buffer.tobytes() + b"\r\n"
            )
    finally:
        cap.release()
