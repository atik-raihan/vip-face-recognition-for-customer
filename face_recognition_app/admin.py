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

from .models_settings import SystemSettings

@admin.register(SystemSettings)
class SystemSettingsAdmin(admin.ModelAdmin):
    list_display = ("recognition_threshold", "vip_min_purchase", "default_camera_source", "updated_at")

    def has_add_permission(self, request):
        return not SystemSettings.objects.exists()

    def has_delete_permission(self, request, obj=None):
        return False

from .models_attendance import Employee, EmployeeAttendanceLog

@admin.register(Employee)
class EmployeeAdmin(admin.ModelAdmin):
    list_display = ("employee_id", "name", "department", "is_active", "created_at")
    list_filter = ("is_active", "department")
    search_fields = ("employee_id", "name")


@admin.register(EmployeeAttendanceLog)
class EmployeeAttendanceLogAdmin(admin.ModelAdmin):
    list_display = ("employee", "event_type", "confidence", "camera_name", "timestamp")
    list_filter = ("event_type", "camera_name")
    date_hierarchy = "timestamp"
