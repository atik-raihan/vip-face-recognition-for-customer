from django.shortcuts import render
from django.utils import timezone

from .models_attendance import EmployeeAttendanceLog


def attendance_dashboard(request):
    """
    Employee Attendance Analytics Dashboard - separate from the existing
    /camera/attendance/ list page (untouched), this adds the summary
    stats + recent activity view for item 12's "analytics" scope.
    """
    today_start = timezone.localtime().replace(hour=0, minute=0, second=0, microsecond=0)

    todays_logs = EmployeeAttendanceLog.objects.filter(recognized_at__gte=today_start)

    todays_total_events = todays_logs.count()
    unique_employees_today = todays_logs.values("employee_id").distinct().count()
    checkins_today = todays_logs.filter(event_type=EmployeeAttendanceLog.CHECK_IN).count()
    checkouts_today = todays_logs.filter(event_type=EmployeeAttendanceLog.CHECK_OUT).count()

    recent_logs = (
        EmployeeAttendanceLog.objects.select_related("employee")
        .order_by("-recognized_at")[:20]
    )

    context = {
        "todays_total_events": todays_total_events,
        "unique_employees_today": unique_employees_today,
        "checkins_today": checkins_today,
        "checkouts_today": checkouts_today,
        "recent_logs": recent_logs,
    }
    return render(request, "face_recognition_app/attendance_dashboard.html", context)

