"""
camera_manager.py

Manages all camera workers.

Responsibilities
----------------
- Load cameras from database
- Start all cameras
- Stop all cameras
- Restart individual cameras
- Return camera status
- Keep workers registered
"""

import logging
from threading import Lock

from .camera_worker import CameraWorker
from .stream_registry import stream_registry

logger = logging.getLogger(__name__)


class CameraManager:

    def __init__(self):

        self._lock = Lock()

    def load_cameras(self):
        """
        Load enabled cameras from database.
        """

        from face_recognition_app.models import Camera

        queryset = Camera.objects.all()

        if hasattr(Camera, "is_active"):
            queryset = queryset.filter(is_active=True)

        return list(queryset)

    def start_camera(self, camera, recognition_callback=None):
        """
        Start a single camera.
        """

        with self._lock:

            if stream_registry.exists(camera.id):

                logger.info(
                    "Camera %s already running.",
                    camera.name,
                )

                return stream_registry.get(camera.id)

            worker = CameraWorker(
                camera=camera,
                recognition_callback=recognition_callback,
            )

            worker.start()

            stream_registry.register(
                camera.id,
                worker,
            )

            logger.info(
                "Started camera %s",
                camera.name,
            )

            return worker

    def stop_camera(self, camera_id):
        """
        Stop one camera.
        """

        with self._lock:

            worker = stream_registry.get(camera_id)

            if worker is None:
                return

            worker.stop()

            worker.join(timeout=5)

            stream_registry.unregister(camera_id)

            logger.info(
                "Stopped camera %s",
                camera_id,
            )

    def restart_camera(self, camera_id):
        """
        Restart a camera.
        """

        from face_recognition_app.models import Camera

        self.stop_camera(camera_id)

        camera = Camera.objects.get(id=camera_id)

        self.start_camera(camera)

    def start_all(self, recognition_callback=None):
        """
        Start every enabled camera.
        """

        cameras = self.load_cameras()

        workers = []

        for camera in cameras:

            worker = self.start_camera(
                camera,
                recognition_callback,
            )

            workers.append(worker)

        logger.info(
            "%s camera(s) started.",
            len(workers),
        )

        return workers

    def stop_all(self):
        """
        Stop every running camera.
        """

        ids = stream_registry.running_camera_ids()

        for camera_id in ids:
            self.stop_camera(camera_id)

        logger.info("All cameras stopped.")

    def get_worker(self, camera_id):
        """
        Return worker.
        """

        return stream_registry.get(camera_id)

    def is_running(self, camera_id):
        """
        Check running status.
        """

        return stream_registry.exists(camera_id)

    def get_status(self):
        """
        Return status for every running camera.
        """

        status = []

        for worker in stream_registry.all_workers().values():

            status.append(worker.status())

        return status

    def running_count(self):
        """
        Number of active cameras.
        """

        return stream_registry.count()

    def running_camera_ids(self):
        """
        Return running camera IDs.
        """

        return stream_registry.running_camera_ids()


camera_manager = CameraManager()