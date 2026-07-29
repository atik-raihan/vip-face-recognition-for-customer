import os
import sys
import django

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")
django.setup()

from django.template.loader import get_template
from django.urls import reverse
from face_recognition_app.models import RecognitionLog

print("=" * 50)
print("Dashboard Verification")
print("=" * 50)

failed = False

# --------------------------------------------------
# Dashboard template
# --------------------------------------------------

try:
    get_template("face_recognition_app/dashboard.html")
    print("[OK] Dashboard template found")
except Exception as e:
    print("[FAIL] Dashboard template missing")
    print(e)
    failed = True

# --------------------------------------------------
# Dashboard URL
# --------------------------------------------------

try:
    print("[OK] Dashboard URL:", reverse("recognition_dashboard"))
except Exception as e:
    print("[FAIL] Dashboard URL not found")
    print(e)
    failed = True

# --------------------------------------------------
# Dashboard Stats
# --------------------------------------------------


# --------------------------------------------------
# Recognition Logs
# --------------------------------------------------

try:
    logs = RecognitionLog.objects.count()
    print(f"[OK] Recognition Logs : {logs}")
except Exception as e:
    print("[FAIL] RecognitionLog error")
    print(e)
    failed = True

# --------------------------------------------------

print("=" * 50)

if failed:
    print("[FAIL] Dashboard verification failed.")
    sys.exit(1)

print("[OK] Dashboard verification passed.")
sys.exit(0)