import uuid
from decimal import Decimal

from django.conf import settings
from django.core.validators import MinValueValidator
from django.db import models

from users.models import Organization


class TenantModel(models.Model):
    organization = models.ForeignKey(Organization, on_delete=models.PROTECT, related_name="%(class)ss")
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        abstract = True


class Producer(TenantModel):
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT, null=True, blank=True, related_name="producer_profiles")
    name = models.CharField(max_length=180)
    identification = models.CharField(max_length=60, blank=True)
    email = models.EmailField(blank=True)
    phone = models.CharField(max_length=40, blank=True)
    location = models.CharField(max_length=180, blank=True)
    is_active = models.BooleanField(default=True)

    class Meta:
        ordering = ["name"]
        constraints = [models.UniqueConstraint(fields=["organization", "identification"], condition=~models.Q(identification=""), name="unique_producer_identification_per_org")]

    def __str__(self):
        return self.name


class Farm(TenantModel):
    producer = models.ForeignKey(Producer, on_delete=models.PROTECT, related_name="farms")
    code = models.CharField(max_length=40)
    name = models.CharField(max_length=180)
    department = models.CharField(max_length=100, blank=True)
    municipality = models.CharField(max_length=100, blank=True)
    area = models.DecimalField(max_digits=12, decimal_places=3, validators=[MinValueValidator(Decimal("0"))])
    area_unit = models.CharField(max_length=20, default="hectarea")
    crops = models.JSONField(default=list, blank=True)
    support_documents = models.JSONField(default=list, blank=True)
    is_active = models.BooleanField(default=True)

    class Meta:
        ordering = ["name"]
        constraints = [models.UniqueConstraint(fields=["organization", "code"], name="unique_farm_code_per_org")]


class Crop(TenantModel):
    farm = models.ForeignKey(Farm, on_delete=models.CASCADE, related_name="registered_crops")
    name = models.CharField(max_length=120)
    product_type = models.CharField(max_length=20, choices=[("cafe", "Cafe"), ("cacao", "Cacao")])
    variety = models.CharField(max_length=100, blank=True)
    planted_area = models.DecimalField(max_digits=12, decimal_places=3, validators=[MinValueValidator(Decimal("0"))])
    planted_on = models.DateField(null=True, blank=True)
    is_active = models.BooleanField(default=True)

    class Meta:
        ordering = ["name"]


class Plot(TenantModel):
    farm = models.ForeignKey(Farm, on_delete=models.PROTECT, related_name="plots")
    crop = models.ForeignKey(Crop, on_delete=models.PROTECT, null=True, blank=True, related_name="plots")
    code = models.CharField(max_length=40)
    name = models.CharField(max_length=120, blank=True)
    geometry = models.JSONField(help_text="GeoJSON Point, Polygon or MultiPolygon")
    area = models.DecimalField(max_digits=12, decimal_places=3, validators=[MinValueValidator(Decimal("0"))])
    crop_type = models.CharField(max_length=20, choices=[("cafe", "Cafe"), ("cacao", "Cacao")])
    evidence = models.JSONField(default=list, blank=True)
    is_active = models.BooleanField(default=True)

    class Meta:
        ordering = ["code"]
        constraints = [models.UniqueConstraint(fields=["farm", "code"], name="unique_plot_code_per_farm")]


class Harvest(TenantModel):
    plot = models.ForeignKey(Plot, on_delete=models.PROTECT, related_name="harvests")
    harvest_date = models.DateField()
    product_type = models.CharField(max_length=20, choices=[("cafe", "Cafe"), ("cacao", "Cacao")])
    quantity = models.DecimalField(max_digits=14, decimal_places=3, validators=[MinValueValidator(Decimal("0.001"))])
    unit = models.CharField(max_length=20, choices=[("kg", "kg"), ("tonelada", "tonelada")], default="kg")
    notes = models.TextField(blank=True)

    class Meta:
        ordering = ["-harvest_date", "-id"]


class Certification(TenantModel):
    producer = models.ForeignKey(Producer, on_delete=models.CASCADE, related_name="certifications")
    name = models.CharField(max_length=120)
    issuer = models.CharField(max_length=180, blank=True)
    certificate_code = models.CharField(max_length=100, blank=True)
    issued_on = models.DateField(null=True, blank=True)
    expires_on = models.DateField(null=True, blank=True)
    evidence = models.JSONField(default=list, blank=True)


class ProductLot(TenantModel):
    code = models.CharField(max_length=50)
    public_id = models.UUIDField(default=uuid.uuid4, unique=True, editable=False)
    product_type = models.CharField(max_length=20, choices=[("cafe", "Cafe"), ("cacao", "Cacao")])
    producer = models.ForeignKey(Producer, on_delete=models.PROTECT, related_name="lots")
    harvest = models.ForeignKey(Harvest, on_delete=models.PROTECT, null=True, blank=True, related_name="lots")
    variety = models.CharField(max_length=100, blank=True)
    presentation = models.CharField(max_length=100, blank=True)
    processing = models.CharField(max_length=100, blank=True)
    fermentation = models.CharField(max_length=100, blank=True)
    drying = models.CharField(max_length=100, blank=True)
    humidity_percent = models.DecimalField(max_digits=5, decimal_places=2, null=True, blank=True, validators=[MinValueValidator(Decimal("0"))])
    classification = models.CharField(max_length=100, blank=True)
    quality_results = models.JSONField(default=dict, blank=True)
    quantity_initial = models.DecimalField(max_digits=14, decimal_places=3, validators=[MinValueValidator(Decimal("0"))])
    quantity_available = models.DecimalField(max_digits=14, decimal_places=3, validators=[MinValueValidator(Decimal("0"))])
    unit = models.CharField(max_length=20, choices=[("kg", "kg"), ("tonelada", "tonelada")], default="kg")
    is_active = models.BooleanField(default=True)

    class Meta:
        ordering = ["code"]
        constraints = [models.UniqueConstraint(fields=["organization", "code"], name="unique_lot_code_per_org")]


class LotRelationship(TenantModel):
    DERIVED = "derivado"
    MIXED = "mezcla"
    TRANSFORMED = "transformacion"
    RELATION_TYPES = [(DERIVED, "Derivado"), (MIXED, "Mezcla"), (TRANSFORMED, "Transformacion")]
    source_lot = models.ForeignKey(ProductLot, on_delete=models.PROTECT, related_name="derived_relations")
    target_lot = models.ForeignKey(ProductLot, on_delete=models.PROTECT, related_name="source_relations")
    relation_type = models.CharField(max_length=20, choices=RELATION_TYPES)
    quantity = models.DecimalField(max_digits=14, decimal_places=3, validators=[MinValueValidator(Decimal("0.001"))])
    output_quantity = models.DecimalField(max_digits=14, decimal_places=3, validators=[MinValueValidator(Decimal("0.001"))], default=Decimal("0"))
    notes = models.TextField(blank=True)
    actor = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT)

    class Meta:
        constraints = [models.UniqueConstraint(fields=["source_lot", "target_lot"], name="unique_lot_relationship")]


class InventoryMovement(TenantModel):
    RECEIPT = "entrada"
    ISSUE = "salida"
    RESERVE = "reserva"
    RELEASE = "liberacion"
    ADJUSTMENT = "ajuste"
    TYPES = [(RECEIPT, "Entrada"), (ISSUE, "Salida"), (RESERVE, "Reserva"), (RELEASE, "Liberacion"), (ADJUSTMENT, "Ajuste")]

    lot = models.ForeignKey(ProductLot, on_delete=models.PROTECT, related_name="movements")
    movement_type = models.CharField(max_length=20, choices=TYPES)
    quantity = models.DecimalField(max_digits=14, decimal_places=3, validators=[MinValueValidator(Decimal("0.001"))])
    reference = models.CharField(max_length=100, blank=True)
    notes = models.TextField(blank=True)
    actor = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="inventory_movements")

    class Meta:
        ordering = ["-created_at", "-id"]


class ExportOperation(TenantModel):
    STATUSES = [
        ("borrador", "Borrador"), ("pendiente_documentacion", "Pendiente de documentacion"),
        ("en_revision", "En revision"), ("requiere_correcciones", "Requiere correcciones"),
        ("aprobada_despacho", "Aprobada para despacho"), ("preparacion_logistica", "En preparacion logistica"),
        ("transporte_terrestre", "En transporte terrestre"), ("embarcada", "Embarcada"),
        ("transito_internacional", "En transito internacional"), ("arribada", "Arribada a destino"),
        ("entregada", "Entregada"), ("cerrada", "Cerrada"), ("bloqueada", "Bloqueada"),
        ("rechazada", "Rechazada"), ("cancelada", "Cancelada"),
    ]
    code = models.CharField(max_length=40)
    importer = models.ForeignKey("catalog.Client", on_delete=models.PROTECT, related_name="export_operations")
    origin_country = models.CharField(max_length=100, default="Colombia")
    destination_country = models.CharField(max_length=100)
    destination_place = models.CharField(max_length=180, blank=True)
    incoterm = models.CharField(max_length=3, blank=True)
    incoterm_version = models.CharField(max_length=10, blank=True)
    commercial_terms = models.TextField(blank=True)
    departure_port = models.CharField(max_length=120, blank=True)
    arrival_port = models.CharField(max_length=120, blank=True)
    estimated_departure = models.DateField(null=True, blank=True)
    estimated_arrival = models.DateField(null=True, blank=True)
    actual_departure = models.DateField(null=True, blank=True)
    actual_arrival = models.DateField(null=True, blank=True)
    gross_weight = models.DecimalField(max_digits=14, decimal_places=3, null=True, blank=True, validators=[MinValueValidator(Decimal("0"))])
    net_weight = models.DecimalField(max_digits=14, decimal_places=3, null=True, blank=True, validators=[MinValueValidator(Decimal("0"))])
    commercial_value = models.DecimalField(max_digits=16, decimal_places=2, null=True, blank=True, validators=[MinValueValidator(Decimal("0"))])
    currency = models.CharField(max_length=3, default="EUR")
    status = models.CharField(max_length=30, choices=STATUSES, default="borrador")
    notes = models.TextField(blank=True)
    responsible = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="managed_exports")

    class Meta:
        ordering = ["-created_at"]
        constraints = [models.UniqueConstraint(fields=["organization", "code"], name="unique_export_code_per_org")]


class ExportLotAllocation(TenantModel):
    export = models.ForeignKey(ExportOperation, on_delete=models.PROTECT, related_name="allocations")
    lot = models.ForeignKey(ProductLot, on_delete=models.PROTECT, related_name="export_allocations")
    quantity = models.DecimalField(max_digits=14, decimal_places=3, validators=[MinValueValidator(Decimal("0.001"))])
    unit = models.CharField(max_length=20, choices=[("kg", "kg"), ("tonelada", "tonelada")], default="kg")
    reserved = models.BooleanField(default=True)

    class Meta:
        constraints = [models.UniqueConstraint(fields=["export", "lot"], name="unique_lot_allocation_per_export")]


class ExportStatusHistory(TenantModel):
    export = models.ForeignKey(ExportOperation, on_delete=models.CASCADE, related_name="status_history")
    previous_status = models.CharField(max_length=30, blank=True)
    new_status = models.CharField(max_length=30, choices=ExportOperation.STATUSES)
    actor = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT)
    notes = models.TextField(blank=True)

    class Meta:
        ordering = ["created_at", "id"]


class TraceabilityEvent(TenantModel):
    lot = models.ForeignKey(ProductLot, on_delete=models.PROTECT, related_name="traceability_events")
    export = models.ForeignKey(ExportOperation, on_delete=models.PROTECT, null=True, blank=True, related_name="traceability_events")
    event_type = models.CharField(max_length=60)
    event_at = models.DateTimeField()
    location = models.JSONField(default=dict, blank=True)
    quantity = models.DecimalField(max_digits=14, decimal_places=3, null=True, blank=True, validators=[MinValueValidator(Decimal("0"))])
    documents = models.JSONField(default=list, blank=True)
    notes = models.TextField(blank=True)
    actor = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="traceability_events")

    class Meta:
        ordering = ["event_at", "id"]
