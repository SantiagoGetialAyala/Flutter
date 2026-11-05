import os
import secrets
from datetime import timedelta
from django.conf import settings
from django.core.management.base import BaseCommand, CommandError
from django.db import transaction
from django.utils import timezone
from catalog.models import Client, Country, Product
from operations.models import Producer, Farm, ProductLot, ExportOperation, ExportLotAllocation
from users.models import User, Role, Membership, Organization
from business import models as m


class Command(BaseCommand):
    help = 'Crea un entorno separado para probar todos los roles; no modifica cuentas existentes.'

    @transaction.atomic
    def handle(self, *args, **options):
        path = settings.BASE_DIR / '.demo-credentials.txt'
        existing = path.exists()
        password = secrets.token_urlsafe(18)
        org, _ = Organization.objects.get_or_create(name='Laboratorio de roles RiTech', tax_id='DEMO-ROLES')
        accounts, created_accounts = {}, []
        for name, label in Role.ROLE_CHOICES:
            role, _ = Role.objects.get_or_create(name=name)
            email = f'{name}@roles.ritech.test'
            user = User.objects.filter(email=email).first()
            if user is None:
                user = User.objects.create_user(email=email, password=password, role=role, first_name=label)
                created_accounts.append((email, password))
            elif user.role_id != role.pk:
                raise CommandError(f'La cuenta {email} ya existe con otro rol; no se modificó.')
            accounts[name] = user
            if name != 'superadmin':
                Membership.objects.get_or_create(organization=org, user=user, defaults={'role': role})
        if created_accounts:
            # Append credentials only for new local accounts; never reset passwords.
            descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
            with os.fdopen(descriptor, 'a') as output:
                for email, secret in created_accounts:
                    output.write(f'{email}\t{secret}\n')
        country, _ = Country.objects.get_or_create(code='DE', defaults={'name': 'Alemania'})
        buyer, _ = Client.objects.get_or_create(email='comprador@roles.ritech.test', defaults={'organization': org, 'user': accounts['importador'], 'business_name': 'Importadora demo', 'country': country})
        producer, _ = Producer.objects.get_or_create(organization=org, identification='DEMO-PRODUCTOR', defaults={'name': 'Productor demo', 'user': accounts['productor']})
        Farm.objects.get_or_create(organization=org, code='DEMO-FINCA', defaults={'name': 'Finca de demostración', 'producer': producer, 'area': 12})
        lot, _ = ProductLot.objects.get_or_create(organization=org, code='DEMO-CAFE-01', defaults={'producer': producer, 'product_type': 'cafe', 'quantity_initial': 1000, 'quantity_available': 1000, 'unit': 'kg', 'variety': 'Castillo'})
        Product.objects.get_or_create(organization=org, name='Café demo', defaults={'product_type': 'cafe', 'quantity': 1000, 'unit': 'kg'})
        export, _ = ExportOperation.objects.get_or_create(organization=org, code='DEMO-EXP-01', defaults={'importer': buyer, 'destination_country': 'Alemania', 'destination_place': 'Hamburgo', 'incoterm': 'FOB', 'commercial_value': 2500, 'responsible': accounts['exportaciones'], 'estimated_departure': timezone.localdate() + timedelta(days=7)})
        allocation, allocation_created = ExportLotAllocation.objects.get_or_create(organization=org, export=export, lot=lot, defaults={'quantity': 100, 'unit': 'kg'})
        if allocation_created:
            from django.db.models import F
            ProductLot.objects.filter(pk=lot.pk).update(quantity_available=F('quantity_available') - 100)
            from operations.models import InventoryMovement
            InventoryMovement.objects.create(organization=org, lot=lot, movement_type='reserva', quantity=100, reference=export.code, actor=accounts['exportaciones'])
        m.Requirement.objects.get_or_create(organization=org, document_type='origen', name='Certificado de origen demo', defaults={'mandatory': True})
        vehicle, _ = m.Vehicle.objects.get_or_create(organization=org, plate='DEMO-001', defaults={'operator': accounts['logistica'], 'description': 'Camión demo'})
        driver, _ = m.Driver.objects.get_or_create(organization=org, license_number='DEMO-LICENCIA', defaults={'name': 'Conductor demo', 'operator': accounts['logistica'], 'license_expires_on': timezone.localdate() + timedelta(days=365)})
        m.Transport.objects.get_or_create(organization=org, export=export, assigned_to=accounts['logistica'], defaults={'vehicle': vehicle, 'driver': driver, 'pickup_place': 'Finca de demostración', 'delivery_place': 'Puerto de Cartagena', 'scheduled_pickup': timezone.now() + timedelta(days=3)})
        m.Order.objects.get_or_create(organization=org, export=export, reference='DEMO-PEDIDO-01', defaults={'description': 'Café Castillo', 'quantity': 100, 'unit': 'kg'})
        m.Activity.objects.get_or_create(organization=org, export=export, title='Preparar expediente documental', defaults={'assigned_to': accounts['documental'], 'due_at': timezone.now() + timedelta(days=2)})
        m.Document.objects.get_or_create(organization=org, title='Certificado de origen demo', export=export, defaults={'owner': accounts['productor'], 'producer': producer, 'document_type': 'origen'})
        m.Supplier.objects.get_or_create(organization=org, identification='DEMO-TRANSPORTADOR', defaults={'name': 'Transportadora demo'})
        for kind, category, amount in [('costo', 'logistica', 300), ('ingreso', 'venta', 2500), ('presupuesto', 'logistica', 400)]:
            m.FinanceEntry.objects.get_or_create(organization=org, export=export, description='Demo ' + kind, defaults={'kind': kind, 'category': category, 'amount': amount, 'base_amount': amount, 'actor': accounts['financiero']})
        for role, user in accounts.items():
            if role != 'superadmin':
                m.Notification.objects.get_or_create(organization=org, recipient=user, title='Bienvenido al laboratorio de roles', defaults={'message': 'Explora tu panel y los módulos autorizados. Los datos demo están separados de las otras empresas.'})
        self.stdout.write(self.style.SUCCESS(f'Laboratorio listo. {len(created_accounts)} cuentas creadas. Credenciales locales: {path}'))
        if not created_accounts and not existing:
            self.stdout.write('Las cuentas ya existían; conserva sus contraseñas actuales.')
