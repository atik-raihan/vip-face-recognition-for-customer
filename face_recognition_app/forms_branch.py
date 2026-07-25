from django import forms

from .models_branch import Branch


class BranchForm(forms.ModelForm):

    class Meta:
        model = Branch
        fields = ["name", "code", "address", "phone", "is_active"]
        widgets = {
            "name": forms.TextInput(attrs={"class": "form-control"}),
            "code": forms.TextInput(attrs={"class": "form-control"}),
            "address": forms.Textarea(attrs={"class": "form-control", "rows": 3}),
            "phone": forms.TextInput(attrs={"class": "form-control"}),
            "is_active": forms.CheckboxInput(attrs={"class": "form-check-input"}),
        }

