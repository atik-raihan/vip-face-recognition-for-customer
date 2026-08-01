from django.apps import AppConfig


class FaceRecognitionAppConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "face_recognition_app"

    def ready(self):
        try:
            from .services.multi_camera_service import multi_camera_service

            multi_camera_service.start()

            print("=" * 60)
            print(" Multi Camera Service Started")
            print("=" * 60)

        except Exception as e:
            print("=" * 60)
            print(" Multi Camera Service Failed")
            print(e)
            print("=" * 60)