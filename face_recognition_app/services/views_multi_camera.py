import cv2

from django.http import StreamingHttpResponse
from django.shortcuts import get_object_or_404, render

from .models import Camera


def camera_wall(request):
    """
    Display every active camera.
    """

    cameras = Camera.objects.filter(
        is_active=True
    ).select_related(
        "branch"
    ).order_by(
        "name"
    )

    return render(
        request,
        "face_recognition_app/camera_wall.html",
        {
            "cameras": cameras,
        },
    )


def generate_frames(camera):

    source = camera.connection_string

    try:
        source = int(source)
    except ValueError:
        pass

    cap = cv2.VideoCapture(source)

    if not cap.isOpened():
        return

    while True:

        success, frame = cap.read()

        if not success:
            break

        _, buffer = cv2.imencode(
            ".jpg",
            frame,
        )

        yield (
            b"--frame\r\n"
            b"Content-Type: image/jpeg\r\n\r\n"
            + buffer.tobytes()
            + b"\r\n"
        )

    cap.release()


def camera_stream(request, camera_id):
    """
    Live stream for a selected camera.
    """

    camera = get_object_or_404(
        Camera,
        pk=camera_id,
        is_active=True,
    )

    return StreamingHttpResponse(
        generate_frames(camera),
        content_type="multipart/x-mixed-replace; boundary=frame",
    )