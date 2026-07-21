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
    
    try:
        stream = gen_frames(camera_source=0, camera_obj=None)
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

# make sure this import already exists or add it


def recognition_dashboard(request):
    today = timezone.localdate()

    todays_logs = (
        RecognitionLog.objects
        .select_related("customer", "camera")
        .filter(created_at__date=today)
        .order_by("-created_at")
    )

    total_recognitions = todays_logs.count()
    vip_recognitions = todays_logs.filter(was_vip_at_time=True).count()
    normal_recognitions = total_recognitions - vip_recognitions

    unique_vip_customers = (
        todays_logs
        .filter(was_vip_at_time=True)
        .values("customer_id")
        .distinct()
        .count()
    )

    context = {
        "total_recognitions": total_recognitions,
        "vip_recognitions": vip_recognitions,
        "normal_recognitions": normal_recognitions,
        "unique_vip_customers": unique_vip_customers,
        "recent_logs": todays_logs[:50],
        "today": today,
    }
    return render(request, "face_recognition/recognition_dashboard.html", context)