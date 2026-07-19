from django.db import models

class DashboardStats(models.Model):
    total_customers = models.IntegerField(default=0)
    vip_customers = models.IntegerField(default=0)
    total_revenue = models.DecimalField(
        max_digits=12,
        decimal_places=2,
        default=0
    )
    today_orders = models.IntegerField(default=0)

    def __str__(self):
        return "Dashboard Statistics"