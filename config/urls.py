from django.contrib import admin
from django.urls import path, include
from django.conf import settings
from django.conf.urls.static import static

urlpatterns = [
    path("admin/", admin.site.urls),

    path("", include("dashboard_app.urls")),

    path("customers/", include("customers.urls")),

    path("products/", include("products.urls")),

    path("pos/", include("sales.urls")),

    path("reports/", include("reports.urls")),

    path("camera/", include("face_recognition_app.urls")),
]

if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)