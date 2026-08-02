import cv2


class VideoProcessor:
    """
    Processes camera frames before they are streamed.
    """

    def process(self, frame, camera=None):
        """
        Process one frame.
        """

        if frame is None:
            return None

        # Camera Name
        if camera is not None:
            cv2.putText(
                frame,
                camera.name,
                (15, 30),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.8,
                (0, 255, 0),
                2,
            )

        # LIVE indicator
        cv2.circle(
            frame,
            (20, 55),
            6,
            (0, 0, 255),
            -1,
        )

        cv2.putText(
            frame,
            "LIVE",
            (35, 60),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.6,
            (255, 255, 255),
            2,
        )

        return frame


video_processor = VideoProcessor()