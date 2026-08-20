from decimal import Decimal
import json
from datetime import timedelta

from django.contrib.auth.decorators import login_required
from django.db import transaction
from django.db.models import Sum
from django.http import JsonResponse
from django.shortcuts import render, redirect, get_object_or_404
from django.utils import timezone
from django.views.decorators.csrf import csrf_exempt

from customers.models import Customer
from products.models import Product
from face_recognition_app.models import RecognitionLog
from .models import Sale, SaleItem


def pos(request):
    """POS page and complete-sale handler."""
    if request.method == "POST":
        customer_id = request.POST.get("customer", "").strip()
        items_json = request.POST.get("items", "[]")

        try:
            items = json.loads(items_json)
        except (TypeError, ValueError, json.JSONDecodeError):
            return JsonResponse(
                {"success": False, "message": "Invalid cart data."},
                status=400,
            )

        if not isinstance(items, list) or not items:
            return JsonResponse(
                {"success": False, "message": "Cart is empty."},
                status=400,
            )

        customer = None
        if customer_id:
            try:
                customer = Customer.objects.get(pk=int(customer_id))
            except (Customer.DoesNotExist, TypeError, ValueError):
                return JsonResponse(
                    {"success": False, "message": "Selected customer does not exist."},
                    status=400,
                )

        # Validate the entire cart before changing the database.
        validated_items = []
        total = Decimal("0.00")

        for item in items:
            try:
                product_id = int(item["id"])
                quantity = int(item["qty"])
            except (KeyError, TypeError, ValueError):
                return JsonResponse(
                    {"success": False, "message": "Invalid product or quantity."},
                    status=400,
                )

            if quantity <= 0:
                return JsonResponse(
                    {"success": False, "message": "Quantity must be at least 1."},
                    status=400,
                )

            product = Product.objects.filter(pk=product_id).first()
            if product is None:
                return JsonResponse(
                    {"success": False, "message": f"Product {product_id} was not found."},
                    status=400,
                )

            if product.stock < quantity:
                return JsonResponse(
                    {
                        "success": False,
                        "message": (
                            f"Not enough stock for {product.name}. "
                            f"Available: {product.stock}, requested: {quantity}."
                        ),
                    },
                    status=400,
                )

            price = Decimal(str(product.price))
            subtotal = price * quantity
            total += subtotal

            validated_items.append({
                "product_id": product.id,
                "quantity": quantity,
                "price": price,
                "subtotal": subtotal,
            })

        # All-or-nothing database operation.
        try:
            with transaction.atomic():
                sale = Sale.objects.create(
                    customer=customer,
                    total=Decimal("0.00"),
                )

                for row in validated_items:
                    product = Product.objects.select_for_update().get(
                        pk=row["product_id"]
                    )

                    if product.stock < row["quantity"]:
                        raise ValueError(
                            f"Not enough stock for {product.name}."
                        )

                    SaleItem.objects.create(
                        sale=sale,
                        product=product,
                        quantity=row["quantity"],
                        price=row["price"],
                        subtotal=row["subtotal"],
                    )

                    product.stock -= row["quantity"]
                    product.save(update_fields=["stock"])

                sale.total = total
                sale.save(update_fields=["total"])

                if customer is not None:
                    customer.total_purchase = (
                        Decimal(str(customer.total_purchase)) + total
                    )
                    # Customer.save() automatically applies:
                    # total_purchase >= 1000 -> is_vip=True
                    customer.save()

        except ValueError as exc:
            return JsonResponse(
                {"success": False, "message": str(exc)},
                status=400,
            )
        except Exception as exc:
            return JsonResponse(
                {"success": False, "message": f"Sale could not be completed: {exc}"},
                status=500,
            )

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
    """Create a POS customer. Customer image upload is not required."""
    if request.method != "POST":
        return JsonResponse(
            {"success": False, "message": "Invalid request"},
            status=405,
        )

    name = request.POST.get("name", "").strip()
    phone = request.POST.get("phone", "").strip()
    email = request.POST.get("email", "")
    address = request.POST.get("address", "")

    if not phone:
        return JsonResponse(
            {"success": False, "message": "Phone number is required"},
            status=400,
        )

    if not name:
        name = "Customer " + phone[-4:]

    if Customer.objects.filter(phone=phone).exists():
        return JsonResponse(
            {"success": False, "message": "A customer with this phone already exists."},
            status=400,
        )

    customer = Customer.objects.create(
        name=name,
        phone=phone,
        email=email,
        address=address,
        total_purchase=0,
    )

    return JsonResponse({
        "success": True,
        "customer_id": customer.id,
        "customer_name": customer.name,
        "message": f"Customer '{customer.name}' saved successfully!",
    })


def get_product(request):
    barcode = request.GET.get("barcode")
    product_id = request.GET.get("id")

    if barcode:
        product = Product.objects.filter(barcode=barcode).first()
    elif product_id:
        product = Product.objects.filter(pk=product_id).first()
    else:
        product = None

    if product is None:
        return JsonResponse(
            {"success": False, "message": "Product not found."},
            status=404,
        )

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

    return render(
        request,
        "sales/print_invoice.html",
        {
            "sale": sale,
            "items": items,
            "now": timezone.now(),
        },
    )


def sales_history(request):
    sales = Sale.objects.select_related("customer").order_by("-created_at")
    return render(request, "sales/history.html", {"sales": sales})


def sale_detail(request, pk):
    sale = get_object_or_404(Sale, pk=pk)
    items = SaleItem.objects.filter(sale=sale).select_related("product")

    return render(
        request,
        "sales/detail.html",
        {"sale": sale, "items": items},
    )


@login_required
def pos_vip_status(request):
    """
    Return recent VIP recognition data for the POS.

    Uses the actual RecognitionLog fields from this project:
    recognized_at and was_vip_at_time.
    """
    cutoff = timezone.now() - timedelta(minutes=10)

    recent_log = (
        RecognitionLog.objects.filter(
            recognized_at__gte=cutoff,
            customer__isnull=False,
            was_vip_at_time=True,
        )
        .select_related("customer")
        .order_by("-recognized_at")
        .first()
    )

    if not recent_log:
        return JsonResponse({"vip_detected": False})

    customer = recent_log.customer

    visit_count = RecognitionLog.objects.filter(
        customer=customer
    ).count()

    last_visit_log = (
        RecognitionLog.objects.filter(
            customer=customer,
            recognized_at__lt=recent_log.recognized_at,
        )
        .order_by("-recognized_at")
        .first()
    )

    last_visit = None

    if last_visit_log:
        diff = timezone.now() - last_visit_log.recognized_at

        if diff.days > 0:
            last_visit = f"{diff.days} days ago"
        elif diff.seconds // 3600 > 0:
            last_visit = f"{diff.seconds // 3600} hours ago"
        else:
            last_visit = f"{diff.seconds // 60} mins ago"

    frequent_items = []

    try:
        frequent_items_qs = (
            SaleItem.objects
            .filter(sale__customer=customer)
            .values("product__name")
            .annotate(total_qty=Sum("quantity"))
            .order_by("-total_qty")[:5]
        )

        frequent_items = [
            item["product__name"]
            for item in frequent_items_qs
            if item["product__name"]
        ]
    except Exception:
        pass

    return JsonResponse({
        "vip_detected": True,
        "customer": {
            "id": customer.id,
            "name": customer.name,
            "phone": customer.phone,
            "photo_url": "",
            "is_vip": customer.is_vip,
            "visit_count": visit_count,
            "last_visit": last_visit or "First visit",
            "frequent_items": frequent_items,
        },
    })
