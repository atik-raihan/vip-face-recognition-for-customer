import os
import sys
import django

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")
django.setup()

from django.template.loader import get_template
from django.urls import reverse
from face_recognition_app.models import EmployeeAttendanceLog, Employee

print("=" * 50)
print("Attendance Verification")
print("=" * 50)

failed = False

# --------------------------------------------------
# Attendance Template
# --------------------------------------------------

try:
    get_template("face_recognition_app/attendance.html")
    print("[OK] Attendance template found")
except Exception as e:
    print("[FAIL] Attendance template missing")
    print(e)
    failed = True

# --------------------------------------------------
# Attendance URL
# --------------------------------------------------

try:
    print("[OK] Attendance URL:", reverse("employee_attendance"))
except Exception as e:
    print("[FAIL] Attendance URL missing")
    print(e)
    failed = True

# --------------------------------------------------
# Employee Count
# --------------------------------------------------

try:
    employees = Employee.objects.count()
    print(f"[OK] Employees : {employees}")
except Exception as e:
    print("[FAIL] Employee model error")
    print(e)
    failed = True

# --------------------------------------------------
# Attendance Records
# --------------------------------------------------

try:
    attendance = EmployeeAttendanceLog.objects.count()
    print(f"[OK] Attendance Records : {attendance}")
except Exception as e:
    print("[FAIL] Attendance model error")
    print(e)
    failed = True

# --------------------------------------------------
# Latest Attendance
# --------------------------------------------------

try:
    latest = EmployeeAttendanceLog.objects.order_by("-id").first()

    if latest:
        print("[OK] Latest Attendance Record Found")
    else:
        print("[WARNING] No attendance records found")
except Exception as e:
    print("[FAIL] Could not read attendance records")
    print(e)
    failed = True

print("=" * 50)

if failed:
    print("[FAIL] Attendance verification failed.")
    sys.exit(1)

print("[OK] Attendance verification passed.")
sys.exit(0)