"""
frame_buffer.py

Thread-safe frame storage for multiple cameras.

Each camera stores only its latest frame. This allows the
dashboard and streaming views to retrieve the newest image
without blocking the camera workers.
"""

from threading import Lock
from typing import Dict, Optional

import cv2
import numpy as np


class FrameBuffer:
    """
    Stores the latest frame for every camera.

    Example:

        Camera 1 -> frame
        Camera 2 -> frame
        Camera 3 -> frame
    """

    def __init__(self):
        self._frames: Dict[int, np.ndarray] = {}
        self._timestamps: Dict[int, float] = {}
        self._lock = Lock()

    def set_frame(self, camera_id: int, frame: np.ndarray) -> None:
        """
        Save the latest frame for a camera.
        """

        if frame is None:
            return

        with self._lock:
            self._frames[camera_id] = frame.copy()
            self._timestamps[camera_id] = cv2.getTickCount()

    def get_frame(self, camera_id: int) -> Optional[np.ndarray]:
        """
        Return the latest frame for a camera.
        """

        with self._lock:

            frame = self._frames.get(camera_id)

            if frame is None:
                return None

            return frame.copy()

    def remove_camera(self, camera_id: int) -> None:
        """
        Remove stored frame for a camera.
        """

        with self._lock:

            self._frames.pop(camera_id, None)
            self._timestamps.pop(camera_id, None)

    def has_frame(self, camera_id: int) -> bool:
        """
        Check whether a frame exists.
        """

        with self._lock:
            return camera_id in self._frames

    def get_timestamp(self, camera_id: int):
        """
        Get last update timestamp.
        """

        with self._lock:
            return self._timestamps.get(camera_id)

    def camera_ids(self):
        """
        Return all active camera IDs.
        """

        with self._lock:
            return list(self._frames.keys())

    def clear(self):
        """
        Remove every stored frame.
        """

        with self._lock:
            self._frames.clear()
            self._timestamps.clear()

    def frame_count(self):
        """
        Number of active frame buffers.
        """

        with self._lock:
            return len(self._frames)


frame_buffer = FrameBuffer()