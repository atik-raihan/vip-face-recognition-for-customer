from django.shortcuts import render
from django.db.models import Sum
from django.utils import timezone
from customers.models import Customer
from sales.models import Sale
from face_recognition_app.models import RecognitionLog

FASTAPI_BASE_URL = "http://localhost:8000"


def dashboard(request):
    # REAL DATA from your actual models
    total_customers = Customer.objects.count()
    total_vip = Customer.objects.filter(is_vip=True).count()

    # Revenue from sales
    revenue_data = Sale.objects.aggregate(total=Sum('total'))
    total_revenue = revenue_data['total'] or 0

    # Today's orders
    today = timezone.now().date()
    todays_orders = Sale.objects.filter(created_at__date=today).count()

    # Recent transactions (last 10 sales)
    recent_sales = Sale.objects.select_related('customer').order_by('-created_at')[:10]

    # Camera status
    camera_status = "OFFLINE"
    try:
        import requests
        cam_resp = requests.get(f"{FASTAPI_BASE_URL}/camera/status", timeout=2)
        if cam_resp.ok:
            camera_status = cam_resp.json().get("status", "unknown").upper()
    except Exception:
        pass

    # Last VIP detection
    last_vip = RecognitionLog.objects.filter(
        customer__isnull=False,
        was_vip_at_time=True
    ).select_related('customer').order_by('-recognized_at').first()

    context = {
        "total_customers": total_customers,
        "total_vip": total_vip,
        "total_revenue": total_revenue,
        "todays_orders": todays_orders,
        "recent_sales": recent_sales,
        "camera_status": camera_status,
        "last_vip": last_vip,
    }
    return render(request, "dashboard/index.html", context)