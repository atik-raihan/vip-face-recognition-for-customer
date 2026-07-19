import uuid

from django.db import models
from django.utils import timezone

from customers.models import Customer


def recognition_snapshot_path(instance, filename):
    """
    Store snapshots under:
    media/recognition_snapshots/<year>/<month>/<day>/<uuid>.jpg
    """
    ext = filename.split(".")[-1] if "." in filename else "jpg"
    now = timezone.now()
    return (
        f"recognition_snapshots/{now.year}/{now.month:02d}/{now.day:02d}/"
        f"{uuid.uuid4().hex}.{ext}"
    )


class Camera(models.Model):
    """
    Represents a physical camera / stream source.
    Supports multiple cameras (Front Door, Cash Counter, VIP Entrance, etc.)
    """

    SOURCE_WEBCAM = "webcam"
    SOURCE_USB = "usb"
    SOURCE_RTSP = "rtsp"
    SOURCE_DVR = "dvr"

    SOURCE_CHOICES = [
        (SOURCE_WEBCAM, "Laptop Webcam"),
        (SOURCE_USB, "USB Camera"),
        (SOURCE_RTSP, "RTSP IP Camera"),
        (SOURCE_DVR, "DVR Stream"),
    ]

    name = models.CharField(max_length=100, unique=True)
    source_type = models.CharField(max_length=20, choices=SOURCE_CHOICES, default=SOURCE_WEBCAM)
    # For webcam/usb: device index as a string, e.g. "0"
    # For rtsp/dvr: full stream URL, e.g. "rtsp://user:pass@192.168.1.10/stream1"
    connection_string = models.CharField(max_length=255, default="0")
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["name"]

    def __str__(self):
        return f"{self.name} ({self.get_source_type_display()})"


class RecognitionLog(models.Model):
    """
    Every recognition event (matched or unknown) is stored here for the
    Recognition Dashboard, VIP visit history, and future analytics /
    attendance features.
    """

    customer = models.ForeignKey(
        Customer,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="recognition_logs",
        help_text="Null when the recognized face did not match any known customer.",
    )
    confidence = models.FloatField(help_text="Cosine similarity score at time of recognition (0.0 - 1.0)")
    camera = models.ForeignKey(
        Camera,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="recognition_logs",
    )
    camera_name = models.CharField(
        max_length=100,
        blank=True,
        help_text="Denormalized camera name, kept even if the Camera row is later deleted.",
    )
    recognized_at = models.DateTimeField(default=timezone.now, db_index=True)
    image_snapshot = models.ImageField(upload_to=recognition_snapshot_path, null=True, blank=True)
    was_vip_at_time = models.BooleanField(default=False)
    whatsapp_notified = models.BooleanField(default=False)

    class Meta:
        ordering = ["-recognized_at"]
        indexes = [
            models.Index(fields=["-recognized_at"]),
        ]

    def __str__(self):
        who = self.customer.name if self.customer else "Unknown"
        return f"{who} @ {self.recognized_at:%Y-%m-%d %H:%M:%S} ({self.confidence:.2f})"

    @property
    def is_known(self) -> bool:
        return self.customer_id is not None
