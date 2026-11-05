from django.core.validators import MinValueValidator
from django.db import models


class Country(models.Model):
    name = models.CharField(max_length=100, unique=True)
    code = models.CharField(max_length=3, unique=True)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["name"]
        verbose_name_plural = "countries"

    def save(self, *args, **kwargs):
        self.code = self.code.upper()
        super().save(*args, **kwargs)

    def __str__(self):
        return f"{self.name} ({self.code})"


class Product(models.Model):
    COFFEE = "cafe"
    CACAO = "cacao"
    PRODUCT_TYPES = [(COFFEE, "Cafe"), (CACAO, "Cacao")]

    KG = "kg"
    TON = "tonelada"
    UNITS = [(KG, "kg"), (TON, "tonelada")]

    name = models.CharField(max_length=120)
    product_type = models.CharField(max_length=20, choices=PRODUCT_TYPES)
    description = models.TextField(blank=True)
    organization = models.ForeignKey(
        "users.Organization",
        on_delete=models.PROTECT,
        related_name="catalog_products",
        null=True,
        blank=True,
    )
    quantity = models.DecimalField(
        max_digits=12,
        decimal_places=2,
        validators=[MinValueValidator(0)],
    )
    unit = models.CharField(max_length=20, choices=UNITS)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["name"]

    def __str__(self):
        return self.name


class Client(models.Model):
    user = models.ForeignKey("users.User", on_delete=models.PROTECT, null=True, blank=True, related_name="client_profiles")
    business_name = models.CharField(max_length=160)
    email = models.EmailField(unique=True)
    phone = models.CharField(max_length=40, blank=True)
    address = models.CharField(max_length=220, blank=True)
    country = models.ForeignKey(
        Country,
        on_delete=models.PROTECT,
        related_name="clients",
    )
    organization = models.ForeignKey(
        "users.Organization",
        on_delete=models.PROTECT,
        related_name="clients",
        null=True,
        blank=True,
    )
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["business_name"]

    def __str__(self):
        return self.business_name
