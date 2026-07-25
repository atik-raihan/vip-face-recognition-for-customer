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

from . import views_employees

urlpatterns += [
    path("employees/", views_employees.employee_list, name="employee_list"),
    path("employees/add/", views_employees.employee_add, name="employee_add"),
    path("employees/<int:employee_id>/edit/", views_employees.employee_edit, name="employee_edit"),
    path("employees/<int:employee_id>/delete/", views_employees.employee_delete, name="employee_delete"),
]

from . import views_attendance_dashboard

urlpatterns += [
    path("attendance/dashboard/", views_attendance_dashboard.attendance_dashboard, name="attendance_dashboard"),
]

from . import views_branch

urlpatterns += [
    path("branches/", views_branch.branch_list, name="branch_list"),
    path("branches/add/", views_branch.branch_add, name="branch_add"),
    path("branches/<int:branch_id>/edit/", views_branch.branch_edit, name="branch_edit"),
    path("branches/<int:branch_id>/delete/", views_branch.branch_delete, name="branch_delete"),
]
