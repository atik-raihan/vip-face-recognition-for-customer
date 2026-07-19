"""
face_recognition_app/services/face_service.py

Reusable, production-grade FaceService (upgrades the previous stub, which
only exposed raw get_embedding()/recognize() with no persistence or
comparison logic).

Responsibilities:
- Load the InsightFace model exactly once (singleton pattern).
- Detect faces in a BGR (OpenCV) image and return embeddings.
- Load/save the customer embeddings database
  (face_recognition_app/embeddings/customer_embeddings.pkl — same path
  your existing build_faces command already writes to).
- Compare a live embedding against the stored database and return the
  best matching customer (or None if nothing clears the threshold).

Usage:
    from face_recognition_app.services.face_service import FaceService

    face_service = FaceService.get_instance()
    faces = face_service.detect_faces(frame)
    for face in faces:
        match = face_service.recognize(face["embedding"])
        if match:
            print(match["customer_name"], match["confidence"])
"""

import os
import pickle
import threading
from typing import Optional, List, Dict, Any

import numpy as np
import cv2

from django.conf import settings

from insightface.app import FaceAnalysis


# ---------------------------------------------------------------------------
# Paths / configurable defaults
# ---------------------------------------------------------------------------

# Matches the folder your existing build_faces command already creates:
# BASE_DIR / face_recognition_app / embeddings / customer_embeddings.pkl
DEFAULT_EMBEDDINGS_PATH = os.path.join(
    getattr(settings, "BASE_DIR", "."),
    "face_recognition_app",
    "embeddings",
    "customer_embeddings.pkl",
)

# Falls back to 0.65 if not defined in Django settings / SettingsApp config.
DEFAULT_RECOGNITION_THRESHOLD = getattr(settings, "RECOGNITION_THRESHOLD", 0.65)

INSIGHTFACE_MODEL_NAME = getattr(settings, "INSIGHTFACE_MODEL_NAME", "buffalo_l")

# ctx_id = 0 uses the first GPU if available via onnxruntime-gpu.
# ctx_id = -1 forces CPU. Default to CPU for maximum compatibility.
INSIGHTFACE_CTX_ID = getattr(settings, "INSIGHTFACE_CTX_ID", -1)
INSIGHTFACE_DET_SIZE = getattr(settings, "INSIGHTFACE_DET_SIZE", (640, 640))


class FaceService:
    """
    Singleton wrapper around InsightFace.

    The InsightFace model is expensive to load (disk + memory + init time),
    so it must be loaded exactly once per process and reused across:
      - the build_faces management command
      - the live camera recognition stream
      - any future recognition endpoints (attendance, employee recognition, etc.)
    """

    _instance: Optional["FaceService"] = None
    _lock = threading.Lock()

    def __init__(self, embeddings_path: str = DEFAULT_EMBEDDINGS_PATH):
        self.embeddings_path = embeddings_path
        self.threshold = DEFAULT_RECOGNITION_THRESHOLD

        self._app = FaceAnalysis(
            name=INSIGHTFACE_MODEL_NAME,
            providers=["CPUExecutionProvider"]
            if INSIGHTFACE_CTX_ID < 0
            else ["CUDAExecutionProvider", "CPUExecutionProvider"],
        )
        self._app.prepare(ctx_id=INSIGHTFACE_CTX_ID, det_size=INSIGHTFACE_DET_SIZE)

        # In-memory embeddings database. Loaded lazily / reloaded on demand
        # so that re-running build_faces doesn't require a server restart.
        self._database: List[Dict[str, Any]] = []
        self.reload_database()

    # ------------------------------------------------------------------
    # Singleton accessor
    # ------------------------------------------------------------------
    @classmethod
    def get_instance(cls) -> "FaceService":
        if cls._instance is None:
            with cls._lock:
                if cls._instance is None:
                    cls._instance = cls()
        return cls._instance

    # ------------------------------------------------------------------
    # Database management
    # ------------------------------------------------------------------
    def reload_database(self) -> None:
        """Reload customer_embeddings.pkl from disk into memory."""
        if not os.path.exists(self.embeddings_path):
            self._database = []
            return

        with open(self.embeddings_path, "rb") as f:
            self._database = pickle.load(f)

    def save_database(self, records: List[Dict[str, Any]]) -> None:
        """
        Persist the given records to customer_embeddings.pkl and refresh
        the in-memory copy used for live recognition.

        Each record has the shape:
            {
                "customer_id": int,
                "customer_name": str,
                "phone": str,
                "vip": bool,
                "embedding": np.ndarray (512,),
            }
        """
        os.makedirs(os.path.dirname(self.embeddings_path) or ".", exist_ok=True)
        with open(self.embeddings_path, "wb") as f:
            pickle.dump(records, f)
        self._database = records

    @property
    def database_size(self) -> int:
        return len(self._database)

    # ------------------------------------------------------------------
    # Detection / embedding generation
    # ------------------------------------------------------------------
    def detect_faces(self, bgr_image: np.ndarray) -> List[Dict[str, Any]]:
        """
        Detect all faces in a BGR (OpenCV-style) image.

        Returns a list of dicts:
            {
                "bbox": (x1, y1, x2, y2),
                "embedding": np.ndarray (512,) normalized,
                "det_score": float,
            }
        """
        if bgr_image is None:
            return []

        faces = self._app.get(bgr_image)
        results = []
        for face in faces:
            bbox = face.bbox.astype(int)
            embedding = face.normed_embedding  # already L2-normalized
            results.append(
                {
                    "bbox": (int(bbox[0]), int(bbox[1]), int(bbox[2]), int(bbox[3])),
                    "embedding": embedding,
                    "det_score": float(face.det_score),
                }
            )
        return results

    def get_embedding_from_path(self, image_path: str) -> Optional[np.ndarray]:
        """
        Load an image file from disk and return the embedding of the
        largest/most confident detected face. Used by build_faces.
        """
        if not image_path or not os.path.exists(image_path):
            return None

        image = cv2.imread(image_path)
        if image is None:
            return None

        faces = self.detect_faces(image)
        if not faces:
            return None

        best_face = max(faces, key=lambda f: f["det_score"])
        return best_face["embedding"]

    # ------------------------------------------------------------------
    # Recognition / comparison
    # ------------------------------------------------------------------
    @staticmethod
    def cosine_similarity(a: np.ndarray, b: np.ndarray) -> float:
        a_norm = a / (np.linalg.norm(a) + 1e-10)
        b_norm = b / (np.linalg.norm(b) + 1e-10)
        return float(np.dot(a_norm, b_norm))

    def recognize(self, embedding: np.ndarray) -> Optional[Dict[str, Any]]:
        """
        Compare a live embedding against every record in the database and
        return the best match if it clears self.threshold, else None.
        """
        if not self._database:
            return None

        best_record = None
        best_score = -1.0

        for record in self._database:
            score = self.cosine_similarity(embedding, record["embedding"])
            if score > best_score:
                best_score = score
                best_record = record

        if best_record is None or best_score < self.threshold:
            return None

        return {
            "customer_id": best_record["customer_id"],
            "customer_name": best_record["customer_name"],
            "phone": best_record.get("phone"),
            "vip": best_record.get("vip", False),
            "confidence": round(best_score, 4),
        }

    def set_threshold(self, threshold: float) -> None:
        """Allow the Settings page to update the recognition threshold at runtime."""
        self.threshold = float(threshold)
