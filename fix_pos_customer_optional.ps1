# VIP Face Recognition - POS Customer Optional Fix
# Run this in PowerShell from your dashboard folder

$dashboard = Get-Location

# ============================================
# 1. SALES MODELS
# ============================================
$salesModels = @"
from django.db import models
from customers.models import Customer
from products.models import Product

class Sale(models.Model):
    customer = models.ForeignKey(
        Customer,
        on_delete=models.SET_NULL,
        null=True,
        blank=True
    )

    total = models.DecimalField(
        max_digits=10,
        decimal_places=2,
        default=0
    )

    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        if self.customer:
            return f"Sale #{self.id} - {self.customer.name}"
        return f"Sale #{self.id} - Walk-in"


class SaleItem(models.Model):
    sale = models.ForeignKey(
        Sale,
        on_delete=models.CASCADE,
        related_name="items"
    )

    product = models.ForeignKey(
        Product,
        on_delete=models.CASCADE
    )

    quantity = models.PositiveIntegerField(default=1)

    price = models.DecimalField(
        max_digits=10,
        decimal_places=2
    )

    subtotal = models.DecimalField(
        max_digits=10,
        decimal_places=2
    )

    def save(self, *args, **kwargs):
        self.price = self.product.price
        self.subtotal = self.price * self.quantity
        super().save(*args, **kwargs)
"@

# ============================================
# 2. SALES VIEWS
# ============================================
$salesViews = @"
from django.shortcuts import render, redirect, get_object_or_404
from django.http import JsonResponse
from customers.models import Customer
from products.models import Product
from .models import Sale, SaleItem
import json


def pos(request):
    if request.method == "POST":
        customer_id = request.POST.get("customer")
        customer = None
        if customer_id:
            try:
                customer = Customer.objects.get(id=customer_id)
            except Customer.DoesNotExist:
                customer = None

        items = json.loads(request.POST["items"])

        sale = Sale.objects.create(
            customer=customer,
            total=0
        )

        total = 0

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

        if customer:
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
        product = Product.objects.get(id=request.GET.get("id"))

    return JsonResponse({
        "success": True,
        "id": product.id,
        "name": product.name,
        "price": float(product.price),
        "stock": product.stock,
    })


def sales_history(request):
    sales = Sale.objects.select_related("customer").order_by("-created_at")
    return render(request, "sales/history.html", {"sales": sales})


def sale_detail(request, pk):
    sale = get_object_or_404(Sale, pk=pk)
    items = SaleItem.objects.filter(sale=sale)
    return render(request, "sales/detail.html", {"sale": sale, "items": items})
"@

# ============================================
# 3. POS TEMPLATE
# ============================================
$posTemplate = @"
{% extends "base.html" %}

{% block title %}Point of Sale{% endblock %}

{% block content %}
<div class="content-wrapper">
  <section class="content-header">
    <h1>Point of Sale</h1>
    <ol class="breadcrumb">
      <li><a href="{% url 'dashboard' %}">Home</a></li>
      <li class="active">POS</li>
    </ol>
  </section>

  <section class="content">
    <div class="row">
      <!-- Left: Product Selection -->
      <div class="col-md-7">
        <div class="box box-primary">
          <div class="box-header">
            <h3 class="box-title"><i class="fa fa-barcode"></i> Scan or Select Product</h3>
          </div>
          <div class="box-body">
            <div class="form-group">
              <input type="text" id="barcode-input" class="form-control" placeholder="Scan barcode or type product name..." autofocus>
            </div>
            <div id="product-suggestions" class="list-group" style="max-height:200px; overflow-y:auto;"></div>
          </div>
        </div>

        <div class="box">
          <div class="box-header">
            <h3 class="box-title"><i class="fa fa-list"></i> Product List</h3>
          </div>
          <div class="box-body table-responsive">
            <table class="table table-hover">
              <thead>
                <tr>
                  <th>Name</th>
                  <th>Price</th>
                  <th>Stock</th>
                  <th>Action</th>
                </tr>
              </thead>
              <tbody>
                {% for product in products %}
                <tr>
                  <td>{{ product.name }}</td>
                  <td>{{ product.price }}</td>
                  <td><span class="badge {% if product.stock == 0 %}bg-red{% elif product.stock <= 5 %}bg-yellow{% else %}bg-green{% endif %}">{{ product.stock }}</span></td>
                  <td>
                    <button type="button" class="btn btn-xs btn-primary add-to-cart" data-id="{{ product.id }}" data-name="{{ product.name }}" data-price="{{ product.price }}" data-stock="{{ product.stock }}">
                      <i class="fa fa-plus"></i> Add
                    </button>
                  </td>
                </tr>
                {% endfor %}
              </tbody>
            </table>
          </div>
        </div>
      </div>

      <!-- Right: Cart & Checkout -->
      <div class="col-md-5">
        <div class="box box-success">
          <div class="box-header">
            <h3 class="box-title"><i class="fa fa-shopping-cart"></i> Cart</h3>
          </div>
          <div class="box-body">
            <table class="table" id="cart-table">
              <thead>
                <tr>
                  <th>Product</th>
                  <th>Qty</th>
                  <th>Price</th>
                  <th>Total</th>
                  <th></th>
                </tr>
              </thead>
              <tbody id="cart-body">
                <tr id="empty-cart">
                  <td colspan="5" class="text-center text-muted">Cart is empty</td>
                </tr>
              </tbody>
              <tfoot>
                <tr>
                  <th colspan="3">Grand Total</th>
                  <th id="grand-total">0.00</th>
                  <th></th>
                </tr>
              </tfoot>
            </table>
          </div>
        </div>

        <div class="box box-info">
          <div class="box-header">
            <h3 class="box-title"><i class="fa fa-user"></i> Customer (Optional)</h3>
          </div>
          <div class="box-body">
            <form id="sale-form" method="post" action="{% url 'pos' %}">
              {% csrf_token %}
              <input type="hidden" name="items" id="items-input" value="[]">

              <div class="form-group">
                <label>Select Customer</label>
                <select name="customer" id="customer-select" class="form-control">
                  <option value="">-- Walk-in (No Customer) --</option>
                  {% for customer in customers %}
                  <option value="{{ customer.id }}">{{ customer.name }} ({{ customer.phone }}) {% if customer.is_vip %}<span class="label label-warning">VIP</span>{% endif %}</option>
                  {% endfor %}
                </select>
                <small class="text-muted">Leave empty for walk-in sales</small>
              </div>

              <button type="submit" class="btn btn-success btn-block btn-lg" id="checkout-btn" disabled>
                <i class="fa fa-check"></i> Complete Sale
              </button>
            </form>
          </div>
        </div>
      </div>
    </div>
  </section>
</div>

<script>
let cart = [];

function updateCart() {
    const tbody = document.getElementById('cart-body');
    const grandTotalEl = document.getElementById('grand-total');
    const checkoutBtn = document.getElementById('checkout-btn');
    const itemsInput = document.getElementById('items-input');

    if (cart.length === 0) {
        tbody.innerHTML = '<tr id="empty-cart"><td colspan="5" class="text-center text-muted">Cart is empty</td></tr>';
        grandTotalEl.textContent = '0.00';
        checkoutBtn.disabled = true;
        itemsInput.value = '[]';
        return;
    }

    let html = '';
    let grandTotal = 0;

    cart.forEach((item, index) => {
        const total = item.price * item.qty;
        grandTotal += total;
        html += `<tr>
            <td>${item.name}</td>
            <td><input type="number" class="form-control qty-input" data-index="${index}" value="${item.qty}" min="1" max="${item.stock}" style="width:60px;"></td>
            <td>${item.price.toFixed(2)}</td>
            <td>${total.toFixed(2)}</td>
            <td><button type="button" class="btn btn-xs btn-danger remove-item" data-index="${index}"><i class="fa fa-trash"></i></button></td>
        </tr>`;
    });

    tbody.innerHTML = html;
    grandTotalEl.textContent = grandTotal.toFixed(2);
    checkoutBtn.disabled = false;
    itemsInput.value = JSON.stringify(cart.map(item => ({id: item.id, qty: item.qty})));
}

document.addEventListener('click', function(e) {
    if (e.target.closest('.add-to-cart')) {
        const btn = e.target.closest('.add-to-cart');
        const id = btn.dataset.id;
        const name = btn.dataset.name;
        const price = parseFloat(btn.dataset.price);
        const stock = parseInt(btn.dataset.stock);

        const existing = cart.find(item => item.id === id);
        if (existing) {
            if (existing.qty < stock) {
                existing.qty++;
            } else {
                alert('Not enough stock!');
            }
        } else {
            cart.push({id, name, price, qty: 1, stock});
        }
        updateCart();
    }

    if (e.target.closest('.remove-item')) {
        const index = parseInt(e.target.closest('.remove-item').dataset.index);
        cart.splice(index, 1);
        updateCart();
    }
});

document.addEventListener('change', function(e) {
    if (e.target.classList.contains('qty-input')) {
        const index = parseInt(e.target.dataset.index);
        const newQty = parseInt(e.target.value);
        if (newQty > 0 && newQty <= cart[index].stock) {
            cart[index].qty = newQty;
        } else {
            alert('Invalid quantity or not enough stock!');
            e.target.value = cart[index].qty;
        }
        updateCart();
    }
});

document.getElementById('barcode-input').addEventListener('keypress', function(e) {
    if (e.key === 'Enter') {
        e.preventDefault();
        const barcode = this.value.trim();
        if (!barcode) return;

        fetch(`/pos/get-product/?barcode=${encodeURIComponent(barcode)}`)
            .then(r => r.json())
            .then(data => {
                if (data.success) {
                    const existing = cart.find(item => item.id == data.id);
                    if (existing) {
                        if (existing.qty < data.stock) {
                            existing.qty++;
                        } else {
                            alert('Not enough stock!');
                        }
                    } else {
                        cart.push({
                            id: String(data.id),
                            name: data.name,
                            price: data.price,
                            qty: 1,
                            stock: data.stock
                        });
                    }
                    updateCart();
                    this.value = '';
                } else {
                    alert('Product not found!');
                }
            });
    }
});
</script>
{% endblock %}
"@

# ============================================
# 4. HISTORY TEMPLATE
# ============================================
$historyTemplate = @"
{% extends "base.html" %}

{% block title %}Sales History{% endblock %}

{% block content %}
<div class="content-wrapper">
  <section class="content-header">
    <h1>Sales History</h1>
    <ol class="breadcrumb">
      <li><a href="{% url 'dashboard' %}">Home</a></li>
      <li class="active">Sales History</li>
    </ol>
  </section>

  <section class="content">
    <div class="box">
      <div class="box-header">
        <h3 class="box-title"><i class="fa fa-receipt"></i> All Sales</h3>
      </div>
      <div class="box-body table-responsive">
        <table class="table table-hover">
          <thead>
            <tr>
              <th>#</th>
              <th>Customer</th>
              <th>Total</th>
              <th>Items</th>
              <th>Date</th>
              <th>Action</th>
            </tr>
          </thead>
          <tbody>
            {% for sale in sales %}
            <tr>
              <td>{{ sale.id }}</td>
              <td>
                {% if sale.customer %}
                  <a href="{% url 'customer_visit_history' sale.customer.id %}">{{ sale.customer.name }}</a>
                  {% if sale.customer.is_vip %}<span class="label label-warning">VIP</span>{% endif %}
                {% else %}
                  <span class="text-muted"><i class="fa fa-user-slash"></i> Walk-in</span>
                {% endif %}
              </td>
              <td><strong>{{ sale.total }}</strong></td>
              <td>{{ sale.items.count }}</td>
              <td>{{ sale.created_at|date:"Y-m-d H:i" }}</td>
              <td><a href="{% url 'sale_detail' sale.id %}" class="btn btn-xs btn-primary"><i class="fa fa-eye"></i> View</a></td>
            </tr>
            {% empty %}
            <tr>
              <td colspan="6" class="text-center text-muted">No sales yet.</td>
            </tr>
            {% endfor %}
          </tbody>
        </table>
      </div>
    </div>
  </section>
</div>
{% endblock %}
"@

# ============================================
# WRITE ALL FILES
# ============================================

$salesModelsPath = Join-Path $dashboard "sales\models.py"
$salesViewsPath = Join-Path $dashboard "salesiews.py"
$posTemplatePath = Join-Path $dashboard "templates\sales\pos.html"
$historyTemplatePath = Join-Path $dashboard "templates\sales\history.html"

# Ensure directories exist
New-Item -ItemType Directory -Path (Split-Path $posTemplatePath) -Force | Out-Null
New-Item -ItemType Directory -Path (Split-Path $historyTemplatePath) -Force | Out-Null

# Write files
$salesModels | Set-Content -Path $salesModelsPath -Encoding UTF8
$salesViews | Set-Content -Path $salesViewsPath -Encoding UTF8
$posTemplate | Set-Content -Path $posTemplatePath -Encoding UTF8
$historyTemplate | Set-Content -Path $historyTemplatePath -Encoding UTF8

Write-Host "========================================" -ForegroundColor Green
Write-Host "FILES WRITTEN SUCCESSFULLY!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Modified files:" -ForegroundColor Cyan
Write-Host "  - sales\models.py" -ForegroundColor White
Write-Host "  - sales\views.py" -ForegroundColor White
Write-Host "  - templates\sales\pos.html" -ForegroundColor White
Write-Host "  - templates\sales\history.html" -ForegroundColor White
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. python manage.py makemigrations sales" -ForegroundColor White
Write-Host "  2. python manage.py migrate" -ForegroundColor White
Write-Host "  3. python manage.py runserver" -ForegroundColor White
Write-Host ""
Write-Host "Then go to /pos/ and sell without selecting a customer!" -ForegroundColor Green
