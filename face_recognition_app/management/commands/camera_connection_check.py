import os
import sys
import django
import cv2

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")
django.setup()

from face_recognition_app.models import Camera

print("=" * 60)
print("Live Camera Connection Test")
print("=" * 60)

failed = 0
tested = 0

active_cameras = Camera.objects.filter(is_active=True).order_by("id")

if not active_cameras.exists():
    print("[WARNING] No active cameras found.")
    sys.exit(0)

for camera in active_cameras:

    print()
    print(f"Camera #{camera.id} : {camera.name}")

    source = camera.connection_string

    if camera.source_type.lower() in ("webcam", "usb"):
        try:
            source = int(source)
        except:
            source = 0

    cap = cv2.VideoCapture(source)

    if not cap.isOpened():
        print("[FAIL] Could not open camera.")
        failed += 1
        continue

    ok, frame = cap.read()

    if not ok or frame is None:
        print("[FAIL] Camera opened but no frame received.")
        cap.release()
        failed += 1
        continue

    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    fps = cap.get(cv2.CAP_PROP_FPS)

    print("[OK] Camera opened successfully.")
    print(f"Resolution : {width} x {height}")
    print(f"FPS        : {fps:.2f}")

    cap.release()

    tested += 1

print()
print("=" * 60)
print(f"Tested : {tested}")
print(f"Failed : {failed}")
print("=" * 60)

if failed:
    print("[FAIL] One or more cameras failed.")
    sys.exit(1)

print("[OK] All active cameras are working.")
sys.exit(0)