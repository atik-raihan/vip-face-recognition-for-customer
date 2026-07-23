"""
NEW FILE.

Employee face recognition -- uses the same InsightFace approach as
services/face_service.py, but against a SEPARATE embeddings pool
(employee_embeddings.pkl) so attendance logic never mixes with customer
VIP recognition. Different thresholds, different dedupe rules, different
failure modes -- keeping them apart means a bug in one can't touch the
other.

OPTIMIZATION TODO (not a correctness issue): this tries to reuse the
InsightFace analyzer already loaded by face_service.py's singleton (to
avoid loading the buffalo_l model into memory twice). It does this via
rom .face_service import face_service + ace_service.app as a guess
at the attribute name -- if that guess is wrong it silently falls back to
loading its own separate analyzer instance, which still works correctly,
just uses more RAM and a slower first request. Paste face_service.py's
class definition if you want this tightened up to guarantee sharing.
"""
import pickle
from pathlib import Path

import numpy as np
from django.conf import settings
from django.utils import timezone

from .models_attendance import Employee, EmployeeAttendanceLog
from .models_settings import SystemSettings

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
        # Try to reuse the shared FaceService analyzer first.
        try:
            from .services.face_service import face_service  # adjust name/path if this doesn't match your file
            if hasattr(face_service, "app") and face_service.app is not None:
                self.analyzer = face_service.app
                return
        except Exception:
            pass

        # Fallback: load a separate InsightFace instance (works, costs more RAM).
        from insightface.app import FaceAnalysis

        model_root = getattr(settings, "INSIGHTFACE_MODEL_ROOT", None)
        model_name = getattr(settings, "INSIGHTFACE_MODEL_NAME", "buffalo_l")
        self.analyzer = FaceAnalysis(name=model_name, root=model_root)
        self.analyzer.prepare(ctx_id=-1)  # CPU

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


employee_recognition_service = EmployeeRecognitionService()

