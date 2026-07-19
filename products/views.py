from django.shortcuts import render, redirect, get_object_or_404
from django.db.models import Q, Sum
from .models import Product
from .forms import ProductForm


def product_list(request):

    products = Product.objects.all().order_by("name")

    q = request.GET.get("q")

    if q:
        products = products.filter(
            Q(name__icontains=q) |
            Q(barcode__icontains=q) |
            Q(category__icontains=q)
        )

    total_products = Product.objects.count()

    low_stock = Product.objects.filter(
        stock__gt=0,
        stock__lte=5
    ).count()

    out_of_stock = Product.objects.filter(
        stock=0
    ).count()

    inventory_value = 0

    for product in Product.objects.all():
        inventory_value += product.price * product.stock

    return render(
        request,
        "products/product_list.html",
        {
            "products": products,
            "total_products": total_products,
            "low_stock": low_stock,
            "out_of_stock": out_of_stock,
            "inventory_value": inventory_value,
        },
    )


def add_product(request):

    if request.method == "POST":

        form = ProductForm(
            request.POST,
            request.FILES
        )

        if form.is_valid():
            form.save()
            return redirect("product_list")

    else:
        form = ProductForm()

    return render(
        request,
        "products/add_product.html",
        {
            "form": form,
        },
    )


def edit_product(request, pk):

    product = get_object_or_404(Product, pk=pk)

    if request.method == "POST":

        form = ProductForm(
            request.POST,
            request.FILES,
            instance=product
        )

        if form.is_valid():
            form.save()
            return redirect("product_list")

    else:
        form = ProductForm(instance=product)

    return render(
        request,
        "products/edit_product.html",
        {
            "form": form,
        },
    )


def delete_product(request, pk):

    product = get_object_or_404(Product, pk=pk)

    product.delete()

    return redirect("product_list")