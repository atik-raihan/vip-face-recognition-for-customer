from django.shortcuts import render, redirect, get_object_or_404
from django.http import JsonResponse
from django.utils import timezone
from django.views.decorators.csrf import csrf_exempt
from django.core.files.base import ContentFile
from customers.models import Customer
from products.models import Product
from .models import Sale, SaleItem
import json
import base64


def pos(request):
    if request.method == "POST":
        # Check if this is a customer+sale combined request
        customer_id = request.POST.get("customer")
        items_json = request.POST.get("items", "[]")
        
        # If creating new customer from POS
        new_customer_data = request.POST.get("new_customer_data")
        if new_customer_data:
            customer_data = json.loads(new_customer_data)
            customer = Customer.objects.create(
                name=customer_data.get("name", "Walk-in"),
                phone=customer_data.get("phone", ""),
                email=customer_data.get("email", ""),
                address=customer_data.get("address", ""),
                is_vip=False,
                total_purchase=0
            )
            # Handle base64 image
            camera_image = request.POST.get("customer_photo")
            if camera_image:
                try:
                    format, imgstr = camera_image.split(';base64,')
                    ext = format.split('/')[-1]
                    data = ContentFile(base64.b64decode(imgstr), name=f'customer_{customer.id}.{ext}')
                    customer.image = data
                    customer.save()
                except Exception:
                    pass
        elif customer_id:
            try:
                customer = Customer.objects.get(id=customer_id)
            except Customer.DoesNotExist:
                customer = None
        else:
            customer = None

        items = json.loads(items_json)
        if not items:
            return redirect("pos")

        total = 0
        sale = Sale.objects.create(customer=customer, total=0)

        for item in items:
            product = Product.objects.get(id=item["id"])
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

        # If new customer, update their purchase total
        if new_customer_data and customer:
            customer.total_purchase = total
            if customer.total_purchase >= 1000:
                customer.is_vip = True
            customer.save()

        # If existing customer, update total
        if customer and not new_customer_data:
            customer.total_purchase += total
            if customer.total_purchase >= 1000:
                customer.is_vip = True
            customer.save()

        return redirect("print_invoice", pk=sale.id)

    return render(
        request,
        "sales/pos.html",
        {
            "customers": Customer.objects.all().order_by("name"),
            "products": Product.objects.all().order_by("name"),
        },
    )


@csrf_exempt
def create_customer_from_pos(request):
    """AJAX endpoint to create customer with captured photo"""
    if request.method == "POST":
        name = request.POST.get("name")
        phone = request.POST.get("phone", "")
        email = request.POST.get("email", "")
        address = request.POST.get("address", "")
        camera_image = request.POST.get("camera_image")

        if not name:
            return JsonResponse({"success": False, "message": "Name is required"})

        # If name is empty, auto-generate from phone
        if not name:
            name = "Customer " + phone[-4:]  # e.g., "Customer 1234"

        customer = Customer.objects.create(
            name=name,
            phone=phone,
            email=email,
            address=address,
            is_vip=False,
            total_purchase=0
        )
        if camera_image:
            try:
                format, imgstr = camera_image.split(';base64,')
                ext = format.split('/')[-1]
                data = ContentFile(base64.b64decode(imgstr), name=f'customer_{customer.id}.{ext}')
                customer.image = data
                customer.save()
            except Exception as e:
                pass

        return JsonResponse({
            "success": True,
            "customer_id": customer.id,
            "customer_name": customer.name,
            "message": f"Customer '{customer.name}' saved successfully!"
        })

    return JsonResponse({"success": False, "message": "Invalid request"})


def get_product(request):
    barcode = request.GET.get("barcode")
    if barcode:
        try:
            product = Product.objects.get(barcode=barcode)
        except Product.DoesNotExist:
            return JsonResponse({"success": False})
    else:
        try:
            product = Product.objects.get(id=request.GET.get("id"))
        except (Product.DoesNotExist, ValueError):
            return JsonResponse({"success": False})

    return JsonResponse({
        "success": True,
        "id": product.id,
        "name": product.name,
        "price": float(product.price),
        "stock": product.stock,
    })


def print_invoice(request, pk):
    sale = get_object_or_404(Sale, pk=pk)
    items = SaleItem.objects.filter(sale=sale).select_related("product")
    return render(request, "sales/print_invoice.html", {
        "sale": sale,
        "items": items,
        "now": timezone.now(),
    })


def sales_history(request):
    sales = Sale.objects.select_related("customer").order_by("-created_at")
    return render(request, "sales/history.html", {"sales": sales})


def sale_detail(request, pk):
    sale = get_object_or_404(Sale, pk=pk)
    items = SaleItem.objects.filter(sale=sale).select_related("product")
    return render(request, "sales/detail.html", {"sale": sale, "items": items})