"""
NEW FILE -- does not touch any existing forms.py.
NOTE: CameraForm uses fields = "__all__" against your existing Camera model
(webcam/usb/rtsp/dvr source types, per your build notes). If your Camera
model has fields beyond name/source_type/connection_string (e.g. is_active,
branch), they'll just show up as extra form fields automatically -- nothing
to change here.
"""
from django import forms
from .models import Camera
from .models_settings import SystemSettings
class SystemSettingsForm(forms.ModelForm):
    class Meta:
        model = SystemSettings
        fields = ["recognition_threshold", "vip_min_purchase", "default_camera_source", "ai_vip_messages_enabled"]
        widgets = {
            "recognition_threshold": forms.NumberInput(
                attrs={"step": "0.01", "min": "0", "max": "1", "class": "form-control"}
            ),
            "vip_min_purchase": forms.NumberInput(
                attrs={"step": "0.01", "min": "0", "class": "form-control"}
            ),
            "default_camera_source": forms.TextInput(attrs={"class": "form-control"}),
            "ai_vip_messages_enabled": forms.CheckboxInput(attrs={"class": "form-check-input"}),
        }
class CameraForm(forms.ModelForm):
    class Meta:
        model = Camera
        fields = "__all__"
        widgets = {
            "name": forms.TextInput(attrs={"class": "form-control"}),
            "source_type": forms.Select(attrs={"class": "form-control"}),
            "connection_string": forms.TextInput(
                attrs={"class": "form-control", "placeholder": "0, rtsp://..., or DVR channel"}
            ),
            "is_active": forms.CheckboxInput(attrs={"class": "form-check-input"}),
            "branch": forms.Select(attrs={"class": "form-control"}),
        }

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.fields["branch"].required = False
