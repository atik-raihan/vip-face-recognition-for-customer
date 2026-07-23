from django.urls import path
from . import views

urlpatterns = [
    path("", views.camera, name="camera"),
    path("video/", views.video_feed, name="video_feed"),
    path("latest-recognition/", views.latest_recognition, name="latest_recognition"),
    path("dashboard/", views.recognition_dashboard, name="recognition_dashboard"),
]
from .views_settings import settings_page, camera_add, camera_edit, camera_delete

urlpatterns += [
    path("settings/", settings_page, name="recognition_settings"),
    path("settings/camera/add/", camera_add, name="camera_add"),
    path("settings/camera/<int:camera_id>/edit/", camera_edit, name="camera_edit"),
    path("settings/camera/<int:camera_id>/delete/", camera_delete, name="camera_delete"),
]

from .views_attendance import attendance_log

urlpatterns += [
    path("attendance/", attendance_log, name="employee_attendance"),
]
