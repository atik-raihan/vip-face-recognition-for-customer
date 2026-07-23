"""
NEW FILE -- does not touch views.py.
"""
from django.contrib.auth.decorators import login_required
from django.shortcuts import render
from django.utils import timezone

from .models_attendance import EmployeeAttendanceLog


@login_required
def attendance_log(request):
    today = timezone.localdate()
    logs = (
        EmployeeAttendanceLog.objects.filter(timestamp__date=today)
        .select_related("employee")
        .order_by("-timestamp")
    )
    return render(
        request,
        "face_recognition_app/attendance.html",
        {"logs": logs, "today": today},
    )

