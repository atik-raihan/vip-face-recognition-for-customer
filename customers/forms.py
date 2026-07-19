from django import forms
from .models import Customer


class CustomerForm(forms.ModelForm):

    class Meta:

        model = Customer

        fields = "__all__"

        widgets = {

            "name": forms.TextInput(attrs={
                "class": "form-control"
            }),

            "phone": forms.TextInput(attrs={
                "class": "form-control"
            }),

            "email": forms.EmailInput(attrs={
                "class": "form-control"
            }),

            "address": forms.Textarea(attrs={
                "class": "form-control",
                "rows": 3
            }),

            "image": forms.FileInput(attrs={
                "class": "form-control"
            }),

            "total_purchase": forms.NumberInput(attrs={
                "class": "form-control"
            }),

        }
