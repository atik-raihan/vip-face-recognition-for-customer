"""
NEW FILE: face_recognition_app/management/commands/build_employee_faces.py

Builds face embeddings for all active employees, same idea as your existing
build_faces.py for customers, but writes to a separate output file so the
two pools never collide.

Run:
    python manage.py build_employee_faces

Output:
    face_recognition_app/embeddings/employee_embeddings.pkl
    { employee_id (str): embedding vector (numpy array) }
"""
from pathlib import Path
import pickle

import cv2
from django.conf import settings
from django.core.management.base import BaseCommand

from face_recognition_app.models_attendance import Employee

OUTPUT_PATH = (
    Path(settings.BASE_DIR) / "face_recognition_app" / "embeddings" / "employee_embeddings.pkl"
)


class Command(BaseCommand):
    help = "Build InsightFace embeddings for all active employees (Item 12)."

    def handle(self, *args, **options):
        from face_recognition_app.services.employee_recognition_service import (
            employee_recognition_service,
        )

        analyzer = employee_recognition_service.analyzer
        embeddings = {}
        skipped = []

        employees = Employee.objects.filter(is_active=True).exclude(photo="")
        for employee in employees:
            if not employee.photo or not Path(employee.photo.path).exists():
                skipped.append(employee.employee_id)
                continue

            img = cv2.imread(employee.photo.path)
            if img is None:
                skipped.append(employee.employee_id)
                continue

            faces = analyzer.get(img)
            if not faces:
                skipped.append(employee.employee_id)
                continue

            # If a photo somehow has multiple faces, take the largest one.
            face = max(
                faces,
                key=lambda f: (f.bbox[2] - f.bbox[0]) * (f.bbox[3] - f.bbox[1]),
            )
            embeddings[employee.employee_id] = face.normed_embedding

        OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
        with open(OUTPUT_PATH, "wb") as f:
            pickle.dump(embeddings, f)

        employee_recognition_service.reload_embeddings()

        self.stdout.write(
            self.style.SUCCESS(f"Built {len(embeddings)} employee embeddings -> {OUTPUT_PATH}")
        )
        if skipped:
            self.stdout.write(
                self.style.WARNING(
                    f"Skipped {len(skipped)} employees (no photo or no face detected): {', '.join(skipped)}"
                )
            )

