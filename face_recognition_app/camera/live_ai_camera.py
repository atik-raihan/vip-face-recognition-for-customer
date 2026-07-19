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

# Colors (BGR) for overlay drawing
COLOR_VIP = (0, 215, 255)       # gold
COLOR_KNOWN = (0, 200, 0)       # green
COLOR_UNKNOWN = (0, 0, 220)     # red

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
    cv2.rectangle(frame, (x1, y1), (x2, y2), color, 2)

    (text_w, text_h), _ = cv2.getTextSize(text, cv2.FONT_HERSHEY_SIMPLEX, 0.6, 2)
    cv2.rectangle(frame, (x1, y1 - text_h - 12), (x1 + text_w + 10, y1), color, -1)
    cv2.putText(
        frame,
        text,
        (x1 + 5, y1 - 6),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.6,
        (0, 0, 0) if color == COLOR_VIP else (255, 255, 255),
        2,
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
        customer_obj = Customer.objects.filter(id=match["customer_id"]).first()
        is_vip = match.get("vip", False)
        confidence = match["confidence"]
        dedupe_key = f"customer_{match['customer_id']}"

    if not _should_log(dedupe_key):
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

        on_customer_recognized(log_entry)
    except ImportError:
        pass


def gen_frames(camera_source=0, camera_obj: Camera = None):
    """
    Generator that yields MJPEG-encoded frames with recognition overlays.
    Opens the camera device fresh on each call (unlike the old global
    cv2.VideoCapture(0) opened once at import time) so it can be reused
    for multiple camera sources without blocking.
    """
    face_service = FaceService.get_instance()
    cap = cv2.VideoCapture(camera_source)

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
