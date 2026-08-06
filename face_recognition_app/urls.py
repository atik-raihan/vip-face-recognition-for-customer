from django.urls import include, path

from . import views
from . import views_attendance_dashboard
from . import views_branch
from . import views_employees

from .views_attendance import attendance_log
from .views_multi_camera import (
    camera_stream,
    camera_wall,
)
from .views_settings import (
    camera_add,
    camera_delete,
    camera_edit,
    settings_page,
)

urlpatterns = [

    # ==========================================
    # Main Camera
    # ==========================================

    path(
        "",
        views.camera,
        name="camera",
    ),

    path(
        "video/",
        views.video_feed,
        name="video_feed",
    ),

    path(
        "dashboard/",
        views.recognition_dashboard,
        name="recognition_dashboard",
    ),

    path(
        "latest-recognition/",
        views.latest_recognition,
        name="latest_recognition",
    ),

    # ==========================================
    # Analytics
    # ==========================================
    

    path(
        "analytics/",
        include("face_recognition_app.urls_analytics"),
    ),

    # ==========================================
    # Multiple Camera
    # ==========================================

    path(
        "camera-wall/",
        camera_wall,
        name="camera_wall",
    ),

    path(
        "camera-stream/<int:camera_id>/",
        camera_stream,
        name="camera_stream",
    ),

    # ==========================================
    # Recognition Settings
    # ==========================================

    path(
        "settings/",
        settings_page,
        name="recognition_settings",
    ),

    path(
        "settings/camera/add/",
        camera_add,
        name="camera_add",
    ),

    path(
        "settings/camera/<int:camera_id>/edit/",
        camera_edit,
        name="camera_edit",
    ),

    path(
        "settings/camera/<int:camera_id>/delete/",
        camera_delete,
        name="camera_delete",
    ),

    # ==========================================
    # Attendance
    # ==========================================

    path(
        "attendance/",
        attendance_log,
        name="employee_attendance",
    ),

    path(
        "attendance/dashboard/",
        views_attendance_dashboard.attendance_dashboard,
        name="attendance_dashboard",
    ),

    # ==========================================
    # Employees
    # ==========================================

    path(
        "employees/",
        views_employees.employee_list,
        name="employee_list",
    ),

    path(
        "employees/add/",
        views_employees.employee_add,
        name="employee_add",
    ),

    path(
        "employees/<int:employee_id>/edit/",
        views_employees.employee_edit,
        name="employee_edit",
    ),

    path(
        "employees/<int:employee_id>/delete/",
        views_employees.employee_delete,
        name="employee_delete",
    ),

    # ==========================================
    # Customer Auto Registration
    # ==========================================

    path(
        "",
        include("face_recognition_app.urls_registration"),
    ),
    # ==========================================
    # Branches
    # ==========================================

    path(
        "branches/",
        views_branch.branch_list,
        name="branch_list",
    ),

    path(
        "branches/add/",
        views_branch.branch_add,
        name="branch_add",
    ),

    path(
        "branches/<int:branch_id>/edit/",
        views_branch.branch_edit,
        name="branch_edit",
    ),

    path(
        "branches/<int:branch_id>/delete/",
        views_branch.branch_delete,
        name="branch_delete",
    ),

    # Customer insights
    path("customer/<int:customer_id>/visit-history/", views.customer_visit_history_page, name="customer_visit_history"),
    path("api/customer/<int:customer_id>/visits/", views.customer_visit_history, name="api_customer_visits"),
    path("api/customer/<int:customer_id>/recommendations/", views.customer_purchase_recommendations, name="api_customer_recommendations"),
    path("api/pos/customer-search/", views.pos_customer_search, name="pos_customer_search"),

    # Unknown visitors
    path("unknown-visitors/", views.unknown_visitor_gallery, name="unknown_visitor_gallery"),
    # Analytics
    path("analytics/", views.analytics_dashboard, name="analytics_dashboard"),
    # Enhanced polling API
    path("latest-recognition-enhanced/", views.latest_recognition_enhanced, name="latest_recognition_enhanced"),
    path("api/pos/customer-search/", views.pos_customer_search, name="pos_customer_search"),]




