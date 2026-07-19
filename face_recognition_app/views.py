from django.shortcuts import render
from django.http import StreamingHttpResponse, Http404
from django.views.decorators.gzip import gzip_page

from .camera.live_ai_camera import gen_frames


def camera(request):
    """
    Renders the camera page. Same view name/URL as before — camera.html
    still points at {% url 'video_feed' %}, unchanged.
    """
    return render(request, "face_recognition_app/camera.html")


@gzip_page
def video_feed(request):
    """
    MJPEG streaming endpoint — now runs the full AI recognition pipeline
    (detect -> embed -> compare -> confidence -> VIP badge -> log) instead
    of a plain, unprocessed webcam feed.

    Default camera source is device index 0 (your original behavior).
    Once the Settings page (multi-camera support) is wired up, this can
    accept a camera_id and pull source_type/connection_string from the
    Camera model instead.
    """
    try:
        stream = gen_frames(camera_source=0, camera_obj=None)
    except RuntimeError as exc:
        raise Http404(str(exc))

    return StreamingHttpResponse(
        stream, content_type="multipart/x-mixed-replace; boundary=frame"
    )
