from django.db import models
from django.utils import timezone


class Employee(models.Model):
    employee_id = models.CharField(max_length=50, unique=True)
    name = models.CharField(max_length=150)
    department = models.CharField(max_length=100, blank=True)
    photo = models.ImageField(upload_to="employee_photos/")
    is_active = models.BooleanField(default=True)

    branch = models.ForeignKey(
        "face_recognition_app.Branch",
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="employees",
    )

    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"{self.name} ({self.employee_id})"


class EmployeeAttendanceLog(models.Model):
    CHECK_IN = "IN"
    CHECK_OUT = "OUT"

    EVENT_CHOICES = [
        (CHECK_IN, "Check In"),
        (CHECK_OUT, "Check Out"),
    ]

    employee = models.ForeignKey(
        Employee,
        on_delete=models.CASCADE,
        related_name="attendance_logs",
    )

    camera = models.ForeignKey(
        "face_recognition_app.Camera",
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
    )

    camera_name = models.CharField(max_length=100, blank=True)
    event_type = models.CharField(max_length=3, choices=EVENT_CHOICES)
    confidence = models.FloatField()
    timestamp = models.DateTimeField(default=timezone.now)
    snapshot = models.ImageField(
        upload_to="attendance_snapshots/",
        blank=True,
        null=True,
    )

    class Meta:
        ordering = ["-timestamp"]

    def __str__(self):
        return f"{self.employee} {self.event_type} @ {self.timestamp:%Y-%m-%d %H:%M}"