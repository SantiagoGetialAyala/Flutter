from django.test import TestCase
from rest_framework import status
from rest_framework.test import APIClient

from users.models import Role, User, Organization, Membership

from .models import Client, Country, Product


class CatalogApiTests(TestCase):
    def setUp(self):
        User.objects.filter(email__in=["admin@ritech.test", "viewer@ritech.test"]).delete()
        Client.objects.filter(email="cliente@europa.test").delete()
        self.admin_role, _ = Role.objects.get_or_create(name=Role.ADMINISTRADOR)
        self.viewer_role, _ = Role.objects.get_or_create(name=Role.GERENCIA)
        self.admin = User.objects.create_user(
            email="admin@ritech.test",
            password="PruebaSegura123",
            role=self.admin_role,
        )
        self.viewer = User.objects.create_user(
            email="viewer@ritech.test",
            password="PruebaSegura123",
            role=self.viewer_role,
        )
        self.country, _ = Country.objects.get_or_create(
            code="DE",
            defaults={"name": "Alemania"},
        )
        self.organization = Organization.objects.create(name='Empresa de catálogo')
        Membership.objects.create(organization=self.organization, user=self.admin, role=self.admin_role)
        Membership.objects.create(organization=self.organization, user=self.viewer, role=self.viewer_role)
        self.client = APIClient()

    def test_product_crud_as_admin(self):
        self.client.force_authenticate(self.admin)
        response = self.client.post(
            "/api/products/",
            {
                "name": "Cafe excelso",
                "product_type": Product.COFFEE,
                "quantity": "20.00",
                "unit": Product.KG,
                "description": "Lote premium",
                "is_active": True,
            },
            format="json",
        )
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)

        product_id = response.data["id"]
        response = self.client.put(
            f"/api/products/{product_id}/",
            {
                "name": "Cafe excelso actualizado",
                "product_type": Product.COFFEE,
                "quantity": "25.00",
                "unit": Product.KG,
                "description": "",
                "is_active": True,
            },
            format="json",
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)

        response = self.client.delete(f"/api/products/{product_id}/")
        self.assertEqual(response.status_code, status.HTTP_204_NO_CONTENT)

    def test_viewer_cannot_create_product(self):
        self.client.force_authenticate(self.viewer)
        response = self.client.post(
            "/api/products/",
            {
                "name": "Cacao",
                "product_type": Product.CACAO,
                "quantity": "10.00",
                "unit": Product.KG,
            },
            format="json",
        )
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_client_crud_as_admin(self):
        self.client.force_authenticate(self.admin)
        response = self.client.post(
            "/api/clients/",
            {
                "business_name": "Importadora Europa",
                "email": "cliente@europa.test",
                "phone": "+49 555",
                "address": "Berlin",
                "country": self.country.id,
                "is_active": True,
            },
            format="json",
        )
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertTrue(Client.objects.filter(email="cliente@europa.test").exists())
