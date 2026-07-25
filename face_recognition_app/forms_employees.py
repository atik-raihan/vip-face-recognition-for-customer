from django import forms

from .models_attendance import Employee


class EmployeeForm(forms.ModelForm):

    class Meta:
        model = Employee
        fields = ["employee_id", "name", "department", "photo", "is_active"]
        widgets = {
            "employee_id": forms.TextInput(attrs={"class": "form-control"}),
            "name": forms.TextInput(attrs={"class": "form-control"}),
            "department": forms.TextInput(attrs={"class": "form-control"}),
            "photo": forms.FileInput(attrs={"class": "form-control"}),
            "is_active": forms.CheckboxInput(attrs={"class": "form-check-input"}),
        }

