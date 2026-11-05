from decimal import Decimal
from django.conf import settings
from django.core.validators import MinValueValidator
from django.db import models
from operations.models import TenantModel

POSITIVE = [MinValueValidator(Decimal('0.01'))]


class Supplier(TenantModel):
    name = models.CharField(max_length=180)
    email = models.EmailField(blank=True)
    identification = models.CharField(max_length=60, blank=True)
    phone = models.CharField(max_length=40, blank=True)
    is_active = models.BooleanField(default=True)


class OrganizationSetting(TenantModel):
    key = models.CharField(max_length=100)
    value = models.TextField()
    class Meta:
        constraints = [models.UniqueConstraint(fields=['organization', 'key'], name='unique_org_setting')]


class Requirement(TenantModel):
    name = models.CharField(max_length=150)
    document_type = models.CharField(max_length=60)
    destination_country = models.CharField(max_length=100, blank=True)
    mandatory = models.BooleanField(default=True)
    is_active = models.BooleanField(default=True)


class Document(TenantModel):
    title = models.CharField(max_length=180)
    document_type = models.CharField(max_length=60)
    export = models.ForeignKey('operations.ExportOperation', null=True, blank=True, on_delete=models.PROTECT, related_name='documents')
    producer = models.ForeignKey('operations.Producer', null=True, blank=True, on_delete=models.PROTECT, related_name='documents')
    owner = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name='owned_documents')
    shared_with_client = models.BooleanField(default=False)
    issued_on = models.DateField(null=True, blank=True)
    expires_on = models.DateField(null=True, blank=True)
    status = models.CharField(max_length=20, choices=[('borrador', 'Borrador'), ('pendiente', 'Pendiente'), ('aprobado', 'Aprobado'), ('rechazado', 'Rechazado'), ('correcciones', 'Correcciones')], default='borrador')
    review_notes = models.TextField(blank=True)
    reviewer = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, on_delete=models.PROTECT, related_name='reviewed_documents')
    reviewed_at = models.DateTimeField(null=True)


class DocumentVersion(models.Model):
    document = models.ForeignKey(Document, on_delete=models.PROTECT, related_name='versions')
    number = models.PositiveIntegerField()
    file = models.FileField(upload_to='documents/%Y/%m/')
    filename = models.CharField(max_length=200)
    sha256 = models.CharField(max_length=64)
    uploaded_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT)
    created_at = models.DateTimeField(auto_now_add=True)
    class Meta:
        constraints = [models.UniqueConstraint(fields=['document', 'number'], name='unique_document_version')]
        ordering = ['-number']


class ChecklistItem(TenantModel):
    export = models.ForeignKey('operations.ExportOperation', on_delete=models.PROTECT, related_name='checklist')
    requirement = models.ForeignKey(Requirement, on_delete=models.PROTECT)
    passed = models.BooleanField(default=False)
    notes = models.TextField(blank=True)
    evaluated_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT)
    class Meta:
        constraints = [models.UniqueConstraint(fields=['export', 'requirement'], name='unique_export_requirement')]


class ComplianceEvaluation(TenantModel):
    export = models.ForeignKey('operations.ExportOperation', on_delete=models.PROTECT, related_name='evaluations')
    result = models.CharField(max_length=20, choices=[('conforme', 'Conforme'), ('no_conforme', 'No conforme')])
    notes = models.TextField()
    evaluator = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT)


class Vehicle(TenantModel):
    plate = models.CharField(max_length=30)
    description = models.CharField(max_length=180, blank=True)
    operator = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT)
    is_active = models.BooleanField(default=True)
    class Meta:
        constraints = [models.UniqueConstraint(fields=['organization', 'plate'], name='unique_vehicle_plate')]


class Driver(TenantModel):
    name = models.CharField(max_length=150)
    license_number = models.CharField(max_length=60)
    license_expires_on = models.DateField()
    operator = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT)
    is_active = models.BooleanField(default=True)


class Transport(TenantModel):
    export = models.ForeignKey('operations.ExportOperation', on_delete=models.PROTECT, related_name='transports')
    assigned_to = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name='assigned_transports')
    vehicle = models.ForeignKey(Vehicle, null=True, blank=True, on_delete=models.PROTECT)
    driver = models.ForeignKey(Driver, null=True, blank=True, on_delete=models.PROTECT)
    pickup_place = models.CharField(max_length=180)
    delivery_place = models.CharField(max_length=180)
    scheduled_pickup = models.DateTimeField()
    scheduled_delivery = models.DateTimeField(null=True, blank=True)
    actual_pickup = models.DateTimeField(null=True, blank=True)
    actual_delivery = models.DateTimeField(null=True, blank=True)
    waybill = models.CharField(max_length=120, blank=True)
    status = models.CharField(max_length=20, choices=[('asignado', 'Asignado'), ('recogido', 'Recogido'), ('en_transito', 'En tránsito'), ('entregado', 'Entregado')], default='asignado')


class TransportEvent(TenantModel):
    transport = models.ForeignKey(Transport, on_delete=models.PROTECT, related_name='events')
    event_type = models.CharField(max_length=30, choices=[('recogida', 'Recogida'), ('inicio', 'Inicio del trayecto'), ('seguimiento', 'Seguimiento'), ('incidencia', 'Incidencia'), ('entrega', 'Entrega')])
    event_at = models.DateTimeField()
    notes = models.TextField(blank=True)
    evidence = models.ForeignKey(Document, null=True, blank=True, on_delete=models.PROTECT)
    actor = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT)


class ExchangeRate(TenantModel):
    base_currency = models.CharField(max_length=3)
    target_currency = models.CharField(max_length=3)
    rate = models.DecimalField(max_digits=20, decimal_places=8, validators=[MinValueValidator(Decimal('0.00000001'))])
    rate_date = models.DateField()
    source = models.CharField(max_length=180)


class Quote(TenantModel):
    export = models.ForeignKey('operations.ExportOperation', on_delete=models.PROTECT, related_name='quotes')
    supplier = models.ForeignKey(Supplier, on_delete=models.PROTECT)
    description = models.CharField(max_length=180)
    amount = models.DecimalField(max_digits=18, decimal_places=2, validators=POSITIVE)
    currency = models.CharField(max_length=3, default='EUR')
    valid_until = models.DateField()
    selected = models.BooleanField(default=False)


class FinanceEntry(TenantModel):
    export = models.ForeignKey('operations.ExportOperation', on_delete=models.PROTECT, related_name='finance_entries')
    kind = models.CharField(max_length=20, choices=[('costo', 'Costo'), ('ingreso', 'Ingreso'), ('presupuesto', 'Presupuesto')])
    category = models.CharField(max_length=30, choices=[('logistica', 'Logística'), ('seguro', 'Seguro'), ('producto', 'Producto'), ('aduana', 'Aduana'), ('venta', 'Venta'), ('otros', 'Otros')])
    description = models.CharField(max_length=180)
    counterparty = models.CharField(max_length=180, blank=True)
    amount = models.DecimalField(max_digits=18, decimal_places=2, validators=POSITIVE)
    currency = models.CharField(max_length=3, default='EUR')
    exchange_rate = models.ForeignKey(ExchangeRate, null=True, blank=True, on_delete=models.PROTECT)
    base_amount = models.DecimalField(max_digits=22, decimal_places=2)
    base_currency = models.CharField(max_length=3, default='EUR')
    due_date = models.DateField(null=True, blank=True)
    payment_status = models.CharField(max_length=20, choices=[('pendiente', 'Pendiente'), ('parcial', 'Parcial'), ('pagado', 'Pagado')], default='pendiente')
    paid_amount = models.DecimalField(max_digits=18, decimal_places=2, default=0, validators=[MinValueValidator(0)])
    actor = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT)


class Activity(TenantModel):
    export = models.ForeignKey('operations.ExportOperation', on_delete=models.PROTECT, related_name='activities')
    title = models.CharField(max_length=180)
    assigned_to = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT)
    due_at = models.DateTimeField()
    completed = models.BooleanField(default=False)
    notes = models.TextField(blank=True)


class Incident(TenantModel):
    export = models.ForeignKey('operations.ExportOperation', on_delete=models.PROTECT, related_name='incidents')
    transport = models.ForeignKey(Transport, null=True, blank=True, on_delete=models.PROTECT)
    title = models.CharField(max_length=180)
    description = models.TextField()
    severity = models.CharField(max_length=20, choices=[('baja', 'Baja'), ('media', 'Media'), ('alta', 'Alta')], default='media')
    status = models.CharField(max_length=20, choices=[('abierta', 'Abierta'), ('en_proceso', 'En proceso'), ('resuelta', 'Resuelta')], default='abierta')
    resolution = models.TextField(blank=True)
    reported_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT)


class Approval(TenantModel):
    export = models.ForeignKey('operations.ExportOperation', on_delete=models.PROTECT, related_name='approvals')
    title = models.CharField(max_length=180)
    reason = models.TextField()
    requested_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name='requested_approvals')
    status = models.CharField(max_length=20, choices=[('pendiente', 'Pendiente'), ('aprobada', 'Aprobada'), ('rechazada', 'Rechazada')], default='pendiente')
    decided_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, on_delete=models.PROTECT, related_name='decided_approvals')
    decision_notes = models.TextField(blank=True)


class Order(TenantModel):
    export = models.ForeignKey('operations.ExportOperation', on_delete=models.PROTECT, related_name='orders')
    reference = models.CharField(max_length=100)
    description = models.TextField()
    quantity = models.DecimalField(max_digits=14, decimal_places=3, validators=POSITIVE)
    unit = models.CharField(max_length=20, choices=[('kg', 'kg'), ('tonelada', 'Tonelada')], default='kg')
    received_at = models.DateTimeField(null=True)
    reception_notes = models.TextField(blank=True)
    received_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, on_delete=models.PROTECT)


class Notification(TenantModel):
    recipient = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    title = models.CharField(max_length=180)
    message = models.TextField()
    read = models.BooleanField(default=False)


class PlatformSetting(models.Model):
    key = models.CharField(max_length=100, unique=True)
    value = models.TextField()
    enabled = models.BooleanField(default=True)


class TechnicalIncident(models.Model):
    title = models.CharField(max_length=180)
    description = models.TextField()
    status = models.CharField(max_length=20, choices=[('abierto', 'Abierto'), ('investigando', 'Investigando'), ('resuelto', 'Resuelto')], default='abierto')
    created_at = models.DateTimeField(auto_now_add=True)
