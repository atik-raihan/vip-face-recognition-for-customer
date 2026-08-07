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

def category_list(request):
    """
    Show all product categories:
    - Valid categories from CATEGORY_CHOICES
    - Actual categories used in database with counts
    - Invalid categories (not in choices) highlighted
    """
    from django.db.models import Count

    # Get valid choices from model
    valid_choices = dict(Product.CATEGORY_CHOICES)
    valid_keys = set(valid_choices.keys())

    # Get actual categories from database with counts
    db_categories = (
        Product.objects.values('category')
        .annotate(count=Count('id'))
        .order_by('category')
    )

    categories_info = []
    invalid_categories = []

    for item in db_categories:
        cat = item['category']
        count = item['count']
        is_valid = cat in valid_keys

        info = {
            'name': cat,
            'display_name': valid_choices.get(cat, cat),
            'count': count,
            'is_valid': is_valid,
        }

        if is_valid:
            categories_info.append(info)
        else:
            invalid_categories.append(info)

    # Also show valid choices that have ZERO products
    used_keys = {item['category'] for item in db_categories}
    for key, display in valid_choices.items():
        if key not in used_keys:
            categories_info.append({
                'name': key,
                'display_name': display,
                'count': 0,
                'is_valid': True,
            })

    # Sort by display name
    categories_info.sort(key=lambda x: x['display_name'])

    total_products = Product.objects.count()

    return render(request, "products/category_list.html", {
        "categories": categories_info,
        "invalid_categories": invalid_categories,
        "valid_choices": list(valid_choices.items()),
        "total_products": total_products,
    })