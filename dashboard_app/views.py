import requests
from django.shortcuts import render
from .models import DashboardStats

FASTAPI_BASE_URL = "http://localhost:8000"


def dashboard(request):
    stats = DashboardStats.objects.first()
    if not stats:
        stats = DashboardStats.objects.create()

    # Pull live data from the FastAPI backend. Fail gracefully if it's
    # offline - the Django dashboard shouldn't crash just because the
    # camera/recognition service isn't running.
    camera_status = "OFFLINE"
    live_summary = None

    try:
        cam_resp = requests.get(f"{FASTAPI_BASE_URL}/camera/status", timeout=2)
        if cam_resp.ok:
            camera_status = cam_resp.json().get("status", "unknown").upper()
    except requests.RequestException:
        pass

    try:
        summary_resp = requests.get(f"{FASTAPI_BASE_URL}/dashboard/summary", timeout=2)
        if summary_resp.ok:
            live_summary = summary_resp.json()
    except requests.RequestException:
        pass

    context = {
        "stats": stats,
        "camera_status": camera_status,
        "live_summary": live_summary,
    }
    return render(request, "dashboard/index.html", context)