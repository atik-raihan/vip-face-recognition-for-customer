from django.contrib import admin
from .models import Sale, SaleItem


class SaleItemInline(admin.TabularInline):
    model = SaleItem
    extra = 0


@admin.register(Sale)
class SaleAdmin(admin.ModelAdmin):

    list_display = (
        "id",
        "customer",
        "total",
        "created_at",
    )

    list_filter = (
        "created_at",
    )

    search_fields = (
        "customer__name",
        "customer__phone",
    )

    inlines = [
        SaleItemInline,
    ]