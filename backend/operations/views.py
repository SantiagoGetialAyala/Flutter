from django.db import transaction
from django.db.models import F
from django.shortcuts import get_object_or_404
from rest_framework import status, viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import PermissionDenied, ValidationError
from rest_framework.response import Response

from users.models import AuditEvent, Membership, Role
from .models import (
    Certification, Crop, ExportLotAllocation, ExportOperation, ExportStatusHistory,
    Farm, Harvest, InventoryMovement, LotRelationship, Plot, ProductLot, Producer,
    TraceabilityEvent,
)
from .serializers import (
    AllocationSerializer, CertificationSerializer, CropSerializer, ExportSerializer,
    ExportStatusHistorySerializer, FarmSerializer, HarvestSerializer,
    InventoryMovementSerializer, LotRelationshipSerializer, PlotSerializer, ProductLotSerializer,
    ProducerSerializer, TraceabilityEventSerializer,
)


class OrganizationScopedViewSet(viewsets.ModelViewSet):
    organization = None
    organization_id = None

    def get_membership(self):
        if not hasattr(self, '_membership'):
            from users.access import membership_for
            self._membership = membership_for(self.request, exceptional=True)
            self.organization = self._membership.organization
            self.organization_id = self.organization.pk
        return self._membership

    def check_permissions(self, request):
        super().check_permissions(request)
        from users.access import action_for, require
        membership = self.get_membership()
        module = getattr(self, 'module', self.request.path.split('/')[2])
        action_name = action_for(self, request)
        if self.action == 'transition':
            target = request.data.get('status')
            action_name = 'approve' if target == 'aprobada_despacho' else 'reject' if target in {'rechazada', 'requiere_correcciones', 'bloqueada'} else 'submit'
        require(membership.role.name, module, action_name)

    def get_queryset(self):
        from business.scoping import scope
        queryset = scope(super().get_queryset(), self.get_membership(), self.request.user)
        # Filter inside the already scoped queryset; never widen tenant/owner access.
        from rest_framework import serializers
        fields = {field.name for field in queryset.model._meta.fields}
        for name in ('export', 'lot', 'farm', 'plot', 'transport'):
            value = self.request.query_params.get(name)
            if name in fields and value:
                related_id = serializers.IntegerField(min_value=1).run_validation(value)
                queryset = queryset.filter(**{name + '_id': related_id})
        return queryset if queryset.ordered else queryset.order_by("pk")

    @transaction.atomic
    def perform_update(self, serializer):
        from users.access import audit
        obj = serializer.save(organization=self.organization)
        audit(self.request, self.organization, f'{obj._meta.model_name}.updated', obj)

    @transaction.atomic
    def perform_create(self, serializer):
        obj = serializer.save(organization=self.organization)
        AuditEvent.objects.create(
            organization=self.organization, actor=self.request.user,
            action=f"{obj._meta.model_name}.created", resource_type=obj._meta.model_name,
            resource_id=str(obj.pk),
        )

    def perform_destroy(self, instance):
        raise PermissionDenied("Este registro se conserva para trazabilidad; desactívalo o cambia su estado.")


class ProducerViewSet(OrganizationScopedViewSet):
    queryset = Producer.objects.all()
    serializer_class = ProducerSerializer
    search_fields = ("name", "identification", "email", "location")
    ordering_fields = ("name", "created_at")


class FarmViewSet(OrganizationScopedViewSet):
    queryset = Farm.objects.select_related("producer")
    serializer_class = FarmSerializer
    search_fields = ("code", "name", "department", "municipality")
    ordering_fields = ("name", "code", "area", "created_at")


class CropViewSet(OrganizationScopedViewSet):
    queryset = Crop.objects.select_related("farm")
    serializer_class = CropSerializer
    search_fields = ("name", "variety", "product_type")
    ordering_fields = ("name", "product_type", "planted_on")


class PlotViewSet(OrganizationScopedViewSet):
    queryset = Plot.objects.select_related("farm", "farm__producer", "crop")
    serializer_class = PlotSerializer
    search_fields = ("code", "name", "crop_type")
    ordering_fields = ("code", "area", "created_at")


class HarvestViewSet(OrganizationScopedViewSet):
    queryset = Harvest.objects.select_related("plot", "plot__farm", "plot__farm__producer")
    serializer_class = HarvestSerializer
    search_fields = ("notes", "product_type", "plot__code")
    ordering_fields = ("harvest_date", "quantity", "created_at")


class CertificationViewSet(OrganizationScopedViewSet):
    queryset = Certification.objects.select_related("producer")
    serializer_class = CertificationSerializer
    search_fields = ("name", "issuer", "certificate_code", "producer__name")
    ordering_fields = ("name", "issued_on", "expires_on", "created_at")


class ProductLotViewSet(OrganizationScopedViewSet):
    queryset = ProductLot.objects.select_related("producer", "harvest", "harvest__plot")
    serializer_class = ProductLotSerializer
    search_fields = ("code", "product_type", "variety", "classification", "producer__name")
    ordering_fields = ("code", "created_at", "quantity_available")

    @transaction.atomic
    def perform_create(self, serializer):
        lot = serializer.save(
            organization=self.organization,
            quantity_available=serializer.validated_data["quantity_initial"],
        )
        if lot.quantity_initial > 0:
            InventoryMovement.objects.create(
                organization=self.organization, lot=lot, movement_type=InventoryMovement.RECEIPT,
                quantity=lot.quantity_initial, actor=self.request.user, reference="initial-stock",
                notes="Existencia inicial del lote",
            )
        AuditEvent.objects.create(
            organization=self.organization, actor=self.request.user, action="lot.created",
            resource_type="productlot", resource_id=str(lot.pk),
        )

    @action(detail=True, methods=["get"], url_path="traceability")
    def traceability(self, request, pk=None):
        lot = self.get_object()
        events = lot.traceability_events.select_related("actor", "export")
        return Response({
            "lot": ProductLotSerializer(lot, context={"request": request, "view": self}).data,
            "origin": {
                "producer": lot.producer.name,
                "farm": lot.harvest.plot.farm.name if lot.harvest_id else None,
                "plot": lot.harvest.plot.code if lot.harvest_id else None,
                "harvest_date": lot.harvest.harvest_date if lot.harvest_id else None,
            },
            "events": TraceabilityEventSerializer(events, many=True).data,
            "exports": list(lot.export_allocations.values("export_id", "export__code", "quantity", "unit")),
            "derived_from": list(lot.source_relations.values("source_lot_id", "source_lot__code", "relation_type", "quantity")),
            "derived_into": list(lot.derived_relations.values("target_lot_id", "target_lot__code", "relation_type", "quantity")),
        })


class InventoryMovementViewSet(OrganizationScopedViewSet):
    queryset = InventoryMovement.objects.select_related("lot", "actor")
    serializer_class = InventoryMovementSerializer
    http_method_names = ["get", "post", "head", "options"]
    search_fields = ("lot__code", "movement_type", "reference", "notes")
    ordering_fields = ("created_at", "quantity", "movement_type")

    @transaction.atomic
    def perform_create(self, serializer):
        lot = get_object_or_404(ProductLot.objects.select_for_update(), pk=serializer.validated_data["lot"].pk, organization=self.organization)
        movement_type = serializer.validated_data["movement_type"]
        quantity = serializer.validated_data["quantity"]
        if movement_type in {InventoryMovement.RESERVE, InventoryMovement.RELEASE}:
            raise ValidationError({"movement_type": "Las reservas y liberaciones se generan desde la exportación para evitar duplicar existencias."})
        decrease = movement_type in {InventoryMovement.ISSUE, InventoryMovement.RESERVE}
        update = ProductLot.objects.filter(pk=lot.pk, organization=self.organization)
        if decrease:
            update = update.filter(quantity_available__gte=quantity)
            changed = update.update(quantity_available=F("quantity_available") - quantity)
        elif movement_type in {InventoryMovement.RECEIPT, InventoryMovement.RELEASE, InventoryMovement.ADJUSTMENT}:
            changed = update.update(quantity_available=F("quantity_available") + quantity)
        else:
            raise ValidationError({"movement_type": "Tipo de movimiento no soportado."})
        if changed != 1:
            raise ValidationError({"quantity": "La cantidad supera el inventario disponible."})
        movement = serializer.save(organization=self.organization, actor=self.request.user)
        AuditEvent.objects.create(organization=self.organization, actor=self.request.user, action="inventory.movement", resource_type="inventorymovement", resource_id=str(movement.pk))


class LotRelationshipViewSet(OrganizationScopedViewSet):
    queryset = LotRelationship.objects.select_related("source_lot", "target_lot", "actor")
    serializer_class = LotRelationshipSerializer
    http_method_names = ["get", "post", "head", "options"]

    @transaction.atomic
    def perform_create(self, serializer):
        source = get_object_or_404(ProductLot.objects.select_for_update(), pk=serializer.validated_data["source_lot"].pk, organization=self.organization)
        target = get_object_or_404(ProductLot.objects.select_for_update(), pk=serializer.validated_data["target_lot"].pk, organization=self.organization)
        input_quantity = serializer.validated_data["quantity"]
        output_quantity = serializer.validated_data["output_quantity"]
        if source.unit != target.unit:
            raise ValidationError({"target_lot": "Los lotes relacionados deben usar la misma unidad."})
        changed = ProductLot.objects.filter(pk=source.pk, organization=self.organization, quantity_available__gte=input_quantity).update(quantity_available=F("quantity_available") - input_quantity)
        if changed != 1:
            raise ValidationError({"quantity": "La cantidad supera la existencia disponible del lote de origen."})
        ProductLot.objects.filter(pk=target.pk, organization=self.organization).update(quantity_available=F("quantity_available") + output_quantity)
        relation = serializer.save(organization=self.organization, actor=self.request.user)
        InventoryMovement.objects.create(organization=self.organization, lot=source, movement_type=InventoryMovement.ISSUE, quantity=input_quantity, actor=self.request.user, reference=target.code, notes="Consumo en mezcla o transformación")
        InventoryMovement.objects.create(organization=self.organization, lot=target, movement_type=InventoryMovement.RECEIPT, quantity=output_quantity, actor=self.request.user, reference=source.code, notes="Producción por mezcla o transformación")
        from django.utils import timezone
        TraceabilityEvent.objects.create(organization=self.organization, lot=source, event_type="transformacion_salida", event_at=timezone.now(), quantity=input_quantity, actor=self.request.user, notes=f"Relacionado con lote {target.code}")
        TraceabilityEvent.objects.create(organization=self.organization, lot=target, event_type="transformacion_entrada", event_at=timezone.now(), quantity=output_quantity, actor=self.request.user, notes=f"Derivado de lote {source.code}")
        AuditEvent.objects.create(organization=self.organization, actor=self.request.user, action="lot.relationship_created", resource_type="lotrelationship", resource_id=str(relation.pk))


class ExportViewSet(OrganizationScopedViewSet):
    queryset = ExportOperation.objects.select_related("importer", "responsible").prefetch_related("allocations__lot")
    serializer_class = ExportSerializer
    search_fields = ("code", "destination_country", "destination_place", "importer__business_name", "status")
    ordering_fields = ("created_at", "estimated_departure", "estimated_arrival", "destination_country", "status")

    def get_queryset(self):
        queryset = super().get_queryset()
        params = self.request.query_params
        if params.get("status"):
            queryset = queryset.filter(status=params["status"])
        if params.get("destination_country"):
            queryset = queryset.filter(destination_country__iexact=params["destination_country"])
        if params.get("product_type"):
            queryset = queryset.filter(allocations__lot__product_type=params["product_type"])
        if params.get("date_from"):
            queryset = queryset.filter(created_at__date__gte=params["date_from"])
        if params.get("date_to"):
            queryset = queryset.filter(created_at__date__lte=params["date_to"])
        return queryset.distinct()

    @action(detail=True, methods=['get'], url_path='map')
    def operation_map(self, request, pk=None):
        """Only recorded geography and confirmed events, under existing grants."""
        export = self.get_object()
        from business import models as bm
        from business.scoping import scope
        from users.access import permissions
        role = self.get_membership().role.name
        grants = permissions(role)
        def rows(module, model, filters, fields):
            if 'view' not in grants.get(module, []):
                return []
            return list(scope(model.objects.all(), self.get_membership(), request.user)
                        .filter(**filters).distinct().values(*fields))
        return Response({
            'export': {'id': export.pk, 'code': export.code, 'status': export.status,
                       'origin_country': export.origin_country, 'destination_country': export.destination_country},
            'plots': rows('plots', Plot,
                {'harvests__lots__export_allocations__export': export},
                ['id', 'code', 'name', 'farm_id', 'farm__name', 'geometry']),
            'events': rows('traceability-events', TraceabilityEvent, {'export': export},
                ['id', 'event_type', 'event_at', 'location', 'notes']),
            'transports': rows('transports', bm.Transport, {'export': export},
                (['id', 'delivery_place', 'scheduled_delivery', 'actual_delivery', 'status'] if role == 'importador' else
                 ['id', 'pickup_place', 'delivery_place', 'scheduled_pickup', 'scheduled_delivery', 'status'])),
            'transport_events': rows('transport-events', bm.TransportEvent, {'transport__export': export},
                ['id', 'event_type', 'event_at', 'notes', 'transport_id']),
        })

    @transaction.atomic
    def perform_create(self, serializer):
        export = serializer.save(organization=self.organization, responsible=self.request.user, status="borrador")
        ExportStatusHistory.objects.create(organization=self.organization, export=export, previous_status="", new_status="borrador", actor=self.request.user)
        AuditEvent.objects.create(organization=self.organization, actor=self.request.user, action="export.created", resource_type="exportoperation", resource_id=str(export.pk))

    @action(detail=True, methods=['post'])
    def assign(self, request, pk=None):
        export = self.get_object()
        from rest_framework import serializers
        user_id = serializers.IntegerField(min_value=1).run_validation(request.data.get('user'))
        member = Membership.objects.filter(organization=self.organization, user_id=user_id, is_active=True, role__name__in=['administrador', 'exportaciones', 'comercial']).first()
        if not member:
            raise ValidationError({'user': 'Selecciona un coordinador activo de esta empresa.'})
        export.responsible = member.user
        export.save(update_fields=['responsible', 'updated_at'])
        from users.access import audit
        audit(request, self.organization, 'export.assigned', export, {'user': member.user_id})
        return Response(self.get_serializer(export).data)

    @action(detail=True, methods=["get"])
    def history(self, request, pk=None):
        export = self.get_object()
        return Response(ExportStatusHistorySerializer(export.status_history.select_related("actor"), many=True).data)

    @action(detail=True, methods=["post"])
    @transaction.atomic
    def transition(self, request, pk=None):
        export = get_object_or_404(ExportOperation.objects.select_for_update(), pk=pk, pk__in=self.get_queryset().values('pk'))
        next_status = request.data.get("status")
        from .workflow import TRANSITIONS
        transitions = TRANSITIONS
        if next_status not in transitions.get(export.status, set()):
            raise ValidationError({"status": f"Transición no permitida desde {export.status}."})
        role = self.get_membership().role.name
        logistics_states = {"transporte_terrestre", "embarcada", "transito_internacional", "arribada", "entregada"}
        document_states = {"en_revision", "requiere_correcciones", "aprobada_despacho", "rechazada"}
        if next_status in logistics_states and role not in {Role.ADMINISTRADOR, Role.EXPORTACIONES, Role.LOGISTICA}:
            raise PermissionDenied("Solo logística o exportaciones pueden actualizar el seguimiento del envío.")
        if next_status in document_states and role not in {Role.ADMINISTRADOR, Role.DOCUMENTAL}:
            raise PermissionDenied("Solo cumplimiento documental puede aprobar o rechazar la revisión.")
        if next_status == "bloqueada" and role not in {Role.ADMINISTRADOR, Role.DOCUMENTAL}:
            raise PermissionDenied("Solo administración o cumplimiento pueden bloquear la operación.")
        if next_status == "aprobada_despacho":
            from business.services import ensure_compliance
            ensure_compliance(export)
        if export.status == "bloqueada" and (role not in {Role.ADMINISTRADOR, Role.DOCUMENTAL} or not str(request.data.get("notes", "")).strip()):
            raise PermissionDenied("Solo administración o cumplimiento pueden desbloquear, con una justificación.")
        previous = export.status
        export.status = next_status
        export.save(update_fields=["status", "updated_at"])
        ExportStatusHistory.objects.create(organization=self.organization, export=export, previous_status=previous, new_status=next_status, actor=request.user, notes=request.data.get("notes", ""))
        if next_status == "cancelada":
            for allocation in export.allocations.select_for_update().filter(reserved=True).select_related("lot"):
                ProductLot.objects.filter(pk=allocation.lot_id).update(quantity_available=F("quantity_available") + allocation.quantity)
                InventoryMovement.objects.create(organization=self.organization, lot=allocation.lot, movement_type=InventoryMovement.RELEASE, quantity=allocation.quantity, actor=request.user, reference=export.code, notes="Liberación por cancelación de exportación")
                allocation.reserved = False
                allocation.save(update_fields=["reserved", "updated_at"])
        AuditEvent.objects.create(organization=self.organization, actor=request.user, action="export.status_changed", resource_type="exportoperation", resource_id=str(export.pk), metadata={"from": previous, "to": next_status})
        return Response(self.get_serializer(export).data)


class ExportLotAllocationViewSet(OrganizationScopedViewSet):
    queryset = ExportLotAllocation.objects.select_related("export", "lot")
    serializer_class = AllocationSerializer
    http_method_names = ["get", "post", "head", "options"]

    @transaction.atomic
    def perform_create(self, serializer):
        export = get_object_or_404(ExportOperation.objects.select_for_update(), pk=serializer.validated_data["export"].pk, organization=self.organization)
        lot = get_object_or_404(ProductLot.objects.select_for_update(), pk=serializer.validated_data["lot"].pk, organization=self.organization)
        quantity, unit = serializer.validated_data["quantity"], serializer.validated_data.get("unit", lot.unit)
        if unit != lot.unit:
            raise ValidationError({"unit": "La unidad debe coincidir con la unidad del lote."})
        if export.status not in {"borrador", "pendiente_documentacion"}:
            raise ValidationError({"export": "No se pueden cambiar lotes después de iniciar la revisión."})
        if ExportLotAllocation.objects.filter(export=export, lot=lot).exists():
            raise ValidationError({"lot": "Este lote ya está reservado para esta exportación."})
        changed = ProductLot.objects.filter(pk=lot.pk, organization=self.organization, quantity_available__gte=quantity).update(quantity_available=F("quantity_available") - quantity)
        if changed != 1:
            raise ValidationError({"quantity": "La asignación excede el inventario disponible."})
        allocation = serializer.save(organization=self.organization, reserved=True, unit=unit)
        InventoryMovement.objects.create(organization=self.organization, lot=lot, movement_type=InventoryMovement.RESERVE, quantity=quantity, actor=self.request.user, reference=export.code, notes="Reserva para exportación")
        TraceabilityEvent.objects.create(organization=self.organization, lot=lot, export=export, event_type="asignacion_exportacion", event_at=__import__("django.utils.timezone", fromlist=["now"]).now(), quantity=quantity, actor=self.request.user, notes=f"Asignado a {export.code}")
        AuditEvent.objects.create(organization=self.organization, actor=self.request.user, action="export.lot_reserved", resource_type="exportlotallocation", resource_id=str(allocation.pk))


class TraceabilityEventViewSet(OrganizationScopedViewSet):
    queryset = TraceabilityEvent.objects.select_related("lot", "export", "actor")
    serializer_class = TraceabilityEventSerializer

    def perform_create(self, serializer):
        event = serializer.save(organization=self.organization, actor=self.request.user)
        AuditEvent.objects.create(organization=self.organization, actor=self.request.user, action="traceability.event_created", resource_type="traceabilityevent", resource_id=str(event.pk))
