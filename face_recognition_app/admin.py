from django.contrib import admin

from .models import Camera, RecognitionLog


@admin.register(Camera)
class CameraAdmin(admin.ModelAdmin):
    list_display = ("name", "source_type", "connection_string", "is_active", "created_at")
    list_filter = ("source_type", "is_active")
    search_fields = ("name", "connection_string")


@admin.register(RecognitionLog)
class RecognitionLogAdmin(admin.ModelAdmin):
    list_display = ("customer", "confidence", "camera_name", "was_vip_at_time", "whatsapp_notified", "recognized_at")
    list_filter = ("was_vip_at_time", "whatsapp_notified", "camera_name")
    search_fields = ("customer__name", "customer__phone", "camera_name")
    readonly_fields = ("recognized_at",)
    date_hierarchy = "recognized_at"
