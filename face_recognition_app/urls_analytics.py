from django.urls import path
from .views_analytics import analytics_dashboard

urlpatterns = [
    path(
        "",
        analytics_dashboard,
        name="analytics_dashboard",
    ),
]