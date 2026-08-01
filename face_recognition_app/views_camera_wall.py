from django.shortcuts import render

from .models import Camera


def camera_wall(request):
    """
    Display all active cameras in a CCTV-style dashboard.
    """

    cameras = (
        Camera.objects
        .filter(is_active=True)
        .order_by("id")
    )

    context = {
        "cameras": cameras,
    }

    return render(
        request,
        "face_recognition_app/camera_wall.html",
        context,
    )