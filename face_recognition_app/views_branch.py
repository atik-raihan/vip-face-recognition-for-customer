from django.shortcuts import render, redirect, get_object_or_404
from django.contrib import messages

from .models_branch import Branch
from .forms_branch import BranchForm


def branch_list(request):
    branches = Branch.objects.all().order_by("name")
    return render(request, "face_recognition_app/branch_list.html", {"branches": branches})


def branch_add(request):
    if request.method == "POST":
        form = BranchForm(request.POST)
        if form.is_valid():
            form.save()
            messages.success(request, "Branch added successfully.")
            return redirect("branch_list")
    else:
        form = BranchForm()
    return render(
        request, "face_recognition_app/branch_form.html", {"form": form, "title": "Add Branch"}
    )


def branch_edit(request, branch_id):
    branch = get_object_or_404(Branch, id=branch_id)
    if request.method == "POST":
        form = BranchForm(request.POST, instance=branch)
        if form.is_valid():
            form.save()
            messages.success(request, "Branch updated successfully.")
            return redirect("branch_list")
    else:
        form = BranchForm(instance=branch)
    return render(
        request,
        "face_recognition_app/branch_form.html",
        {"form": form, "title": "Edit Branch", "branch": branch},
    )


def branch_delete(request, branch_id):
    branch = get_object_or_404(Branch, id=branch_id)
    if request.method == "POST":
        branch.delete()
        messages.success(request, "Branch deleted.")
        return redirect("branch_list")
    return render(
        request, "face_recognition_app/branch_confirm_delete.html", {"branch": branch}
    )

