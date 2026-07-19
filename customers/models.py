from django.db import models


class Customer(models.Model):

    name = models.CharField(max_length=100)

    phone = models.CharField(
        max_length=20,
        unique=True
    )

    email = models.EmailField(
        blank=True,
        null=True
    )

    address = models.TextField(
        blank=True
    )

    image = models.ImageField(
        upload_to="customers/",
        blank=True,
        null=True
    )

    total_purchase = models.DecimalField(
        max_digits=12,
        decimal_places=2,
        default=0
    )

    is_vip = models.BooleanField(
        default=False
    )

    created_at = models.DateTimeField(
        auto_now_add=True
    )

    def save(self, *args, **kwargs):

        if self.total_purchase >= 1000:
            self.is_vip = True
        else:
            self.is_vip = False

        super().save(*args, **kwargs)

    def __str__(self):
        return self.name