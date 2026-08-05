import base64
import os
import uuid

import cv2

from django.conf import settings
from django.http import JsonResponse

from face_recognition_app.camera.registration_camera import registration_camera
from face_recognition_app.services.face_service import FaceService

from customers.models import Customer
from django.shortcuts import render

def registration_page(request):
    return render(
        request,
        "customers/customer_register_ai.html",
    )


def registration_status(request):

    result = registration_camera.check_face()

    return JsonResponse(result)


def registration_capture(request):

    frame = registration_camera.capture()

    if frame is None:

        return JsonResponse({
            "success": False
        })

    _, buffer = cv2.imencode(".jpg", frame)

    registration_camera.last_capture = frame.copy()

    return JsonResponse({

        "success": True,

        "image":
            "data:image/jpeg;base64,"
            + base64.b64encode(buffer).decode()

    })


def registration_save(request):

    if request.method != "POST":

        return JsonResponse({

            "success": False,
            "message": "POST only"

        })

    frame = registration_camera.last_capture

    if frame is None:

        return JsonResponse({

            "success": False,
            "message": "Capture image first."

        })

    name = request.POST.get("name", "")
    phone = request.POST.get("phone", "")

    if name == "":

        return JsonResponse({

            "success": False,
            "message": "Name required"

        })

    customer = Customer(

        name=name,
        phone=phone,

    )

    customer.save()

    folder = os.path.join(

        settings.MEDIA_ROOT,
        "customers"

    )

    os.makedirs(folder, exist_ok=True)

    filename = f"{uuid.uuid4()}.jpg"

    filepath = os.path.join(folder, filename)

    cv2.imwrite(filepath, frame)

    customer.image = f"customers/{filename}"

    customer.save()

    face_service = FaceService.get_instance()

    embedding = face_service.get_embedding_from_path(filepath)

    if embedding is None:

        customer.delete()

        os.remove(filepath)

        return JsonResponse({

            "success": False,
            "message": "No face detected."

        })

    face_service.reload_database()

    database = list(face_service._database)

    database.append({

        "customer_id": customer.id,
        "customer_name": customer.name,
        "phone": customer.phone,
        "vip": customer.is_vip,
        "embedding": embedding,

    })

    face_service.save_database(database)

    return JsonResponse({

        "success": True,

        "customer_id": customer.id,

        "message": "Customer Registered Successfully"

    })
