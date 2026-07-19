from django.contrib import admin
from .models import Customer


@admin.register(Customer)
class CustomerAdmin(admin.ModelAdmin):
    list_display = (
        "name",
        "phone",
        "total_purchase",
        "is_vip",
    )

    search_fields = (
        "name",
        "phone",
    )

    list_filter = (
        "is_vip",
    )