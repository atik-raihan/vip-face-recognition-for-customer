"""
Employee face recognition -- uses the same InsightFace approach as
services/face_service.py, but against a SEPARATE embeddings pool
(employee_embeddings.pkl) so attendance logic never mixes with customer
VIP recognition.

Shares the InsightFace analyzer already loaded by FaceService's singleton
(via FaceService.get_instance()._app) instead of loading buffalo_l a
second time.
"""
import pickle
from pathlib import Path

import numpy as np
from django.conf import settings
from django.utils import timezone

from ..models_attendance import Employee, EmployeeAttendanceLog
from ..models_settings import SystemSettings

EMBEDDINGS_PATH = (
    Path(settings.BASE_DIR) / "face_recognition_app" / "embeddings" / "employee_embeddings.pkl"
)


class EmployeeRecognitionService:
    _instance = None

    def __new__(cls):
        if cls._instance is None:
            cls._instance = super().__new__(cls)
            cls._instance._init()
        return cls._instance

    def _init(self):
        self.analyzer = None
        self.embeddings = {}
        self._load_analyzer()
        self._load_embeddings()

    def _load_analyzer(self):
        # Reuse the shared FaceService singleton's already-loaded InsightFace
        # analyzer instead of loading buffalo_l a second time.
        from .face_service import FaceService

        face_service = FaceService.get_instance()
        self.analyzer = face_service._app

    def _load_embeddings(self):
        if EMBEDDINGS_PATH.exists():
            with open(EMBEDDINGS_PATH, "rb") as f:
                self.embeddings = pickle.load(f)
        else:
            self.embeddings = {}

    def reload_embeddings(self):
        """Call after re-running build_employee_faces so the running server picks up new photos without a restart."""
        self._load_embeddings()

    @staticmethod
    def _cosine_similarity(a, b):
        a, b = np.asarray(a), np.asarray(b)
        return float(np.dot(a, b) / (np.linalg.norm(a) * np.linalg.norm(b) + 1e-8))

    def recognize(self, face_embedding):
        """Returns (Employee, confidence) if matched above threshold, else (None, best_score)."""
        if not self.embeddings:
            return None, 0.0

        threshold = SystemSettings.load().employee_recognition_threshold
        best_id, best_score = None, -1.0
        for employee_id, emb in self.embeddings.items():
            score = self._cosine_similarity(face_embedding, emb)
            if score > best_score:
                best_id, best_score = employee_id, score

        if best_id is not None and best_score >= threshold:
            employee = Employee.objects.filter(employee_id=best_id, is_active=True).first()
            if employee:
                return employee, best_score
        return None, best_score

    def log_attendance(self, employee, confidence, camera=None, camera_name=""):
        """
        Creates an IN/OUT log entry, alternating based on the employee's last
        entry. Returns None (no-op) if a log for this employee already
        exists within the configured dedupe window, so standing in frame
        for a while doesn't spam the log.
        """
        dedupe_seconds = SystemSettings.load().attendance_dedupe_seconds
        cutoff = timezone.now() - timezone.timedelta(seconds=dedupe_seconds)

        recent_exists = EmployeeAttendanceLog.objects.filter(
            employee=employee, timestamp__gte=cutoff
        ).exists()
        if recent_exists:
            return None

        last_log = (
            EmployeeAttendanceLog.objects.filter(employee=employee).order_by("-timestamp").first()
        )
        event_type = "OUT" if last_log and last_log.event_type == "IN" else "IN"

        return EmployeeAttendanceLog.objects.create(
            employee=employee,
            camera=camera,
            camera_name=camera_name,
            event_type=event_type,
            confidence=confidence,
        )

    @classmethod
    def get_instance(cls):
        return cls()

