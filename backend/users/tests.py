from datetime import timedelta
from django.test import TestCase
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APIClient

from .models import AuditEvent, Invitation, Membership, Organization, Role, User


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

    def test_registration_uses_assigned_invitation_role(self):
        invitation = self.make_invitation(email="producer@ritech.test")
        response = self.client.post(
            "/api/auth/register/",
            {
                "first_name": "Ana",
                "email": "producer@ritech.test",
                "password": "Fuerte-y-segura-739!",
                "password_confirm": "Fuerte-y-segura-739!",
                "invitation_code": str(invitation.token),
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

    def test_company_owner_signup_has_no_access_to_existing_company(self):
        other_company = Organization.objects.create(name='Empresa ajena')
        response = self.client.post('/api/auth/register-company/', {
            'email': 'owner-new@ritech.test', 'password': 'Fuerte-y-segura-739!',
            'password_confirm': 'Fuerte-y-segura-739!', 'company_name': 'Mi exportadora', 'tax_id': 'PRUEBA-123',
        }, format='json')
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data['user']['role'], Role.ADMINISTRADOR)
        user = User.objects.get(email='owner-new@ritech.test')
        self.assertTrue(Membership.objects.filter(user=user, organization__name='Mi exportadora', role__name='administrador').exists())
        self.assertTrue(AuditEvent.objects.filter(actor=user, action='organization.created').exists())
        self.client.credentials(HTTP_AUTHORIZATION='Bearer ' + response.data['access'])
        self.assertEqual(self.client.get('/api/workspace/').status_code, 200)
        self.assertEqual(self.client.get(f'/api/organizations/{other_company.pk}/').status_code, 404)

    def register_with_invitation(self, invitation, email=None):
        return self.client.post('/api/auth/register/', {
            'email': email or invitation.email,
            'password': 'Fuerte-y-segura-739!',
            'password_confirm': 'Fuerte-y-segura-739!',
            'invitation_code': str(invitation.token),
        }, format='json')

    def test_registration_without_invitation_does_not_create_an_unassigned_account(self):
        response = self.client.post('/api/auth/register/', {
            'email': 'sin-invitacion@ritech.test', 'password': 'Fuerte-y-segura-739!',
            'password_confirm': 'Fuerte-y-segura-739!',
        }, format='json')
        self.assertEqual(response.status_code, 400)
        self.assertIn('email', response.data)
        self.assertFalse(User.objects.filter(email='sin-invitacion@ritech.test').exists())

    def test_old_form_role_is_ignored_and_invitation_assignment_wins(self):
        invitation = self.make_invitation()
        response = self.client.post('/api/auth/register/', {
            'email': invitation.email, 'password': 'Fuerte-y-segura-739!',
            'password_confirm': 'Fuerte-y-segura-739!',
            'invitation_code': str(invitation.token), 'role': Role.ADMINISTRADOR,
        }, format='json')
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data['user']['role'], Role.PRODUCTOR)
        invitation.refresh_from_db()
        self.assertIsNotNone(invitation.accepted_at)
        self.assertTrue(Membership.objects.filter(user__email=invitation.email, role=invitation.role, organization=invitation.organization).exists())

    def test_company_registration_is_atomic_when_account_data_is_invalid(self):
        response = self.client.post('/api/auth/register-company/', {
            'email': 'error@ritech.test', 'password': 'Fuerte-y-segura-739!',
            'password_confirm': 'No-coincide-739!', 'company_name': 'No crear empresa',
        }, format='json')
        self.assertEqual(response.status_code, 400)
        self.assertFalse(Organization.objects.filter(name='No crear empresa').exists())
        self.assertFalse(User.objects.filter(email='error@ritech.test').exists())

    def make_invitation(self, **overrides):
        return Invitation.objects.create(**{
            'organization': Organization.objects.create(name='Exportadora'),
            'email': 'invitado@ritech.test',
            'role': Role.objects.get(name=Role.PRODUCTOR),
            'expires_at': timezone.now() + timedelta(days=1),
            **overrides,
        })

    def test_register_with_invitation_enters_company_as_assigned_producer(self):
        invitation = self.make_invitation()
        response = self.register_with_invitation(invitation)
        self.assertEqual(response.status_code, 201, response.data)
        user = User.objects.get(email=invitation.email)
        self.assertEqual(response.data['user']['role'], Role.PRODUCTOR)
        self.assertTrue(Membership.objects.filter(user=user,
            organization=invitation.organization, role=invitation.role, is_active=True).exists())
        invitation.refresh_from_db()
        self.assertIsNotNone(invitation.accepted_at)
        self.assertTrue(AuditEvent.objects.filter(actor=user, action='invitation.accepted').exists())
        self.client.credentials(HTTP_AUTHORIZATION='Bearer ' + response.data['access'])
        workspace = self.client.get('/api/workspace/')
        self.assertEqual(workspace.status_code, 200)
        self.assertEqual(workspace.data['role'], Role.PRODUCTOR)

    def test_email_alone_resolves_admin_assignment_for_each_business_role(self):
        for role_name in Role.BUSINESS_ROLES:
            invitation = self.make_invitation(email=f'{role_name}@correo.test',
                role=Role.objects.get(name=role_name))
            response = self.client.post('/api/auth/register/', {
                'email': invitation.email, 'password': 'Fuerte-y-segura-739!',
                'password_confirm': 'Fuerte-y-segura-739!',
            }, format='json')
            self.assertEqual(response.status_code, 201, response.data)
            self.assertEqual(response.data['user']['role'], role_name)
            self.assertTrue(Membership.objects.filter(user_id=response.data['user']['id'],
                organization=invitation.organization, role=invitation.role).exists())
            invitation.refresh_from_db()
            self.assertIsNotNone(invitation.accepted_at)

    def test_email_registration_uses_most_recent_valid_assignment_not_client_role(self):
        previous = self.make_invitation()
        latest = self.make_invitation(role=Role.objects.get(name=Role.LOGISTICA))
        response = self.client.post('/api/auth/register/', {
            'email': latest.email.upper(), 'password': 'Fuerte-y-segura-739!',
            'password_confirm': 'Fuerte-y-segura-739!', 'role': 'administrador',
        }, format='json')
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data['user']['role'], Role.LOGISTICA)
        memberships = Membership.objects.filter(user_id=response.data['user']['id'])
        self.assertEqual(memberships.count(), 1)
        self.assertEqual(memberships.get().organization, latest.organization)
        self.assertNotEqual(latest.organization, previous.organization)

    def test_email_registration_rejects_expired_used_or_inactive_assignments(self):
        for index, kind in enumerate(('expired', 'used', 'company', 'role')):
            invitation = self.make_invitation(email=f'invalido-{index}@correo.test')
            if kind == 'expired':
                invitation.expires_at = timezone.now() - timedelta(seconds=1)
                invitation.save()
            elif kind == 'used':
                invitation.accepted_at = timezone.now()
                invitation.save()
            elif kind == 'company':
                invitation.organization.is_active = False
                invitation.organization.save()
            else:
                invitation.role.is_active = False
                invitation.role.save()
            response = self.client.post('/api/auth/register/', {
                'email': invitation.email, 'password': 'Fuerte-y-segura-739!',
                'password_confirm': 'Fuerte-y-segura-739!',
            }, format='json')
            self.assertEqual(response.status_code, 400, response.data)
            self.assertFalse(User.objects.filter(email=invitation.email).exists())

    def test_invalid_invitation_does_not_leave_an_account_or_membership(self):
        for overrides in (
            {'expires_at': timezone.now() - timedelta(seconds=1)},
            {'accepted_at': timezone.now()},
            {},
        ):
            with self.subTest(overrides=overrides):
                invitation = self.make_invitation(**overrides)
                email = 'otro@ritech.test' if not overrides else invitation.email
                response = self.register_with_invitation(invitation, email=email)
                self.assertEqual(response.status_code, 400, response.data)
                self.assertFalse(User.objects.filter(email=email).exists())
                self.assertFalse(Membership.objects.filter(organization=invitation.organization).exists())

    def test_invitation_assigns_transporter_role_without_public_role_selection(self):
        invitation = self.make_invitation(role=Role.objects.get(name=Role.LOGISTICA))
        response = self.register_with_invitation(invitation)
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data['user']['role'], Role.LOGISTICA)


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
