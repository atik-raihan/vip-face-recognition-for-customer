from django.db import models


class Product(models.Model):

    CATEGORY_CHOICES = [
        ("Beverage", "Beverage"),
        ("Food", "Food"),
        ("Snack", "Snack"),
        ("Electronics", "Electronics"),
        ("Other", "Other"),
    ]

    name = models.CharField(max_length=150)

    barcode = models.CharField(
        max_length=100,
        unique=True
    )

    category = models.CharField(
        max_length=100,
        choices=CATEGORY_CHOICES,
        default="Other"
    )

    price = models.DecimalField(
        max_digits=10,
        decimal_places=2
    )

    stock = models.PositiveIntegerField(default=0)

    image = models.ImageField(
        upload_to="products/",
        blank=True,
        null=True
    )

    created_at = models.DateTimeField(
        auto_now_add=True
    )

    @property
    def stock_status(self):

        if self.stock == 0:
            return "Out of Stock"

        elif self.stock < 10:
            return "Low Stock"

        return "Available"

    def __str__(self):
        return self.name