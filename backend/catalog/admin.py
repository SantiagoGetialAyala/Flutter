from django.contrib import admin

from .models import Client, Country, Product


@admin.register(Country)
class CountryAdmin(admin.ModelAdmin):
    list_display = ("name", "code", "is_active")
    search_fields = ("name", "code")
    list_filter = ("is_active",)


@admin.register(Product)
class ProductAdmin(admin.ModelAdmin):
    list_display = ("name", "product_type", "quantity", "unit", "is_active")
    search_fields = ("name", "description")
    list_filter = ("product_type", "unit", "is_active")


@admin.register(Client)
class ClientAdmin(admin.ModelAdmin):
    list_display = ("business_name", "email", "country", "is_active")
    search_fields = ("business_name", "email")
    list_filter = ("country", "is_active")
