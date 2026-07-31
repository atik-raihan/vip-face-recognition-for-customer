from datetime import timedelta

import io
import base64

import matplotlib

matplotlib.use("Agg")

import matplotlib.pyplot as plt

from django.shortcuts import render
from django.utils import timezone
from django.db.models import Count

from face_recognition_app.models import RecognitionLog
from sales.models import Sale
from face_recognition_app.models_attendance import EmployeeAttendanceLog


def _fig_to_base64():
    buffer = io.BytesIO()
    plt.tight_layout()
    plt.savefig(buffer, format="png")
    plt.close()
    buffer.seek(0)
    return base64.b64encode(buffer.read()).decode("utf-8")


def analytics_dashboard(request):

    today = timezone.localdate()
    start_date = today - timedelta(days=6)

    # ---------------------------------------------------
    # Daily Visitors
    # ---------------------------------------------------

    visitor_labels = []
    visitor_values = []

    for i in range(7):
        day = start_date + timedelta(days=i)

        count = RecognitionLog.objects.filter(
            recognized_at__date=day
        ).count()

        visitor_labels.append(day.strftime("%a"))
        visitor_values.append(count)

    plt.figure(figsize=(7, 3.5))
    plt.plot(visitor_labels, visitor_values, marker="o", linewidth=2)
    plt.title("Daily Visitors")
    plt.xlabel("Day")
    plt.ylabel("Visitors")

    visitors_chart = _fig_to_base64()

    # ---------------------------------------------------
    # VIP Visits
    # ---------------------------------------------------

    vip_labels = []
    vip_values = []

    for i in range(7):
        day = start_date + timedelta(days=i)

        count = RecognitionLog.objects.filter(
            recognized_at__date=day,
            was_vip_at_time=True,
        ).count()

        vip_labels.append(day.strftime("%a"))
        vip_values.append(count)

    plt.figure(figsize=(7, 3.5))
    plt.bar(vip_labels, vip_values)
    plt.title("VIP Visits This Week")
    plt.xlabel("Day")
    plt.ylabel("VIP Visits")

    vip_chart = _fig_to_base64()

    # ---------------------------------------------------
    # Recognition Success Rate
    # ---------------------------------------------------

    total_logs = RecognitionLog.objects.count()

    matched_logs = RecognitionLog.objects.exclude(
        customer=None
    ).count()

    unknown_logs = total_logs - matched_logs

    plt.figure(figsize=(5, 5))
    plt.pie(
        [matched_logs, unknown_logs],
        labels=["Recognized", "Unknown"],
        autopct="%1.1f%%",
    )
    plt.title("Recognition Success Rate")

    recognition_chart = _fig_to_base64()

    # ---------------------------------------------------
    # Sales by Day
    # ---------------------------------------------------

    sales_labels = []
    sales_values = []

    for i in range(7):
        day = start_date + timedelta(days=i)

        total = (
            Sale.objects.filter(
                created_at__date=day
            ).aggregate(total=Count("id"))
        )["total"] or 0

        sales_labels.append(day.strftime("%a"))
        sales_values.append(total)

    plt.figure(figsize=(7, 3.5))
    plt.plot(sales_labels, sales_values, marker="o")
    plt.title("Sales by Day")
    plt.xlabel("Day")
    plt.ylabel("Sales")

    sales_chart = _fig_to_base64()

    # ---------------------------------------------------
    # Attendance Trend
    # ---------------------------------------------------

    attendance_labels = []
    attendance_values = []

    for i in range(7):
        day = start_date + timedelta(days=i)

        total = EmployeeAttendanceLog.objects.filter(
            timestamp__date=day
        ).count()

        attendance_labels.append(day.strftime("%a"))
        attendance_values.append(total)

    plt.figure(figsize=(7, 3.5))
    plt.bar(attendance_labels, attendance_values)
    plt.title("Attendance Trend")
    plt.xlabel("Day")
    plt.ylabel("Attendance")

    attendance_chart = _fig_to_base64()

    context = {
        "visitors_chart": visitors_chart,
        "vip_chart": vip_chart,
        "recognition_chart": recognition_chart,
        "sales_chart": sales_chart,
        "attendance_chart": attendance_chart,
    }

    return render(
        request,
        "face_recognition_app/analytics_dashboard.html",
        context,
    )