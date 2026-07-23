"""
NEW FILE -- does not touch models.py directly (one import line gets appended
to it, same pattern used for models_settings.py).

Employee face recognition + attendance (Item 12, first slice).

NOTE: field is deliberately named photo here, NOT image -- this is not
a repeat of the earlier Customer.image gotcha, it's a distinct model. Keep
that straight if the two ever get merged or refactored together later.
"""
from django.db import models
from django.utils import timezone


class Employee(models.Model):
    employee_id = models.CharField(max_length=50, unique=True)
    name = models.CharField(max_length=150)
    department = models.CharField(max_length=100, blank=True)
    photo = models.ImageField(upload_to="employee_photos/")
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"{self.name} ({self.employee_id})"


class EmployeeAttendanceLog(models.Model):
    EVENT_CHOICES = [("IN", "Check In"), ("OUT", "Check Out")]

    employee = models.ForeignKey(
        Employee, on_delete=models.CASCADE, related_name="attendance_logs"
    )
    # String reference avoids a circular import with models.py, since
    # models.py is the one importing THIS file, not the other way around.
    camera = models.ForeignKey(
        "face_recognition_app.Camera", null=True, blank=True, on_delete=models.SET_NULL
    )
    camera_name = models.CharField(max_length=100, blank=True)
    event_type = models.CharField(max_length=3, choices=EVENT_CHOICES)
    confidence = models.FloatField()
    timestamp = models.DateTimeField(default=timezone.now)
    snapshot = models.ImageField(upload_to="attendance_snapshots/", blank=True, null=True)

    class Meta:
        ordering = ["-timestamp"]

    def __str__(self):
        return f"{self.employee} {self.event_type} @ {self.timestamp:%Y-%m-%d %H:%M}"

