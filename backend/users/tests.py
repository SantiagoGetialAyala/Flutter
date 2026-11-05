from django.test import TestCase
from rest_framework import status
from rest_framework.test import APIClient

from .models import AuditEvent, Membership, Organization, Role, User


class AuthApiTests(TestCase):
    def setUp(self):
        User.objects.filter(email="admin@ritech.test").delete()
        self.role, _ = Role.objects.get_or_create(name=Role.ADMINISTRADOR)
        self.user = User.objects.create_user(
            email="admin@ritech.test",
            password="PruebaSegura123",
            role=self.role,
        )
        self.client = APIClient()

    def test_login_success(self):
        response = self.client.post(
            "/api/auth/login/",
            {"email": "admin@ritech.test", "password": "PruebaSegura123"},
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertIn("access", response.data)

    def test_login_invalid_password(self):
        response = self.client.post(
            "/api/auth/login/",
            {"email": "admin@ritech.test", "password": "incorrecta"},
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_users_endpoint_requires_authentication(self):
        response = self.client.get("/api/users/")
        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_public_registration_can_choose_a_safe_account_type(self):
        response = self.client.post(
            "/api/auth/register/",
            {
                "first_name": "Ana",
                "email": "producer@ritech.test",
                "password": "Fuerte-y-segura-739!",
                "password_confirm": "Fuerte-y-segura-739!",
                "role": Role.PRODUCTOR,
            },
            format="json",
        )
        self.assertEqual(response.status_code, status.HTTP_201_CREATED, response.data)
        self.assertEqual(response.data["user"]["role"], Role.PRODUCTOR)

    def test_public_registration_cannot_assign_privileged_role(self):
        response = self.client.post(
            "/api/auth/register/",
            {
                "email": "attacker@ritech.test",
                "password": "Fuerte-y-segura-739!",
                "password_confirm": "Fuerte-y-segura-739!",
                "role": Role.ADMINISTRADOR,
            },
            format="json",
        )
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertFalse(User.objects.filter(email="attacker@ritech.test").exists())


class OrganizationIsolationTests(TestCase):
    def setUp(self):
        role = Role.objects.get(name=Role.ADMINISTRADOR)
        self.owner = User.objects.create_user(email="owner@ritech.test", password="PruebaSegura123", role=role)
        commercial_role, _ = Role.objects.get_or_create(name=Role.COMERCIAL)
        self.other = User.objects.create_user(email="other@ritech.test", password="PruebaSegura123", role=commercial_role)
        self.organization = Organization.objects.create(name="Exportadora Andina")
        Membership.objects.create(organization=self.organization, user=self.owner, role=role)
        self.client = APIClient()

    def test_user_only_sees_organizations_they_belong_to(self):
        self.client.force_authenticate(self.other)
        response = self.client.get("/api/organizations/")
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["results"], [])

    def test_user_cannot_read_another_organization(self):
        self.client.force_authenticate(self.other)
        response = self.client.get(f"/api/organizations/{self.organization.pk}/")
        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def test_creating_organization_assigns_owner_and_audit_event(self):
        self.client.force_authenticate(self.other)
        response = self.client.post("/api/organizations/", {"name": "Nueva Exportadora"}, format="json")
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        created = Organization.objects.get(pk=response.data["id"])
        self.assertTrue(Membership.objects.filter(organization=created, user=self.other, role__name=Role.ADMINISTRADOR).exists())
        self.assertTrue(AuditEvent.objects.filter(organization=created, actor=self.other, action="organization.created").exists())
