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
            obj, _ = Role.objects.update_or_create(name=role, defaults={'is_active': True})
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
        invitation = self.post('invitations/', {'email': self.users['importador'].email, 'role': 'productor'})
        self.assertEqual(invitation.status_code, 201, invitation.data)
        self.assertEqual(self.post('invitations/', {'email': 'x@test.local', 'role': 'superadmin'}).status_code, 400)
        self.login('productor')
        self.assertEqual(self.post('invitations/accept/', {'token': invitation.data['token']}).status_code, 400)
        self.login('importador')
        self.assertEqual(self.post('invitations/accept/', {'token': invitation.data['token']}).status_code, 200)
        self.assertEqual(Membership.objects.get(user=self.users['importador']).role.name, 'productor')
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

    def test_task_feed_respects_owner_tenant_and_action_grants(self):
        own = m.Activity.objects.create(organization=self.org, export=self.export,
            title='Mi trabajo', assigned_to=self.users['exportaciones'], due_at=timezone.now() - timedelta(days=1))
        m.Activity.objects.create(organization=self.org, export=self.export,
            title='Trabajo ajeno', assigned_to=self.users['documental'], due_at=timezone.now())
        m.Activity.objects.create(organization=self.other_org, export=self.other_export,
            title='Otra organización', assigned_to=self.users['exportaciones'], due_at=timezone.now())
        self.login('exportaciones')
        response = self.client.get('/api/workspace/')
        tasks = response.data['pending_tasks']
        titles = {task['title'] for task in tasks}
        self.assertIn('Mi trabajo', titles)
        self.assertNotIn('Trabajo ajeno', titles)
        self.assertNotIn('Otra organización', titles)
        self.assertTrue(next(t for t in tasks if t['record_id'] == own.pk and t['module'] == 'activities')['overdue'])
        role = Role.objects.get(name='exportaciones')
        RoleGrant.objects.create(role=role, module='activities', action='update', allowed=False)
        tasks = self.client.get('/api/workspace/').data['pending_tasks']
        self.assertFalse(any(t['module'] == 'activities' for t in tasks))

    def test_contexts_are_only_active_memberships(self):
        Membership.objects.create(user=self.users['exportaciones'], organization=self.other_org,
            role=Role.objects.get(name='documental'))
        self.login('exportaciones')
        contexts = self.client.get('/api/workspace/').data['contexts']
        self.assertEqual({c['role__name'] for c in contexts}, {'exportaciones', 'documental'})
        self.other_org.is_active = False
        self.other_org.save()
        contexts = self.client.get('/api/workspace/').data['contexts']
        self.assertEqual(len(contexts), 1)

    def test_export_related_filters_do_not_mix_dossiers(self):
        m.Activity.objects.create(organization=self.org, export=self.export, title='Expediente uno',
            assigned_to=self.users['exportaciones'], due_at=timezone.now())
        m.Activity.objects.create(organization=self.org, export=self.other_export, title='Expediente dos',
            assigned_to=self.users['exportaciones'], due_at=timezone.now())
        response = self.client.get(f'/api/activities/?export={self.export.pk}')
        rows = response.data['results']
        self.assertEqual([r['title'] for r in rows], ['Expediente uno'])
        self.assertEqual(self.client.get('/api/activities/?export=invalid').status_code, 400)

    def test_map_only_includes_linked_geography_and_authorized_events(self):
        from operations.models import Plot, Harvest, ExportLotAllocation, TraceabilityEvent
        farm = Farm.objects.create(organization=self.org, producer=self.producer, code='F-MAP', name='Finca', area=1)
        plot = Plot.objects.create(organization=self.org, farm=farm, code='P-MAP', crop_type='cafe', area=1,
            geometry={'type': 'Point', 'coordinates': [-76.6, 1.2]})
        harvest = Harvest.objects.create(organization=self.org, plot=plot, harvest_date=date.today(), product_type='cafe', quantity=10)
        self.lot.harvest = harvest
        self.lot.save()
        ExportLotAllocation.objects.create(organization=self.org, export=self.export, lot=self.lot, quantity=5)
        Plot.objects.create(organization=self.org, farm=farm, code='P-OTHER', crop_type='cafe', area=1,
            geometry={'type': 'Point', 'coordinates': [-75, 2]})
        TraceabilityEvent.objects.create(organization=self.org, export=self.export, lot=self.lot,
            event_type='origen', event_at=timezone.now(), actor=self.users['administrador'], location={'lat': 1.2, 'lng': -76.6})
        response = self.client.get(f'/api/exports/{self.export.pk}/map/')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual([p['code'] for p in response.data['plots']], ['P-MAP'])
        self.assertEqual(len(response.data['events']), 1)
        self.login('importador')
        response = self.client.get(f'/api/exports/{self.export.pk}/map/')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['plots'], [])
        self.assertEqual(response.data['events'], [])
        self.assertEqual(self.client.get(f'/api/exports/{self.other_export.pk}/map/').status_code, 404)

    def test_transition_hints_follow_role_status_and_revoked_grants(self):
        self.export.status = 'en_revision'
        self.export.save()
        self.login('exportaciones')
        data = self.client.get(f'/api/exports/{self.export.pk}/').data
        self.assertEqual(data['allowed_transitions'], [])
        self.login('documental')
        data = self.client.get(f'/api/exports/{self.export.pk}/').data
        self.assertIn('aprobada_despacho', data['allowed_transitions'])
        RoleGrant.objects.create(role=Role.objects.get(name='documental'), module='exports', action='approve', allowed=False)
        data = self.client.get(f'/api/exports/{self.export.pk}/').data
        self.assertNotIn('aprobada_despacho', data['allowed_transitions'])
        self.assertEqual(self.post(f'exports/{self.export.pk}/transition/', {'status': 'aprobada_despacho'}).status_code, 403)

    def test_importer_map_preserves_transport_field_redaction(self):
        m.Transport.objects.create(organization=self.org, export=self.export,
            assigned_to=self.users['logistica'], pickup_place='Origen interno privado',
            delivery_place='Destino público', scheduled_pickup=timezone.now())
        self.login('importador')
        response = self.client.get(f'/api/exports/{self.export.pk}/map/')
        self.assertEqual(response.status_code, 200, response.data)
        transport = response.data['transports'][0]
        self.assertEqual(transport['delivery_place'], 'Destino público')
        self.assertNotIn('pickup_place', transport)
        self.assertNotIn('scheduled_pickup', transport)

    def test_only_linked_importer_gets_order_confirmation_hint_and_task(self):
        self.export.status = 'arribada'
        self.export.save()
        order = m.Order.objects.create(organization=self.org, export=self.export,
            reference='PED-1', description='Pedido', quantity=10)
        self.login('administrador')
        self.assertFalse(self.client.get(f'/api/orders/{order.pk}/').data['can_confirm'])
        self.assertFalse(any(t['module'] == 'orders' for t in self.client.get('/api/workspace/').data['pending_tasks']))
        self.login('importador')
        self.assertTrue(self.client.get(f'/api/orders/{order.pk}/').data['can_confirm'])
        self.assertTrue(any(t['module'] == 'orders' for t in self.client.get('/api/workspace/').data['pending_tasks']))

    def test_document_review_task_excludes_own_uploads(self):
        doc = m.Document.objects.create(organization=self.org, export=self.export,
            owner=self.users['administrador'], title='Preparado por quien revisa', document_type='origen', status='borrador')
        self.login('documental')
        self.upload(doc.pk)
        doc.status = 'pendiente'
        doc.save()
        data = self.client.get(f'/api/documents/{doc.pk}/').data
        self.assertFalse(data['can_review'])
        self.assertFalse(data['can_approve'])
        tasks = self.client.get('/api/workspace/').data['pending_tasks']
        self.assertFalse(any(t['module'] == 'documents' and t['record_id'] == doc.pk for t in tasks))

    def test_export_form_offers_all_eu_destinations(self):
        self.login('exportaciones')
        modules = self.client.get('/api/workspace/').data['modules']
        export = next(m for m in modules if m['key'] == 'exports')
        field = next(f for f in export['fields'] if f['key'] == 'destination_country')
        self.assertEqual(field['type'], 'choice')
        self.assertEqual(len(field['choices']), 27)
        self.assertTrue({'España', 'Chequia', 'Suecia', 'Malta', 'Chipre'}.issubset(
            {c['value'] for c in field['choices']}))

    def test_documented_minimal_flow_from_origin_to_closed_export(self):
        def create(path, data):
            response = self.post(path + '/', data)
            self.assertEqual(response.status_code, 201, response.data)
            return response.data

        self.login('productor')
        farm = create('farms', {'producer': self.producer.pk, 'name': 'Finca prueba',
            'area': 2, 'department': 'Antioquia', 'municipality': 'Medellín',
            'geometry': {'type': 'Point', 'coordinates': [-75.58, 6.25]},
            'new_plots': [{'name': 'Área principal', 'area': 2, 'crop_type': 'cafe',
                'geometry': {'type': 'Point', 'coordinates': [-75.58, 6.25]}}]})
        harvest = create('harvests', {'plot': farm['plots'][0]['id'],
            'harvest_date': timezone.localdate().isoformat(), 'product_type': 'cafe',
            'quantity': 1000, 'unit': 'kg'})
        lot = create('lots', {'producer': self.producer.pk, 'code': 'PRUEBA-LOTE-001',
            'harvest': harvest['id'], 'product_type': 'cafe', 'quantity_initial': 1000, 'unit': 'kg'})
        self.login('administrador')
        export = create('exports', {'code': 'PRUEBA-EXP-001', 'importer': self.buyer.pk,
            'destination_country': 'Alemania', 'currency': 'EUR'})
        export_id = export['id']
        create('export-allocations', {'export': export_id, 'lot': lot['id'], 'quantity': 100, 'unit': 'kg'})
        order = create('orders', {'export': export_id, 'reference': 'PRUEBA-PED-001',
            'description': '100 kg de café', 'quantity': 100, 'unit': 'kg'})
        geography = self.client.get(f'/api/exports/{export_id}/map/')
        self.assertEqual(geography.status_code, 200)
        self.assertEqual(geography.data['plots'][0]['id'], farm['plots'][0]['id'])
        doc = create('documents', {'export': export_id, 'title': 'Origen prueba',
            'document_type': 'origen', 'shared_with_client': True})
        self.upload(doc['id'])
        self.assertEqual(self.post(f'documents/{doc["id"]}/submit/', {}).status_code, 200)

        def transition(state):
            response = self.post(f'exports/{export_id}/transition/', {'status': state})
            self.assertEqual(response.status_code, 200, response.data)
            self.assertEqual(response.data['status'], state)

        transition('pendiente_documentacion')
        self.login('administrador')
        requirement = create('requirements', {'name': 'Origen prueba', 'document_type': 'origen',
            'destination_country': 'Alemania', 'mandatory': True})
        transition('en_revision')
        self.assertEqual(self.post(f'documents/{doc["id"]}/approve/', {'notes': 'Archivo revisado'}).status_code, 200)
        create('checklist', {'export': export_id, 'requirement': requirement['id'], 'passed': True})
        create('compliance', {'export': export_id, 'result': 'conforme', 'notes': 'Expediente verificado'})
        transition('aprobada_despacho')

        self.login('administrador')
        transport = create('transports', {'export': export_id, 'assigned_to': self.users['logistica'].pk,
            'pickup_place': 'Finca prueba', 'delivery_place': 'Hamburgo',
            'scheduled_pickup': timezone.now().isoformat()})
        transition('preparacion_logistica')
        self.login('logistica')
        evidence = create('documents', {'export': export_id, 'title': 'Evidencia de prueba', 'document_type': 'evidencia'})
        self.upload(evidence['id'])
        for event in ('recogida', 'inicio', 'entrega'):
            create('transport-events', {'transport': transport['id'], 'event_type': event,
                'event_at': timezone.now().isoformat(), 'evidence': evidence['id']})
        self.login('administrador')
        for state in ('transporte_terrestre', 'embarcada', 'transito_internacional', 'arribada', 'entregada'):
            transition(state)
        self.login('importador')
        self.assertEqual(self.post(f'orders/{order["id"]}/confirm/', {'notes': 'Recibido completo'}).status_code, 200)
        self.assertEqual(len(self.client.get('/api/documents/').data['results']), 1)
        self.login('administrador')
        for kind, category, amount in [('ingreso', 'venta', 2500), ('costo', 'logistica', 300)]:
            create('finance', {'export': export_id, 'kind': kind, 'category': category,
                'description': 'Prueba ' + kind, 'amount': amount, 'paid_amount': amount,
                'currency': 'EUR', 'base_currency': 'EUR'})
        self.login('administrador')
        transition('cerrada')
        saved_lot = ProductLot.objects.get(pk=lot['id'])
        self.assertEqual(saved_lot.quantity_available, Decimal('900'))

    def test_administrator_enters_orders_and_external_roles_cannot(self):
        data = {'export': self.export.pk, 'reference': 'PED-NUEVO', 'description': 'Café', 'quantity': 10}
        for role in ('productor', 'importador', 'logistica', 'documental', 'financiero'):
            self.login(role)
            self.assertEqual(self.post('orders/', data).status_code, 403, role)
        self.login('exportaciones')
        self.assertEqual(self.post('orders/', data).status_code, 201)

    def test_administration_owns_finance_documents_and_export_tasks(self):
        m.FinanceEntry.objects.create(organization=self.org, export=self.export,
            actor=self.users['financiero'], kind='costo', description='Flete pendiente', amount=10, currency='USD', base_currency='USD', base_amount=10)
        m.Document.objects.create(organization=self.org, export=self.export,
            owner=self.users['exportaciones'], title='Para revisar', document_type='origen', status='pendiente')
        self.login('administrador')
        tasks = self.client.get('/api/workspace/').data['pending_tasks']
        self.assertTrue({'finance', 'exports', 'documents'}.issubset({t['module'] for t in tasks}))
        self.login('financiero')
        tasks = self.client.get('/api/workspace/').data['pending_tasks']
        self.assertTrue(any(t['module'] == 'finance' for t in tasks))

    def test_invitation_options_are_exactly_four_even_if_legacy_rows_exist(self):
        self.login('administrador')
        response = self.client.get('/api/role-options/')
        self.assertEqual(response.status_code, 200)
        self.assertEqual({row['id']: row['name'] for row in response.data}, {
            'administrador': 'Administrador', 'productor': 'Productor',
            'logistica': 'Transportador', 'importador': 'Importador'})
        for role in Role.LEGACY_ROLES:
            self.assertEqual(self.post('invitations/', {'email': 'nuevo@test.local', 'role': role}).status_code, 400)
        membership = Membership.objects.get(user=self.users['productor'], organization=self.org)
        self.assertEqual(self.client.patch(f'/api/members/{membership.pk}/', {'role': 'financiero'}, format='json').status_code, 400)

    def test_only_administrator_invites_and_manages_the_team(self):
        for role in ('productor', 'logistica', 'importador'):
            self.login(role)
            self.assertEqual(self.post('invitations/', {'email': 'nuevo@test.local', 'role': 'productor'}).status_code, 403)
            self.assertEqual(self.client.get('/api/role-options/').status_code, 403)
        self.login('administrador')
        self.assertEqual(self.post('invitations/', {'email': 'nuevo@test.local', 'role': 'logistica'}).status_code, 201)

    def test_administrator_can_review_own_uploaded_document_with_audit(self):
        self.login('administrador')
        doc = self.create_doc()
        self.upload(doc)
        self.assertEqual(self.post(f'documents/{doc}/submit/', {}).status_code, 200)
        data = self.client.get(f'/api/documents/{doc}/').data
        self.assertTrue(data['can_approve'])
        self.assertEqual(self.post(f'documents/{doc}/approve/', {'notes': 'Verificado por administrador'}).status_code, 200)
        self.assertTrue(AuditEvent.objects.filter(actor=self.users['administrador'],
            action='document.aprobado', resource_id=str(doc)).exists())
        self.assertEqual(self.post('transport-events/', {}).status_code, 403)

    def test_role_migration_preserves_accounts_invitations_and_export_responsibility(self):
        from importlib import import_module
        from types import SimpleNamespace
        from django.apps import apps
        from django.db import connection
        previous_user = self.users['exportaciones']
        from users.models import Invitation
        invitation = Invitation.objects.create(organization=self.org, email='pendiente@test.local',
            role=Role.objects.get(name='documental'), expires_at=timezone.now() + timedelta(days=1))
        migration = import_module('users.migrations.0007_four_business_roles')
        migration.consolidate_roles(apps, SimpleNamespace(connection=connection))
        previous_user.refresh_from_db()
        invitation.refresh_from_db()
        self.export.refresh_from_db()
        self.assertEqual(previous_user.role.name, 'administrador')
        self.assertEqual(self.export.responsible_id, previous_user.pk)
        self.assertEqual(invitation.role.name, 'administrador')
        self.assertFalse(Role.objects.filter(name__in=Role.LEGACY_ROLES, is_active=True).exists())
        self.assertFalse(Membership.objects.filter(role__name__in=Role.LEGACY_ROLES).exists())
        self.assertTrue(AuditEvent.objects.filter(action='membership.role_consolidated').exists())

    def test_legacy_destination_names_keep_exports_and_requirements_aligned(self):
        from importlib import import_module
        from types import SimpleNamespace
        from django.apps import apps
        from django.db import connection
        self.export.destination_country = 'Espana'
        self.export.save()
        requirement = m.Requirement.objects.create(organization=self.org,
            name='Origen España', document_type='origen', destination_country='Espana')
        migration = import_module('catalog.migrations.0007_align_destination_names')
        migration.align_destinations(apps, SimpleNamespace(connection=connection))
        self.export.refresh_from_db()
        requirement.refresh_from_db()
        self.assertEqual(self.export.destination_country, 'España')
        self.assertEqual(requirement.destination_country, 'España')
