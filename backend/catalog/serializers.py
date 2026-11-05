from rest_framework import serializers

from .models import Client, Country, Product


class CountrySerializer(serializers.ModelSerializer):
    class Meta:
        model = Country
        fields = ("id", "name", "code", "is_active")

    def validate_code(self, value):
        value = value.strip().upper()
        if len(value) < 2 or len(value) > 3:
            raise serializers.ValidationError("El codigo debe tener 2 o 3 caracteres.")
        return value


class ProductSerializer(serializers.ModelSerializer):
    product_type_display = serializers.CharField(
        source="get_product_type_display",
        read_only=True,
    )
    unit_display = serializers.CharField(source="get_unit_display", read_only=True)

    class Meta:
        model = Product
        fields = (
            "id",
            "name",
            "product_type",
            "product_type_display",
            "description",
            "quantity",
            "unit",
            "unit_display",
            "is_active",
        )
        read_only_fields = ("id",)

    def validate_name(self, value):
        value = value.strip()
        if not value:
            raise serializers.ValidationError("El nombre es obligatorio.")
        return value


class ClientSerializer(serializers.ModelSerializer):
    country_name = serializers.CharField(source="country.name", read_only=True)
    country_code = serializers.CharField(source="country.code", read_only=True)

    class Meta:
        model = Client
        fields = (
            "id",
            "business_name",
            "user",
            "email",
            "phone",
            "address",
            "country",
            "country_name",
            "country_code",
            "is_active",
        )
        read_only_fields = ("id",)

    def validate_user(self, value):
        from users.models import Membership
        if value and not Membership.objects.filter(user=value, organization=self.context['view'].get_membership().organization, is_active=True, role__name='importador').exists():
            raise serializers.ValidationError('Selecciona una cuenta importadora activa de esta empresa.')
        return value

    def validate_business_name(self, value):
        value = value.strip()
        if not value:
            raise serializers.ValidationError("La razon social es obligatoria.")
        return value
