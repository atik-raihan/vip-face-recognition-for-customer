from django.urls import path
from . import views

urlpatterns = [
    path("", views.camera, name="camera"),
    path("video/", views.video_feed, name="video_feed"),
    path("latest-recognition/", views.latest_recognition, name="latest_recognition"),
]