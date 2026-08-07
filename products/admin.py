from django.contrib import admin
from .models import Category, Product


@admin.register(Category)
class CategoryAdmin(admin.ModelAdmin):
    list_display = ["name", "product_count", "created_at"]
    search_fields = ["name"]
    ordering = ["name"]

    def product_count(self, obj):
        return obj.products.count()
    product_count.short_description = "Products"


@admin.register(Product)
class ProductAdmin(admin.ModelAdmin):
    list_display = ["name", "category", "price", "stock", "stock_status", "created_at"]
    list_filter = ["category"]  # REMOVED "stock_status" — it's a property, not a field
    search_fields = ["name", "barcode"]
    ordering = ["name"]