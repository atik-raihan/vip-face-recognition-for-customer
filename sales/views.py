from django.shortcuts import render, redirect, get_object_or_404
from django.http import JsonResponse
from customers.models import Customer
from products.models import Product
from .models import Sale, SaleItem
import json


def pos(request):

    if request.method == "POST":

        customer = Customer.objects.get(
            id=request.POST["customer"]
        )

        items = json.loads(request.POST["items"])

        sale = Sale.objects.create(
            customer=customer,
            total=0
        )

        total = 0

        for item in items:

            product = Product.objects.get(
                id=item["id"]
            )

            qty = int(item["qty"])

            subtotal = product.price * qty

            SaleItem.objects.create(
                sale=sale,
                product=product,
                quantity=qty,
                price=product.price,
                subtotal=subtotal
            )

            product.stock -= qty
            product.save()

            total += subtotal

        sale.total = total
        sale.save()

        customer.total_purchase += total
        customer.save()

        return redirect("sales_history")

    return render(
        request,
        "sales/pos.html",
        {
            "customers": Customer.objects.all(),
            "products": Product.objects.all(),
        },
    )


def get_product(request):

    barcode = request.GET.get("barcode")

    if barcode:

        try:
            product = Product.objects.get(barcode=barcode)

        except Product.DoesNotExist:

            return JsonResponse({"success": False})

    else:

        product = Product.objects.get(
            id=request.GET.get("id")
        )

    return JsonResponse({

        "success": True,
        "id": product.id,
        "name": product.name,
        "price": float(product.price),
        "stock": product.stock,

    })


def sales_history(request):

    sales = Sale.objects.select_related(
        "customer"
    ).order_by("-created_at")

    return render(
        request,
        "sales/history.html",
        {
            "sales": sales,
        },
    )


def sale_detail(request, pk):

    sale = get_object_or_404(
        Sale,
        pk=pk
    )

    items = SaleItem.objects.filter(
        sale=sale
    )

    return render(
        request,
        "sales/detail.html",
        {
            "sale": sale,
            "items": items,
        },
    )