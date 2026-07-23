"""
NEW FILE -- does not touch your existing views.py (camera, video_feed,
latest_recognition, recognition_dashboard all stay exactly as they are).

Covers Item 10 (settings page + camera CRUD UI).
"""
from django.contrib import messages
from django.contrib.auth.decorators import login_required
from django.shortcuts import get_object_or_404, redirect, render

from .forms_settings import CameraForm, SystemSettingsForm
from .models import Camera
from .models_settings import SystemSettings


@login_required
def settings_page(request):
    settings_obj = SystemSettings.load()

    if request.method == "POST" and "save_settings" in request.POST:
        form = SystemSettingsForm(request.POST, instance=settings_obj)
        if form.is_valid():
            form.save()
            messages.success(request, "Settings updated.")
            return redirect("recognition_settings")
    else:
        form = SystemSettingsForm(instance=settings_obj)

    cameras = Camera.objects.all().order_by("id")
    camera_form = CameraForm()

    return render(
        request,
        "face_recognition_app/settings.html",
        {
            "form": form,
            "cameras": cameras,
            "camera_form": camera_form,
        },
    )


@login_required
def camera_add(request):
    if request.method == "POST":
        form = CameraForm(request.POST)
        if form.is_valid():
            form.save()
            messages.success(request, "Camera added.")
        else:
            messages.error(request, f"Could not add camera: {form.errors.as_text()}")
    return redirect("recognition_settings")


@login_required
def camera_edit(request, camera_id):
    camera = get_object_or_404(Camera, id=camera_id)
    if request.method == "POST":
        form = CameraForm(request.POST, instance=camera)
        if form.is_valid():
            form.save()
            messages.success(request, "Camera updated.")
        else:
            messages.error(request, f"Could not update camera: {form.errors.as_text()}")
    return redirect("recognition_settings")


@login_required
def camera_delete(request, camera_id):
    camera = get_object_or_404(Camera, id=camera_id)
    if request.method == "POST":
        camera.delete()
        messages.success(request, "Camera removed.")
    return redirect("recognition_settings")

