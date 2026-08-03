from django.shortcuts import render
from django.http import StreamingHttpResponse, Http404, JsonResponse
from django.views.decorators.gzip import gzip_page
from django.utils import timezone
from datetime import timedelta

from .camera.live_ai_camera import gen_frames
from .models import RecognitionLog


# How fresh a recognition needs to be to count as "just walked in" for POS
# auto-select purposes. Keeps old/stale recognitions from re-popping the
# Welcome Back modal if the POS page is left open a while.
POS_RECOGNITION_FRESHNESS_SECONDS = 20


def camera(request):
    """
    Renders the camera page.
    """
    return render(request, "face_recognition_app/camera.html")


@gzip_page
def video_feed(request):
    camera_id = request.GET.get("camera_id")
    camera_obj = None
    source = None

    if camera_id:
        from .models import Camera

        camera_obj = Camera.objects.filter(
            id=camera_id,
            is_active=True
        ).first()

        if camera_obj:
            source = camera_obj.connection_string

            if camera_obj.source_type in ("webcam", "usb"):
                try:
                    source = int(source)
                except (TypeError, ValueError):
                    source = 0

    if source is None:
        from .models_settings import SystemSettings

        settings_row = SystemSettings.load()
        default_source = getattr(settings_row, "default_camera_source", None)

        source = default_source if default_source is not None else 0

        if isinstance(source, str) and source.isdigit():
            source = int(source)

    try:
        stream = gen_frames(
            camera_source=source,
            camera_obj=camera_obj,
        )
    except RuntimeError as exc:
        raise Http404(str(exc))

    return StreamingHttpResponse(
        stream,
        content_type="multipart/x-mixed-replace; boundary=frame",
    )


def latest_recognition(request):
    """
    Polling endpoint for POS.
    """

    since_id = request.GET.get("since_id")

    logs = RecognitionLog.objects.filter(
        customer__isnull=False
    ).select_related("customer")

    if since_id:
        try:
            logs = logs.filter(id__gt=int(since_id))
        except (TypeError, ValueError):
            pass

    log = logs.order_by("-id").first()

    if log is None:
        return JsonResponse({
            "new": False
        })

    customer = log.customer

    return JsonResponse({

        "new": True,
        "log_id": log.id,

        "customer_id": customer.id,
        "customer_name": customer.name,
        "phone": customer.phone,

        "is_vip": log.was_vip_at_time,
        "total_purchase": str(customer.total_purchase),
        "confidence": log.confidence,

    })


def recognition_dashboard(request):
    """
    Recognition Dashboard.
    """

    today_start = timezone.localtime().replace(
        hour=0,
        minute=0,
        second=0,
        microsecond=0,
    )

    todays_logs = RecognitionLog.objects.filter(
        recognized_at__gte=today_start
    )

    todays_total = todays_logs.count()

    vip_visits_today = todays_logs.filter(
        was_vip_at_time=True
    ).count()

    normal_visits_today = todays_logs.filter(
        customer__isnull=False,
        was_vip_at_time=False,
    ).count()

    unknown_visits_today = todays_logs.filter(
        customer__isnull=True
    ).count()

    recent_recognitions = (
        RecognitionLog.objects.select_related("customer")
        .order_by("-recognized_at")[:20]
    )

    context = {
        "todays_total": todays_total,
        "vip_visits_today": vip_visits_today,
        "normal_visits_today": normal_visits_today,
        "unknown_visits_today": unknown_visits_today,
        "recent_recognitions": recent_recognitions,
    }

    return render(
        request,
        "face_recognition_app/dashboard.html",
        context,
    )