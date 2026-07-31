"""
stream_registry.py

Keeps track of every running camera worker.

This registry is the central place where the application
can discover active cameras, check their status, and
retrieve worker instances.
"""

from threading import Lock
from typing import Dict


class StreamRegistry:

    def __init__(self):

        self._workers: Dict[int, object] = {}
        self._lock = Lock()

    def register(self, camera_id: int, worker) -> None:
        """
        Register a running worker.
        """

        with self._lock:
            self._workers[camera_id] = worker

    def unregister(self, camera_id: int) -> None:
        """
        Remove a worker.
        """

        with self._lock:
            self._workers.pop(camera_id, None)

    def get(self, camera_id: int):
        """
        Return worker for a camera.
        """

        with self._lock:
            return self._workers.get(camera_id)

    def exists(self, camera_id: int) -> bool:
        """
        Check if a worker exists.
        """

        with self._lock:
            return camera_id in self._workers

    def all_workers(self):
        """
        Return every worker.
        """

        with self._lock:
            return dict(self._workers)

    def running_camera_ids(self):
        """
        Return list of running camera IDs.
        """

        with self._lock:
            return list(self._workers.keys())

    def count(self):
        """
        Number of running cameras.
        """

        with self._lock:
            return len(self._workers)

    def stop_all(self):
        """
        Stop every worker.
        """

        with self._lock:
            workers = list(self._workers.values())

        for worker in workers:

            try:
                worker.stop()
            except Exception:
                pass

        with self._lock:
            self._workers.clear()


stream_registry = StreamRegistry()