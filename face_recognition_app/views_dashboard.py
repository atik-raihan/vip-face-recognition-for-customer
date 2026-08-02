from django.shortcuts import render
from django.utils import timezone
from django.db.models import Count

from .models import (
    RecognitionLog,
    Camera,
)

from .models_branch import Branch


def recognition_dashboard(request):

    today = timezone.localdate()

    today_logs = RecognitionLog.objects.filter(
        recognized_at__date=today
    )

    total_recognitions = today_logs.count()

    unique_customers = (
        today_logs.exclude(customer=None)
        .values("customer")
        .distinct()
        .count()
    )

    vip_today = today_logs.filter(
        was_vip_at_time=True
    ).count()

    total_cameras = Camera.objects.count()

    active_cameras = Camera.objects.filter(
        is_active=True
    ).count()

    offline_cameras = (
        total_cameras - active_cameras
    )

    total_branches = Branch.objects.count()

    recent_logs = (
        RecognitionLog.objects
        .select_related(
            "customer",
            "camera",
        )
        .order_by("-recognized_at")[:20]
    )

    hourly_stats = (
        today_logs.extra(
            select={
                "hour": "strftime('%%H', recognized_at)"
            }
        )
        .values("hour")
        .annotate(total=Count("id"))
        .order_by("hour")
    )

    context = {

        # Recognition

        "total_recognitions": total_recognitions,
        "unique_customers": unique_customers,
        "vip_today": vip_today,

        # Camera

        "total_cameras": total_cameras,
        "active_cameras": active_cameras,
        "offline_cameras": offline_cameras,

        # Branch

        "total_branches": total_branches,

        # Tables

        "recent_logs": recent_logs,

        # Charts

        "hourly_stats": hourly_stats,
    }

    return render(
        request,
        "face_recognition_app/recognition_dashboard.html",
        context,
    )