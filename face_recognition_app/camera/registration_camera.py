import cv2
import threading

from face_recognition_app.services.face_service import FaceService


class RegistrationCamera:

    def __init__(self):

        self.cap = None

        self.lock = threading.Lock()

        self.last_frame = None

        self.last_capture = None

        self.face_service = FaceService.get_instance()

        self.start()

    def start(self):

        if self.cap is not None:
            return

        self.cap = cv2.VideoCapture(0)

    def get_frame(self):

        with self.lock:

            if self.cap is None:
                return None

            ok, frame = self.cap.read()

            if not ok:
                return None

            self.last_frame = frame

            return frame.copy()

    def check_face(self):

        frame = self.get_frame()

        if frame is None:

            return {
                "status": "waiting"
            }

        faces = self.face_service.detect_faces(frame)

        if len(faces) == 0:

            return {
                "status": "waiting"
            }

        if len(faces) > 1:

            return {
                "status": "multiple"
            }

        return {

            "status": "face_found"

        }

    def capture(self):

        frame = self.get_frame()

        if frame is None:
            return None

        self.last_capture = frame.copy()

        return self.last_capture

    def stop(self):

        if self.cap is not None:

            self.cap.release()

            self.cap = None


registration_camera = RegistrationCamera()

