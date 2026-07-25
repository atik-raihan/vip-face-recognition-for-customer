from django.shortcuts import render, redirect, get_object_or_404
from django.contrib import messages

from .models_attendance import Employee
from .forms_employees import EmployeeForm


def employee_list(request):
    employees = Employee.objects.all().order_by("name")
    return render(request, "face_recognition_app/employee_list.html", {"employees": employees})


def employee_add(request):
    if request.method == "POST":
        form = EmployeeForm(request.POST, request.FILES)
        if form.is_valid():
            form.save()
            messages.success(request, "Employee added successfully.")
            return redirect("employee_list")
    else:
        form = EmployeeForm()
    return render(
        request,
        "face_recognition_app/employee_form.html",
        {"form": form, "title": "Add Employee"},
    )


def employee_edit(request, employee_id):
    employee = get_object_or_404(Employee, id=employee_id)
    if request.method == "POST":
        form = EmployeeForm(request.POST, request.FILES, instance=employee)
        if form.is_valid():
            form.save()
            messages.success(request, "Employee updated successfully.")
            return redirect("employee_list")
    else:
        form = EmployeeForm(instance=employee)
    return render(
        request,
        "face_recognition_app/employee_form.html",
        {"form": form, "title": "Edit Employee", "employee": employee},
    )


def employee_delete(request, employee_id):
    employee = get_object_or_404(Employee, id=employee_id)
    if request.method == "POST":
        employee.delete()
        messages.success(request, "Employee deleted.")
        return redirect("employee_list")
    return render(
        request, "face_recognition_app/employee_confirm_delete.html", {"employee": employee}
    )

