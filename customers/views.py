import base64
from django.core.files.base import ContentFile
from django.shortcuts import render, redirect
from .models import Customer
from .forms import CustomerForm

from django.shortcuts import render, get_object_or_404
from django.db.models import Count
from sales.models import Sale
from face_recognition_app.models import RecognitionLog



def customer_list(request):
    customers = Customer.objects.all().order_by("-id")

    q = request.GET.get("q")

    if q:
        customers = customers.filter(
            Q(name__icontains=q) |
            Q(phone__icontains=q)
        )

    return render(
        request,
        "customers/customer_list.html",
        {
            "customers": customers,
        },
    )


def add_customer(request):

    if request.method == "POST":
        form = CustomerForm(
            request.POST,
            request.FILES
        )

        if form.is_valid():
            form.save()
            return redirect("customer_list")

    else:
        form = CustomerForm()

    return render(
        request,
        "customers/add_customer.html",
        {
            "form": form,
        },
    )


def edit_customer(request, pk):

    customer = Customer.objects.get(id=pk)

    if request.method == "POST":
        form = CustomerForm(
            request.POST,
            request.FILES,
            instance=customer
        )

        if form.is_valid():
            form.save()
            return redirect("customer_list")

    else:
        form = CustomerForm(instance=customer)

    return render(
        request,
        "customers/edit_customer.html",
        {
            "form": form,
        },
    )

def delete_customer(request, pk):

    customer = Customer.objects.get(id=pk)

    if request.method == "POST":
        customer.delete()
        return redirect("customer_list")

    return render(
        request,
        "customers/delete_customer.html",
        {
            "customer": customer,
        },
    )

def add_customer(request):
    if request.method == "POST":
        form = CustomerForm(request.POST, request.FILES)

        # Handle base64 camera image
        camera_image = request.POST.get("camera_image")
        if camera_image:
            # Remove data:image/jpeg;base64, prefix
            format, imgstr = camera_image.split(';base64,')
            ext = format.split('/')[-1]
            data = ContentFile(base64.b64decode(imgstr), name=f'camera_capture.{ext}')
            request.FILES['image'] = data

        if form.is_valid():
            customer = form.save()
            return redirect("customer_list")
    else:
        form = CustomerForm()

    return render(request, "customers/add_customer.html", {"form": form})

def customer_history(request, pk):
    customer = get_object_or_404(Customer, pk=pk)
    sales = Sale.objects.filter(customer=customer).order_by("-created_at")
    visits = RecognitionLog.objects.filter(customer=customer).order_by("-recognized_at")
    total_visits = visits.count()
    
    return render(request, "customers/customer_history.html", {
        "customer": customer,
        "sales": sales,
        "visits": visits,
        "total_visits": total_visits,
    })