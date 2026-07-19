from django.shortcuts import render
from django.db.models import Sum, Count
from sales.models import Sale, SaleItem
from customers.models import Customer
from products.models import Product


def reports_dashboard(request):

    total_sales = Sale.objects.count()

    total_revenue = Sale.objects.aggregate(
        total=Sum("total")
    )["total"] or 0

    total_customers = Customer.objects.count()

    vip_customers = Customer.objects.filter(
        is_vip=True
    ).count()

    total_products = Product.objects.count()

    low_stock = Product.objects.filter(
        stock__lte=5,
        stock__gt=0
    ).count()

    best_products = (
        SaleItem.objects.values("product__name")
        .annotate(quantity=Sum("quantity"))
        .order_by("-quantity")[:10]
    )

    recent_sales = Sale.objects.select_related(
        "customer"
    ).order_by("-created_at")[:10]

    return render(
        request,
        "reports/dashboard.html",
        {
            "total_sales": total_sales,
            "total_revenue": total_revenue,
            "total_customers": total_customers,
            "vip_customers": vip_customers,
            "total_products": total_products,
            "low_stock": low_stock,
            "best_products": best_products,
            "recent_sales": recent_sales,
        },
    )