from django.shortcuts import render, redirect
from django.db.models import Q
from .models import Customer
from .forms import CustomerForm


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