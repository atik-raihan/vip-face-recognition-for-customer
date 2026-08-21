from django.shortcuts import render
from django.http import StreamingHttpResponse, Http404, JsonResponse
from django.views.decorators.gzip import gzip_page
from django.utils import timezone
from datetime import timedelta
from django.shortcuts import get_object_or_404
from django.db import models
from .utils import chart_to_base64

from .camera.live_ai_camera import gen_frames
from .models import RecognitionLog
from django.contrib.auth.decorators import login_required

# Recognition remains "fresh" for POS popup
POS_RECOGNITION_FRESHNESS_SECONDS = 20


def camera(request):
    """
    Camera page.
    """
    return render(
        request,
        "face_recognition_app/camera.html"
    )


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

            if camera_obj.source_type in (
                "webcam",
                "usb"
            ):

                try:
                    source = int(source)

                except (TypeError, ValueError):
                    source = 0

    if source is None:

        from .models_settings import SystemSettings

        settings_row = SystemSettings.load()

        default_source = getattr(
            settings_row,
            "default_camera_source",
            None
        )

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

    cutoff = timezone.now() - timedelta(
        seconds=POS_RECOGNITION_FRESHNESS_SECONDS
    )

    logs = (
        RecognitionLog.objects.filter(
            customer__isnull=False
        )
        .select_related("customer")
        .order_by("-id")
    )

    if since_id:

        try:

            logs = logs.filter(
                id__gt=int(since_id)
            )

        except (TypeError, ValueError):
            pass

    log = logs.first()

    if log is None:

        return JsonResponse({
            "new": False
        })

    customer = log.customer

    if customer is None:

        return JsonResponse({
            "new": False
        })

    return JsonResponse({

        "new": True,

        "log_id": log.id,

        "customer_id": customer.id,

        "customer_name": customer.name,

        "phone": customer.phone,

        "is_vip": log.was_vip_at_time,

        "total_purchase": str(customer.total_purchase),

        "confidence": log.confidence,

        "photo": (
            log.image_snapshot.url
            if log.image_snapshot
            else ""
        ),

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
        RecognitionLog.objects
        .select_related("customer")
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

# ============================================================
# CUSTOMER INSIGHTS: Visit History, Recommendations
# ============================================================

from django.db.models import Count, Sum


@login_required
def customer_visit_history(request, customer_id):
    """Return last 10 visits for a customer."""
    from customers.models import Customer
    customer = get_object_or_404(Customer, id=customer_id)

    visits = (
        RecognitionLog.objects.filter(customer=customer)
        .order_by("-recognized_at")[:10]
    )

    history = []
    for v in visits:
        history.append({
            "id": v.id,
            "date": v.recognized_at.strftime("%Y-%m-%d %H:%M") if v.recognized_at else None,
            "confidence": round(v.confidence, 2) if v.confidence else None,
            "camera": v.camera_name or "Default",
            "snapshot": v.image_snapshot.url if v.image_snapshot else None,
        })

    return JsonResponse({
        "customer_name": customer.name,
        "total_visits": RecognitionLog.objects.filter(customer=customer).count(),
        "history": history,
    })


@login_required
def customer_purchase_recommendations(request, customer_id):
    """Return top 5 frequently bought products for a customer."""
    from customers.models import Customer
    customer = get_object_or_404(Customer, id=customer_id)

    try:
        from sales.models import SaleItem
        frequent = (
            SaleItem.objects.filter(sale__customer=customer)
            .values("product__name", "product__id")
            .annotate(count=Count("id"), total_qty=Sum("quantity"))
            .order_by("-count")[:5]
        )
        items = [
            {
                "product_id": f["product__id"],
                "name": f["product__name"],
                "times_bought": f["count"],
                "total_quantity": f["total_qty"],
            }
            for f in frequent
        ]
    except Exception:
        items = []

    return JsonResponse({
        "customer_name": customer.name,
        "recommendations": items,
    })

# ============================================================
# POS CUSTOMER SEARCH API
# ============================================================

@login_required
def pos_customer_search(request):
    """Search customers by name or phone for POS dropdown."""
    query = request.GET.get("q", "").strip()
    if not query or len(query) < 2:
        return JsonResponse({"results": []})

    from customers.models import Customer
    customers = Customer.objects.filter(
        models.Q(name__icontains=query) | models.Q(phone__icontains=query)
    )[:10]

    results = []
    for c in customers:
        results.append({
            "id": c.id,
            "name": c.name,
            "phone": getattr(c, "phone", "") or "",
            "total_purchase": getattr(c, "total_purchase", 0) or 0,
            "is_vip": getattr(c, "is_vip", False) or getattr(c, "vip", False),
        })

    return JsonResponse({"results": results})

# ============================================================
# UNKNOWN VISITOR GALLERY
# ============================================================

@login_required
def unknown_visitor_gallery(request):
    unknown_logs = (
        RecognitionLog.objects.filter(customer__isnull=True)
        .order_by("-recognized_at")[:50]
    )
    unknown_count = RecognitionLog.objects.filter(customer__isnull=True).count()

    return render(request, "face_recognition_app/unknown_visitor_gallery.html", {
        "unknown_logs": unknown_logs,
        "unknown_count": unknown_count,
    })

@login_required
def customer_visit_history_page(request, customer_id):
    from customers.models import Customer
    customer = get_object_or_404(Customer, id=customer_id)

    history = (
        RecognitionLog.objects.filter(customer=customer)
        .order_by("-recognized_at")[:10]
    )
    total_visits = RecognitionLog.objects.filter(customer=customer).count()

    try:
        from sales.models import SaleItem
        recommendations = (
            SaleItem.objects.filter(sale__customer=customer)
            .values("product__name", "product__id")
            .annotate(count=Count("id"), total_qty=Sum("quantity"))
            .order_by("-count")[:5]
        )
        recs = [
            {
                "name": r["product__name"],
                "times_bought": r["count"],
                "total_quantity": r["total_qty"],
            }
            for r in recommendations
        ]
    except Exception:
        recs = []

    return render(request, "face_recognition_app/customer_visit_history.html", {
        "customer": customer,
        "history": history,
        "total_visits": total_visits,
        "recommendations": recs,
    })

# ============================================================
# ANALYTICS DASHBOARD
# ============================================================

from django.db.models import Count, Q
from django.utils import timezone
from datetime import timedelta


@login_required
def analytics_dashboard(request):
    today = timezone.now().date()

    # --- Daily (last 7 days) ---
    daily_labels = []
    daily_total = []
    daily_vip = []
    for i in range(6, -1, -1):
        day = today - timedelta(days=i)
        daily_labels.append(day.strftime("%a"))
        day_start = timezone.make_aware(timezone.datetime.combine(day, timezone.datetime.min.time()))
        day_end = timezone.make_aware(timezone.datetime.combine(day, timezone.datetime.max.time()))
        logs = RecognitionLog.objects.filter(recognized_at__range=(day_start, day_end))
        daily_total.append(logs.count())
        daily_vip.append(logs.filter(was_vip_at_time=True).count())

    # --- Weekly (last 4 weeks) ---
    weekly_labels = []
    weekly_total = []
    weekly_vip = []
    for i in range(3, -1, -1):
        week_start = today - timedelta(weeks=i+1)
        week_end = today - timedelta(weeks=i)
        weekly_labels.append("Week " + str(4-i))
        logs = RecognitionLog.objects.filter(recognized_at__date__gte=week_start, recognized_at__date__lt=week_end)
        weekly_total.append(logs.count())
        weekly_vip.append(logs.filter(was_vip_at_time=True).count())

    # --- Monthly (last 6 months) ---
    monthly_labels = []
    monthly_total = []
    monthly_vip = []
    for i in range(5, -1, -1):
        month = today.replace(day=1) - timedelta(days=i*30)
        monthly_labels.append(month.strftime("%b"))
        month_start = month.replace(day=1)
        next_month = (month.replace(day=28) + timedelta(days=4)).replace(day=1)
        month_start_dt = timezone.make_aware(timezone.datetime.combine(month_start, timezone.datetime.min.time()))
        month_end_dt = timezone.make_aware(timezone.datetime.combine(next_month, timezone.datetime.min.time()))
        logs = RecognitionLog.objects.filter(recognized_at__range=(month_start_dt, month_end_dt))
        monthly_total.append(logs.count())
        monthly_vip.append(logs.filter(was_vip_at_time=True).count())

    # --- Summary stats ---
    total_all_time = RecognitionLog.objects.count()
    total_vip_all_time = RecognitionLog.objects.filter(was_vip_at_time=True).count()
    total_unknown_all_time = RecognitionLog.objects.filter(customer__isnull=True).count()
    vip_percentage = round((total_vip_all_time / total_all_time * 100), 1) if total_all_time > 0 else 0

    # Top customers by visit count
    top_customers = (
        RecognitionLog.objects.exclude(customer__isnull=True)
        .values("customer__name", "customer__id")
        .annotate(visit_count=Count("id"))
        .order_by("-visit_count")[:10]
    )

    context = {
        "daily_labels": daily_labels,
        "daily_total": daily_total,
        "daily_vip": daily_vip,
        "weekly_labels": weekly_labels,
        "weekly_total": weekly_total,
        "weekly_vip": weekly_vip,
        "monthly_labels": monthly_labels,
        "monthly_total": monthly_total,
        "monthly_vip": monthly_vip,
        "total_all_time": total_all_time,
        "total_vip_all_time": total_vip_all_time,
        "total_unknown_all_time": total_unknown_all_time,
        "vip_percentage": vip_percentage,
        "top_customers": top_customers,
        # Matplotlib charts
        "daily_chart": chart_to_base64(daily_labels, daily_total, daily_vip, "Daily (Last 7 Days)", "line"),
        "weekly_chart": chart_to_base64(weekly_labels, weekly_total, weekly_vip, "Weekly (Last 4 Weeks)", "bar"),
        "monthly_chart": chart_to_base64(monthly_labels, monthly_total, monthly_vip, "Monthly (Last 6 Months)", "bar"),
    }
    return render(request, "face_recognition_app/analytics_dashboard.html", context)
# ============================================================
# ENHANCED POLLING API - visit count, last visit, recommendations
# ============================================================

from django.db.models import Count, Sum


@login_required
def latest_recognition_enhanced(request):
    since_id = request.GET.get("since_id")

    qs = RecognitionLog.objects.select_related("customer", "camera")
    if since_id:
        qs = qs.filter(id__gt=since_id)

    log = qs.order_by("-recognized_at").first()

    if not log:
        return JsonResponse({"new": False})

    customer = log.customer
    data = {
        "new": True,
        "log_id": log.id,
        "customer_id": customer.id if customer else None,
        "customer_name": customer.name if customer else "Unknown",
        "photo": log.image_snapshot.url if log.image_snapshot else None,
        "confidence": round(log.confidence, 2) if log.confidence else None,
        "is_vip": log.was_vip_at_time,
        "total_purchase": getattr(customer, "total_purchase", 0) if customer else 0,
        "recognized_at": log.recognized_at.isoformat() if log.recognized_at else None,
        "camera_name": log.camera_name or "Default",
    }

    if customer:
        visit_count = RecognitionLog.objects.filter(customer=customer).count()
        data["visit_count"] = visit_count
        last_visit = RecognitionLog.objects.filter(customer=customer).exclude(id=log.id).order_by("-recognized_at").first()
        data["last_visit"] = last_visit.recognized_at.isoformat() if last_visit else None

        try:
            from sales.models import SaleItem
            frequent_items = (
                SaleItem.objects.filter(sale__customer=customer)
                .values("product__name")
                .annotate(count=Count("id"))
                .order_by("-count")[:3]
            )
            data["frequent_items"] = [item["product__name"] for item in frequent_items]
        except Exception:
            data["frequent_items"] = []
    else:
        data["visit_count"] = 0
        data["last_visit"] = None
        data["frequent_items"] = []

    return JsonResponse(data)
