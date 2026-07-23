"""
UPDATED FILE (was created earlier this session) -- adds two fields for
Item 12 attendance. Since this is a file we generated ourselves and no
manual edits have been made to it, it's safe to overwrite wholesale rather
than patch in place.

Holds the app-wide configurable settings:
- recognition_threshold        -> customer/VIP face match threshold
- vip_min_purchase             -> minimum spend to flag a customer VIP
- default_camera_source        -> fallback source for video_feed
- employee_recognition_threshold -> separate threshold for employee/attendance matching [NEW]
- attendance_dedupe_seconds    -> cooldown between logging repeat recognitions of the same employee [NEW]

Singleton pattern: only ever one row, pk=1. Always fetch it with
SystemSettings.load() -- never SystemSettings.objects.all().
"""
from django.core.cache import cache
from django.db import models


class SystemSettings(models.Model):
    recognition_threshold = models.FloatField(
        default=0.65,
        help_text="Cosine similarity threshold for a customer face match (0.0-1.0). Lower = more lenient matching.",
    )
    vip_min_purchase = models.DecimalField(
        max_digits=12,
        decimal_places=2,
        default=0,
        help_text="Minimum total purchase amount for a customer to be flagged VIP.",
    )
    default_camera_source = models.CharField(
        max_length=200,
        default="0",
        help_text="Fallback camera source (index or RTSP/DVR URL) used when video_feed is called without a camera_id.",
    )
    employee_recognition_threshold = models.FloatField(
        default=0.60,
        help_text="Cosine similarity threshold for an employee/attendance face match (0.0-1.0).",
    )
    attendance_dedupe_seconds = models.IntegerField(
        default=300,
        help_text="Minimum seconds between two attendance log entries for the same employee (avoids spamming logs while someone stands in frame).",
    )
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = "System Settings"
        verbose_name_plural = "System Settings"

    def save(self, *args, **kwargs):
        self.pk = 1
        super().save(*args, **kwargs)
        cache.set("system_settings", self, timeout=None)

    def delete(self, *args, **kwargs):
        # Singleton row is never deleted.
        pass

    @classmethod
    def load(cls):
        cached = cache.get("system_settings")
        if cached is not None:
            return cached
        obj, _ = cls.objects.get_or_create(pk=1)
        cache.set("system_settings", obj, timeout=None)
        return obj

    def __str__(self):
        return "System Settings"

