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
    Renders the camera page. Same view name/URL as before — camera.html
    still points at {% url 'video_feed' %}, unchanged.
    """
    return render(request, "face_recognition_app/camera.html")


@gzip_page
def video_feed(request):
    camera_id = request.GET.get("camera_id")
    camera_obj = None
    source = None

    if camera_id:
        from .models import Camera
        camera_obj = Camera.objects.filter(id=camera_id, is_active=True).first()
        if camera_obj:
            source = camera_obj.connection_string  # NOT camera.source — that field doesn't exist
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

    try:
        stream = gen_frames(camera_source=source, camera_obj=camera_obj)
    except RuntimeError as exc:
        raise Http404(str(exc))

    return StreamingHttpResponse(
        stream, content_type="multipart/x-mixed-replace; boundary=frame"
    )


def latest_recognition(request):
    """
    Polling endpoint for the POS page's JavaScript (item 6).

    Query param `since_id` (optional): the last RecognitionLog id the
    client already showed a popup for. If the newest log is not newer
    than that, returns {"new": false} so the POS page doesn't re-show
    the same popup on every poll.

    Response when there's a fresh, known-customer recognition:
        {
            "new": true,
            "log_id": 42,
            "customer_id": 7,
            "customer_name": "John Doe",
            "phone": "017xxxxxxxx",
            "is_vip": true,
            "total_purchase": "18450.00",
            "confidence": 0.83
        }

    Response otherwise:
        {"new": false}

    Unknown-face recognitions (customer is null) are never surfaced here —
    POS has nothing useful to auto-select for an unrecognized visitor.
    """
    since_id = request.GET.get("since_id")
    cutoff = timezone.now() - timedelta(seconds=POS_RECOGNITION_FRESHNESS_SECONDS)

    qs = (
        RecognitionLog.objects.filter(
            customer__isnull=False,
            recognized_at__gte=cutoff,
        )
        .select_related("customer")
        .order_by("-recognized_at")
    )

    if since_id:
        try:
            qs = qs.exclude(id__lte=int(since_id))
        except (TypeError, ValueError):
            pass

    log_entry = qs.first()

    if log_entry is None:
        return JsonResponse({"new": False})

    customer = log_entry.customer
    return JsonResponse(
        {
            "new": True,
            "log_id": log_entry.id,
            "customer_id": customer.id,
            "customer_name": customer.name,
            "phone": customer.phone,
            "is_vip": log_entry.was_vip_at_time,
            "total_purchase": str(customer.total_purchase),
            "confidence": log_entry.confidence,
        }
    )


def recognition_dashboard(request):
    """
    Recognition Dashboard (item 5):
    - Today's total recognitions (known + unknown)
    - VIP visits today
    - Normal (known, non-VIP) visits today
    - Unknown visits today
    - Recent recognitions list (last 20), with snapshot thumbnail if available
    """
    today_start = timezone.localtime().replace(hour=0, minute=0, second=0, microsecond=0)

    todays_logs = RecognitionLog.objects.filter(recognized_at__gte=today_start)

    todays_total = todays_logs.count()
    vip_visits_today = todays_logs.filter(was_vip_at_time=True).count()
    normal_visits_today = todays_logs.filter(
        customer__isnull=False, was_vip_at_time=False
    ).count()
    unknown_visits_today = todays_logs.filter(customer__isnull=True).count()

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
    return render(request, "face_recognition_app/dashboard.html", context)
