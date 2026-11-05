import base64
import tempfile
from datetime import date, timedelta
from decimal import Decimal
from django.test import TestCase, override_settings
from django.utils import timezone
from rest_framework.test import APIClient
from catalog.models import Client, Country
from operations.models import ExportOperation, Producer, ProductLot, Farm
from users.models import AuditEvent, Membership, Organization, Role, RoleGrant, User
from . import models as m


@override_settings(PASSWORD_HASHERS=["django.contrib.auth.hashers.MD5PasswordHasher"])
class RoleBusinessTests(TestCase):
    def setUp(self):
        media = self.enterContext(tempfile.TemporaryDirectory(prefix="ritech-test-"))
        self.enterContext(override_settings(MEDIA_ROOT=media))
        self.org = Organization.objects.create(name='Exportadora de pruebas')
        self.other_org = Organization.objects.create(name='Otra empresa')
        self.users = {}
        for role, _ in Role.ROLE_CHOICES:
            obj, _ = Role.objects.get_or_create(name=role)
            user = User.objects.create_user(email=f'{role}@test.local', password='Valid-Password-123!', role=obj)
            self.users[role] = user
            if role != 'superadmin':
                Membership.objects.create(user=user, organization=self.org, role=obj)
        self.producer = Producer.objects.create(organization=self.org, name='Origen uno', user=self.users['productor'])
        self.other_producer = Producer.objects.create(organization=self.org, name='Origen privado')
        self.lot = ProductLot.objects.create(organization=self.org, producer=self.producer, code='L1', product_type='cafe', quantity_initial=100, quantity_available=100)
        country, _ = Country.objects.get_or_create(code='DE', defaults={'name': 'Alemania'})
        self.buyer = Client.objects.create(organization=self.org, user=self.users['importador'], email='cliente@test.local', business_name='Cliente propio', country=country)
        self.other_buyer = Client.objects.create(organization=self.org, email='otro@test.local', business_name='Cliente ajeno', country=country)
        self.export = ExportOperation.objects.create(organization=self.org, code='E1', importer=self.buyer, destination_country='Alemania', responsible=self.users['exportaciones'], commercial_value=500, commercial_terms='Confidencial')
        self.other_export = ExportOperation.objects.create(organization=self.org, code='E2', importer=self.other_buyer, destination_country='Alemania', responsible=self.users['exportaciones'])
        self.client = APIClient()
        self.login('administrador')

    def login(self, role):
        self.client.force_authenticate(self.users[role])
        self.client.credentials(HTTP_X_ORGANIZATION_ID=str(self.org.pk))

    def post(self, path, data):
        return self.client.post('/api/' + path, data, format='json')

    def create_doc(self, **overrides):
        data = {'title': 'Certificado origen', 'document_type': 'origen', 'export': self.export.pk, **overrides}
        response = self.post('documents/', data)
        self.assertEqual(response.status_code, 201, response.data)
        return response.data['id']

    def upload(self, doc):
        response = self.post(f'documents/{doc}/upload/', {'filename': 'certificado.pdf', 'content': base64.b64encode(b'%PDF-1.4 test evidence').decode()})
        self.assertEqual(response.status_code, 200, response.data)

    def test_all_roles_have_distinct_workspaces(self):
        for role in self.users:
            with self.subTest(role=role):
                self.login(role)
                if role == 'superadmin':
                    self.client.credentials()
                response = self.client.get('/api/workspace/')
                self.assertEqual(response.status_code, 200, response.data)
                self.assertEqual(response.data['role'], role)
                keys = {row['key'] for row in response.data['modules']}
                self.assertTrue(keys)
                if role in ('productor', 'importador', 'logistica', 'documental'):
                    self.assertNotIn('finance', keys)
                if role == 'importador':
                    self.assertNotIn('producers', keys)

    def test_membership_role_overrides_global_profile(self):
        Membership.objects.filter(user=self.users['comercial']).update(role=Role.objects.get(name='productor'))
        self.login('comercial')
        response = self.client.get('/api/workspace/')
        self.assertEqual(response.data['role'], 'productor')
        self.assertEqual(self.post('exports/', {'code': 'ATTACK'}).status_code, 403)

    def test_producer_reads_and_modifies_only_own_origin(self):
        own = Farm.objects.create(organization=self.org, producer=self.producer, code='OWN', name='Propia', area=1)
        other = Farm.objects.create(organization=self.org, producer=self.other_producer, code='PRIVATE', name='Ajena', area=1)
        self.login('productor')
        response = self.client.get('/api/farms/')
        self.assertEqual([item['id'] for item in response.data['results']], [own.pk])
        self.assertEqual(self.client.patch(f'/api/farms/{other.pk}/', {'name': 'Ataque'}, format='json').status_code, 404)
        response = self.post('farms/', {'producer': self.other_producer.pk, 'code': 'ATTACK', 'name': 'Ataque', 'area': 1})
        self.assertEqual(response.status_code, 400)
        self.assertEqual(self.client.get('/api/finance/').status_code, 403)

    def test_importer_isolated_from_other_clients_and_internal_files(self):
        own = m.Document.objects.create(organization=self.org, owner=self.users['documental'], export=self.export, title='Compartido', document_type='origen', status='aprobado', shared_with_client=True)
        private = m.Document.objects.create(organization=self.org, owner=self.users['documental'], export=self.export, title='Interno', document_type='interno', status='aprobado')
        other = m.Document.objects.create(organization=self.org, owner=self.users['documental'], export=self.other_export, title='Otro cliente', document_type='origen', status='aprobado', shared_with_client=True)
        self.login('importador')
        response = self.client.get('/api/exports/')
        self.assertEqual([item['id'] for item in response.data['results']], [self.export.pk])
        self.assertNotIn('commercial_value', response.data['results'][0])
        self.assertNotIn('commercial_terms', response.data['results'][0])
        response = self.client.get('/api/documents/')
        self.assertEqual([item['id'] for item in response.data['results']], [own.pk])
        for doc in (private, other):
            self.assertEqual(self.client.get(f'/api/documents/{doc.pk}/download/').status_code, 404)
        self.assertEqual(self.client.patch(f'/api/exports/{self.export.pk}/', {'commercial_value': 1}, format='json').status_code, 403)

    def test_cross_organization_foreign_key_rejected(self):
        supplier = m.Supplier.objects.create(organization=self.other_org, name='Ajeno')
        self.login('financiero')
        response = self.post('quotes/', {'export': self.export.pk, 'supplier': supplier.pk, 'description': 'Prueba', 'amount': 10, 'currency': 'EUR', 'valid_until': '2027-01-01'})
        self.assertEqual(response.status_code, 400)
        self.client.credentials(HTTP_X_ORGANIZATION_ID=str(self.other_org.pk))
        self.assertEqual(self.client.get('/api/finance/').status_code, 403)

    def test_document_versions_review_and_audit(self):
        self.login('exportaciones')
        doc = self.create_doc()
        self.assertEqual(self.post(f'documents/{doc}/submit/', {}).status_code, 400)
        self.upload(doc)
        self.assertEqual(self.post(f'documents/{doc}/submit/', {}).status_code, 200)
        self.assertEqual(self.post(f'documents/{doc}/approve/', {}).status_code, 403)
        self.login('documental')
        self.assertEqual(self.post(f'documents/{doc}/approve/', {'notes': 'Verificado'}).status_code, 200)
        self.assertEqual(self.client.get(f'/api/documents/{doc}/download/').status_code, 200)
        self.login('exportaciones')
        self.upload(doc)
        document = m.Document.objects.get(pk=doc)
        self.assertEqual(document.status, 'borrador')
        self.assertEqual(document.versions.count(), 2)
        self.assertTrue(AuditEvent.objects.filter(action='document.downloaded').exists())

    def test_no_self_approval_and_no_approval_of_expired_document(self):
        self.login('documental')
        doc = self.create_doc(expires_on='2020-01-01')
        self.upload(doc)
        self.post(f'documents/{doc}/submit/', {})
        self.assertEqual(self.post(f'documents/{doc}/approve/', {}).status_code, 403)
        self.login('administrador')
        self.assertEqual(self.post(f'documents/{doc}/approve/', {}).status_code, 400)

    def test_compliance_blocks_export_until_every_requirement_is_met(self):
        self.export.status = 'en_revision'
        self.export.save()
        self.login('documental')
        self.assertEqual(self.post(f'exports/{self.export.pk}/transition/', {'status': 'aprobada_despacho'}).status_code, 400)
        requirement = self.post('requirements/', {'name': 'Certificado de origen', 'document_type': 'origen', 'mandatory': True})
        self.assertEqual(requirement.status_code, 201, requirement.data)
        self.login('exportaciones')
        doc = self.create_doc()
        self.upload(doc)
        self.post(f'documents/{doc}/submit/', {})
        self.login('documental')
        self.post(f'documents/{doc}/approve/', {'notes': 'Validado'})
        check = self.post('checklist/', {'export': self.export.pk, 'requirement': requirement.data['id'], 'passed': True})
        self.assertEqual(check.status_code, 201, check.data)
        evaluation = self.post('compliance/', {'export': self.export.pk, 'result': 'conforme', 'notes': 'Expediente completo'})
        self.assertEqual(evaluation.status_code, 201, evaluation.data)
        response = self.post(f'exports/{self.export.pk}/transition/', {'status': 'aprobada_despacho'})
        self.assertEqual(response.status_code, 200, response.data)

    def test_transport_assignment_isolation_and_evidence_flow(self):
        transport = m.Transport.objects.create(organization=self.org, export=self.export, assigned_to=self.users['logistica'], pickup_place='Finca', delivery_place='Puerto', scheduled_pickup=timezone.now())
        other = m.Transport.objects.create(organization=self.org, export=self.other_export, assigned_to=self.users['exportaciones'], pickup_place='Otra', delivery_place='Puerto', scheduled_pickup=timezone.now())
        self.login('logistica')
        response = self.client.get('/api/transports/')
        self.assertEqual([r['id'] for r in response.data['results']], [transport.pk])
        self.assertEqual(self.client.patch(f'/api/transports/{other.pk}/', {'waybill': 'X'}, format='json').status_code, 404)
        response = self.client.patch(f'/api/exports/{self.export.pk}/', {'commercial_terms': 'Ataque'}, format='json')
        self.assertEqual(response.status_code, 403)
        self.assertEqual(self.post('transport-events/', {'transport': transport.pk, 'event_type': 'entrega', 'event_at': timezone.now().isoformat()}).status_code, 400)
        doc = self.create_doc(document_type='fotografia')
        self.upload(doc)
        for event in ('recogida', 'inicio', 'entrega'):
            response = self.post('transport-events/', {'transport': transport.pk, 'event_type': event, 'event_at': timezone.now().isoformat(), 'evidence': doc})
            self.assertEqual(response.status_code, 201, response.data)
        transport.refresh_from_db()
        self.assertEqual(transport.status, 'entregado')
        self.assertIsNotNone(transport.actual_delivery)

    def test_financial_conversions_payments_and_profit_report(self):
        self.login('financiero')
        rate = self.post('exchange-rates/', {'base_currency': 'USD', 'target_currency': 'EUR', 'rate': '.9', 'rate_date': date.today().isoformat(), 'source': 'Fuente de prueba'})
        self.assertEqual(rate.status_code, 201, rate.data)
        cost = self.post('finance/', {'export': self.export.pk, 'kind': 'costo', 'category': 'seguro', 'description': 'Seguro', 'amount': '100', 'currency': 'USD', 'exchange_rate': rate.data['id'], 'paid_amount': '20'})
        self.assertEqual(cost.status_code, 201, cost.data)
        self.assertEqual(Decimal(cost.data['base_amount']), Decimal('90'))
        self.assertEqual(cost.data['payment_status'], 'parcial')
        self.assertEqual(self.client.patch(f"/api/finance/{cost.data['id']}/", {'paid_amount': 101}, format='json').status_code, 400)
        revenue = self.post('finance/', {'export': self.export.pk, 'kind': 'ingreso', 'category': 'venta', 'description': 'Venta', 'amount': 200, 'currency': 'EUR'})
        self.assertEqual(revenue.status_code, 201, revenue.data)
        report = self.client.get('/api/finance/report/')
        self.assertEqual(report.status_code, 200, report.data)
        self.assertEqual(report.data['operations'][0]['margin'], Decimal('110'))
        self.assertEqual(self.post('farms/', {'name': 'Ataque'}).status_code, 403)
        self.assertEqual(self.post('documents/1/approve/', {}).status_code, 403)

    def test_invitation_acceptance_role_revocation_and_no_global_escalation(self):
        invitation = self.post('invitations/', {'email': self.users['importador'].email, 'role': 'documental'})
        self.assertEqual(invitation.status_code, 201, invitation.data)
        self.assertEqual(self.post('invitations/', {'email': 'x@test.local', 'role': 'superadmin'}).status_code, 400)
        self.login('productor')
        self.assertEqual(self.post('invitations/accept/', {'token': invitation.data['token']}).status_code, 400)
        self.login('importador')
        self.assertEqual(self.post('invitations/accept/', {'token': invitation.data['token']}).status_code, 200)
        self.assertEqual(Membership.objects.get(user=self.users['importador']).role.name, 'documental')
        self.login('administrador')
        member = Membership.objects.get(user=self.users['importador'])
        self.assertEqual(self.client.patch(f'/api/members/{member.pk}/', {'is_active': False}, format='json').status_code, 200)
        self.assertEqual(self.client.get('/api/platform-users/').status_code, 403)
        self.login('importador')
        self.assertEqual(self.client.get('/api/documents/').status_code, 403)

    def test_platform_sensitive_access_requires_justification_and_is_audited(self):
        self.login('superadmin')
        self.assertEqual(self.client.get('/api/exports/').status_code, 403)
        self.client.credentials(HTTP_X_ORGANIZATION_ID=str(self.org.pk), HTTP_X_ACCESS_REASON='Investigar incidente autorizado por la empresa')
        self.assertEqual(self.client.get('/api/exports/').status_code, 200)
        self.assertTrue(AuditEvent.objects.filter(action='security.exceptional_access', organization=self.org).exists())
        self.assertEqual(self.client.patch(f'/api/exports/{self.export.pk}/', {'notes': 'Ataque'}, format='json').status_code, 403)
        self.client.credentials()
        self.assertEqual(self.client.get('/api/platform-users/').status_code, 200)
        self.assertEqual(self.client.get('/api/service-status/').status_code, 200)

    def test_central_permission_override_takes_effect(self):
        RoleGrant.objects.create(role=Role.objects.get(name='exportaciones'), module='exports', action='create', allowed=False)
        self.login('exportaciones')
        self.assertEqual(self.post('exports/', {}).status_code, 403)
        workspace = self.client.get('/api/workspace/')
        module = next(x for x in workspace.data['modules'] if x['key'] == 'exports')
        self.assertFalse(module['can_create'])

    def test_client_confirmation_and_business_approval(self):
        self.export.status = 'arribada'
        self.export.save()
        order = m.Order.objects.create(organization=self.org, export=self.export, reference='P1', description='Café', quantity=20)
        other_order = m.Order.objects.create(organization=self.org, export=self.other_export, reference='P2', description='Privado', quantity=10)
        self.login('importador')
        self.assertEqual(self.post(f'orders/{other_order.pk}/confirm/', {}).status_code, 404)
        self.assertEqual(self.post(f'orders/{order.pk}/confirm/', {'notes': 'Recibido completo'}).status_code, 200)
        self.login('exportaciones')
        approval = self.post('approvals/', {'export': self.export.pk, 'title': 'Cambio de ruta', 'reason': 'Cierre de puerto'})
        self.assertEqual(approval.status_code, 201, approval.data)
        self.login('administrador')
        self.assertEqual(self.post(f"approvals/{approval.data['id']}/approve/", {'notes': 'Autorizado'}).status_code, 200)
        self.assertTrue(m.Notification.objects.filter(recipient=self.users['exportaciones']).exists())

    def test_platform_can_suspend_account_and_module_switch_revokes_access(self):
        self.login('superadmin')
        self.client.credentials()
        response = self.client.patch(f"/api/platform-users/{self.users['productor'].pk}/", {'account_status': 'suspendida'}, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        self.users['productor'].refresh_from_db()
        self.assertFalse(self.users['productor'].is_active)
        response = self.post('auth/login/', {'email': self.users['productor'].email, 'password': 'Valid-Password-123!'})
        self.assertEqual(response.status_code, 400)
        switch = self.post('platform-settings/', {'key': 'module.finance', 'value': 'Deshabilitado para mantenimiento', 'enabled': False})
        self.assertEqual(switch.status_code, 201, switch.data)
        self.login('financiero')
        self.assertEqual(self.client.get('/api/finance/').status_code, 403)

    def test_producer_uploads_origin_evidence_and_cannot_release_stock_twice(self):
        self.login('productor')
        doc = self.create_doc(export=None, producer=self.producer.pk)
        self.upload(doc)
        self.assertEqual(self.post('inventory-movements/', {'lot': self.lot.pk, 'movement_type': 'liberacion', 'quantity': 100}).status_code, 400)
        self.lot.refresh_from_db()
        self.assertEqual(self.lot.quantity_available, 100)

    def test_logistics_registers_own_vehicle_and_driver_without_operator_input(self):
        self.login('logistica')
        vehicle = self.post('vehicles/', {'plate': 'ABC-123', 'description': 'Camión'})
        self.assertEqual(vehicle.status_code, 201, vehicle.data)
        self.assertEqual(vehicle.data['operator'], self.users['logistica'].pk)
        driver = self.post('drivers/', {'name': 'Pedro', 'license_number': 'LIC-123', 'license_expires_on': '2028-01-01'})
        self.assertEqual(driver.status_code, 201, driver.data)
        self.assertEqual(driver.data['operator'], self.users['logistica'].pk)
        workspace = self.client.get('/api/workspace/')
        docs = next(row for row in workspace.data['modules'] if row['key'] == 'documents')
        self.assertNotIn('producer', {field['key'] for field in docs['fields']})
        self.login('productor')
        workspace = self.client.get('/api/workspace/')
        docs = next(row for row in workspace.data['modules'] if row['key'] == 'documents')
        self.assertNotIn('export', {field['key'] for field in docs['fields']})

    def test_platform_onboards_company_and_first_administrator_by_invitation(self):
        self.login('superadmin')
        self.client.credentials()
        response = self.post('platform-organizations/', {'name': 'Nueva exportadora', 'tax_id': '900-111', 'administrator_email': 'empresa-admin@test.local'})
        self.assertEqual(response.status_code, 201, response.data)
        invitation = response.data['administrator_invitation']
        self.assertEqual(invitation['email'], 'empresa-admin@test.local')
        org = Organization.objects.get(pk=response.data['id'])
        self.assertFalse(Membership.objects.filter(organization=org).exists())
        user = User.objects.create_user(email='empresa-admin@test.local', password='A-valid-password-123!', role=Role.objects.get(name='comercial'))
        self.client.force_authenticate(user)
        self.assertEqual(self.post('invitations/accept/', {'token': invitation['token']}).status_code, 200)
        self.assertTrue(Membership.objects.filter(user=user, organization=org, role__name='administrador').exists())
        self.client.credentials(HTTP_X_ORGANIZATION_ID=str(org.pk))
        workspace = self.client.get('/api/workspace/')
        self.assertEqual(workspace.status_code, 200, workspace.data)
        self.assertEqual(workspace.data['role'], 'administrador')

    def test_platform_role_can_create_organization_without_django_superuser_flag(self):
        self.login('superadmin')
        self.client.credentials()
        self.assertFalse(self.users['superadmin'].is_superuser)
        response = self.post('organizations/', {'name': 'Empresa del operador'})
        self.assertEqual(response.status_code, 201, response.data)

    def test_same_user_can_switch_between_multiple_organizations_and_roles(self):
        Membership.objects.create(user=self.users['exportaciones'], organization=self.other_org, role=Role.objects.get(name='financiero'))
        self.login('exportaciones')
        response = self.client.get('/api/organizations/')
        self.assertEqual(response.data['count'], 2)
        response = self.client.get('/api/workspace/')
        self.assertEqual(response.data['role'], 'exportaciones')
        self.client.credentials(HTTP_X_ORGANIZATION_ID=str(self.other_org.pk))
        response = self.client.get('/api/workspace/')
        self.assertEqual(response.data['role'], 'financiero')
        self.assertEqual(response.data['organization'], self.other_org.name)
        self.assertEqual(self.client.get('/api/exports/').data['count'], 0)

    def test_export_document_filters_keep_detail_on_its_own_export(self):
        for export in (self.export, self.other_export):
            m.Document.objects.create(organization=self.org, export=export, owner=self.users['documental'], title=export.code, document_type='origen', status='pendiente')
        self.login('documental')
        response = self.client.get(f'/api/documents/?export={self.export.pk}&status=pendiente')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['count'], 1)
        self.assertEqual(response.data['results'][0]['export'], self.export.pk)
