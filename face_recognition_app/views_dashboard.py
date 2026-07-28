from django.contrib.auth.decorators import login_required
from django.db.models import Count
from django.http import JsonResponse
from django.shortcuts import render
from django.utils import timezone

from .models import RecognitionLog


@login_required
def recognition_dashboard(request):
    today = timezone.localdate()
    today_logs = RecognitionLog.objects.filter(recognized_at__date=today)

    context = {
        "today_total": today_logs.count(),
        "today_vip": today_logs.filter(was_vip_at_time=True).count(),
        "today_normal": today_logs.filter(customer__isnull=False, was_vip_at_time=False).count(),
        "today_unknown": today_logs.filter(customer__isnull=True).count(),
        "recent_logs": RecognitionLog.objects.select_related("customer", "camera").order_by("-recognized_at")[:20],
    }

    return render(request, "face_recognition_app/recognition_dashboard.html", context)


@login_required
def recognition_dashboard_api(request):
    today = timezone.localdate()
    today_logs = RecognitionLog.objects.filter(recognized_at__date=today)

    latest = []
    for log in RecognitionLog.objects.select_related("customer", "camera").order_by("-recognized_at")[:10]:
        latest.append({
            "id": log.id,
            "customer_name": log.customer.name if log.customer else "Unknown",
            "was_vip": log.was_vip_at_time,
            "confidence": round(log.confidence, 2) if log.confidence else None,
            "camera_name": log.camera.name if log.camera else "Default",
            "timestamp": timezone.localtime(log.recognized_at).strftime("%H:%M:%S"),
            "snapshot_url": log.snapshot.url if log.snapshot else None,
        })

    return JsonResponse({
        "today_total": today_logs.count(),
        "today_vip": today_logs.filter(was_vip_at_time=True).count(),
        "today_normal": today_logs.filter(customer__isnull=False, was_vip_at_time=False).count(),
        "latest": latest,
    })
