from django.urls import path
from . import views

urlpatterns = [

    path("", views.pos, name="pos"),

    path(
        "product/",
        views.get_product,
        name="get_product"
    ),

    path(
        "history/",
        views.sales_history,
        name="sales_history"
    ),

    path(
        "history/<int:pk>/",
        views.sale_detail,
        name="sale_detail"
    ),

]