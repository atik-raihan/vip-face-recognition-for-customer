"""
face_recognition_app/models_branch.py

Foundation model for item 12's multi-branch scope. Deliberately standalone
right now - does NOT add a branch FK to Camera, Employee, or Customer yet,
since that would mean editing those existing (working) models blind.

Once you're ready to actually assign cameras/employees to branches, the
next step is a small additive migration adding a nullable `branch` FK to
those models - safe to do once, not done automatically here to avoid
touching confirmed-working code without a specific go-ahead.
"""

from django.db import models


class Branch(models.Model):
    name = models.CharField(max_length=100, unique=True)
    code = models.CharField(
        max_length=20, unique=True, blank=True,
        help_text="Short code for this branch, e.g. DHK-01, CTG-02"
    )
    address = models.TextField(blank=True)
    phone = models.CharField(max_length=20, blank=True)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["name"]
        verbose_name_plural = "Branches"

    def __str__(self):
        return f"{self.name} ({self.code})" if self.code else self.name

