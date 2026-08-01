import threading
import time

from face_recognition_app.models_camera import Camera
from face_recognition_app.camera.live_ai_camera import LiveAICamera


class CameraManager:

    def __init__(self):
        self.cameras = {}
        self.threads = {}
        self.running = False

    def start(self):
        if self.running:
            return

        self.running = True

        threading.Thread(
            target=self._monitor,
            daemon=True,
        ).start()

    def stop(self):
        self.running = False

        for camera in self.cameras.values():
            try:
                camera.stop()
            except Exception:
                pass

        self.cameras.clear()
        self.threads.clear()

    def _monitor(self):

        while self.running:

            active_ids = set(
                Camera.objects.filter(is_active=True)
                .values_list("id", flat=True)
            )

            # Start newly enabled cameras
            for camera in Camera.objects.filter(is_active=True):

                if camera.id in self.cameras:
                    continue

                ai_camera = LiveAICamera(camera)

                thread = threading.Thread(
                    target=ai_camera.start,
                    daemon=True,
                )

                thread.start()

                self.cameras[camera.id] = ai_camera
                self.threads[camera.id] = thread

                print(f"[CAMERA STARTED] {camera.name}")

            # Stop disabled cameras
            stopped = []

            for camera_id, ai_camera in self.cameras.items():

                if camera_id not in active_ids:

                    try:
                        ai_camera.stop()
                    except Exception:
                        pass

                    stopped.append(camera_id)

            for camera_id in stopped:

                self.cameras.pop(camera_id, None)
                self.threads.pop(camera_id, None)

                print(f"[CAMERA STOPPED] ID={camera_id}")

            time.sleep(5)


camera_manager = CameraManager()