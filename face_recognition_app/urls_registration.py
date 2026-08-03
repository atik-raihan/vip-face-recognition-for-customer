from django.urls import path

from .views_registration import (
    registration_page,
    registration_status,
    registration_capture,
    registration_save,
)

urlpatterns = [

    path(
        "registration/",
        registration_page,
        name="registration_page",
    ),

    path(
        "registration/status/",
        registration_status,
        name="registration_status",
    ),

    path(
        "registration/capture/",
        registration_capture,
        name="registration_capture",
    ),

    path(
        "registration/save/",
        registration_save,
        name="registration_save",
    ),

]