"""
camera_worker.py

Runs one camera in its own thread.

Responsibilities
----------------
- Open camera
- Read frames
- Store latest frame
- Run face recognition
- Recover from camera disconnects
- Stop gracefully
"""

import logging
import threading
import time

import cv2

from .frame_buffer import frame_buffer

logger = logging.getLogger(__name__)


class CameraWorker(threading.Thread):
    """
    One worker = One camera
    """

    def __init__(
        self,
        camera,
        recognition_callback=None,
    ):
        super().__init__(daemon=True)

        self.camera = camera
        self.recognition_callback = recognition_callback

        self.capture = None

        self.running = False

        self.last_frame_time = None

        self.fps = 0

        self.frame_count = 0

        self.start_time = time.time()

    @property
    def camera_id(self):
        return self.camera.id

    @property
    def camera_name(self):
        return getattr(self.camera, "name", f"Camera {self.camera.id}")

    def _camera_source(self):
        """
        Returns the OpenCV source.
        """

        if getattr(self.camera, "rtsp_url", None):
            return self.camera.rtsp_url

        if getattr(self.camera, "device_index", None) is not None:
            return int(self.camera.device_index)

        return 0

    def open_camera(self):

        source = self._camera_source()

        logger.info(
            "Opening camera %s (%s)",
            self.camera_name,
            source,
        )

        self.capture = cv2.VideoCapture(source)

        if not self.capture.isOpened():

            logger.error(
                "Unable to open camera %s",
                self.camera_name,
            )

            return False

        return True

    def reconnect(self):

        logger.warning(
            "Reconnecting camera %s",
            self.camera_name,
        )

        try:

            if self.capture is not None:
                self.capture.release()

        except Exception:
            pass

        time.sleep(2)

        return self.open_camera()

    def process_frame(self, frame):
        """
        Save frame and send it to the recognition pipeline.
        """

        frame_buffer.set_frame(
            self.camera_id,
            frame,
        )

        if self.recognition_callback is not None:

            try:

                self.recognition_callback(
                    frame=frame,
                    camera=self.camera,
                )

            except Exception:

                logger.exception(
                    "Recognition failed for %s",
                    self.camera_name,
                )

    def calculate_fps(self):

        self.frame_count += 1

        elapsed = time.time() - self.start_time

        if elapsed >= 1:

            self.fps = self.frame_count / elapsed

            self.frame_count = 0

            self.start_time = time.time()

    def stop(self):

        self.running = False

    def release(self):

        try:

            if self.capture is not None:
                self.capture.release()

        except Exception:
            pass

        frame_buffer.remove_camera(
            self.camera_id
        )

    def run(self):

        self.running = True

        if not self.open_camera():
            return

        logger.info(
            "%s started.",
            self.camera_name,
        )

        while self.running:

            success, frame = self.capture.read()

            if not success:

                logger.warning(
                    "%s frame read failed.",
                    self.camera_name,
                )

                if not self.reconnect():
                    continue

                continue

            self.last_frame_time = time.time()

            self.calculate_fps()

            self.process_frame(frame)

        self.release()

        logger.info(
            "%s stopped.",
            self.camera_name,
        )

    def status(self):

        return {
            "camera_id": self.camera_id,
            "camera_name": self.camera_name,
            "running": self.running,
            "fps": round(self.fps, 2),
            "last_frame": self.last_frame_time,
        }