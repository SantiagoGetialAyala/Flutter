from rest_framework import serializers
from decimal import Decimal
from uuid import uuid4
from django.db import transaction

from .models import (
    Certification, Crop, ExportLotAllocation, ExportOperation, ExportStatusHistory,
    Farm, Harvest, InventoryMovement, Plot, ProductLot, Producer,
    TraceabilityEvent, LotRelationship,
)


class TenantSerializer(serializers.ModelSerializer):
    def _same_organization(self, value, field):
        if value is None:
            return
        org_id = self.context["view"].organization_id
        if getattr(value, "organization_id", org_id) != org_id:
            raise serializers.ValidationError({field: "El recurso debe pertenecer a la organización activa."})

    def validate(self, attrs):
        attrs = super().validate(attrs)
        for field in ("producer", "farm", "crop", "plot", "harvest", "lot", "source_lot", "target_lot", "export", "importer", "user"):
            value = attrs.get(field)
            if value is not None:
                self._same_organization(value, field)
                from business.scoping import scope
                from users.models import Membership, User
                view = self.context['view']
                if isinstance(value, User):
                    if not Membership.objects.filter(organization_id=view.organization_id, user=value, is_active=True).exists():
                        raise serializers.ValidationError({field: 'El usuario debe pertenecer a esta empresa.'})
                    if view.get_membership().role.name != 'administrador':
                        raise serializers.ValidationError({field: 'Solo administración puede vincular cuentas.'})
                elif hasattr(value, 'organization_id') and not scope(type(value).objects.all(), view.get_membership(), self.context['request'].user).filter(pk=value.pk).exists():
                    raise serializers.ValidationError({field: 'No tienes acceso a este recurso.'})
        if self.instance and self.instance._meta.model_name == 'productlot' and 'quantity_initial' in attrs and attrs['quantity_initial'] != self.instance.quantity_initial:
            raise serializers.ValidationError({'quantity_initial': 'Registra un movimiento para ajustar existencias.'})
        def current(name):
            return attrs.get(name, getattr(self.instance, name, self.Meta.model._meta.get_field(name).get_default()))
        model = self.Meta.model.__name__
        if model == 'ProductLot' and current('harvest'):
            harvest = current('harvest')
            if harvest.plot.farm.producer_id != current('producer').pk or harvest.product_type != current('product_type') or harvest.unit != current('unit'):
                raise serializers.ValidationError('La cosecha debe corresponder al productor, producto y unidad del lote.')
        if model == 'Plot' and current('crop') and current('crop').farm_id != current('farm').pk:
            raise serializers.ValidationError({'crop': 'El cultivo debe pertenecer a la finca seleccionada.'})
        return attrs


class ProducerSerializer(TenantSerializer):
    def validate(self, attrs):
        attrs = super().validate(attrs)
        if self.context['view'].get_membership().role.name == 'productor':
            attrs['user'] = self.context['request'].user
        return attrs

    class Meta:
        model = Producer
        exclude = ("organization", "created_at", "updated_at")


class FarmPlotInputSerializer(serializers.Serializer):
    name = serializers.CharField(max_length=120, default='Área principal')
    area = serializers.DecimalField(max_digits=12, decimal_places=3, min_value=Decimal('0.001'))
    crop_type = serializers.ChoiceField(choices=[('cafe', 'Café'), ('cacao', 'Cacao')])
    geometry = serializers.JSONField()

    def validate_geometry(self, value):
        return PlotSerializer().validate_geometry(value)


class FarmSerializer(TenantSerializer):
    code = serializers.CharField(max_length=40, required=False)
    area_unit = serializers.ChoiceField(choices=[('hectarea', 'Hectáreas (ha)'), ('km2', 'Kilómetros cuadrados (km²)')], default='hectarea')
    new_plots = FarmPlotInputSerializer(many=True, write_only=True, required=False, max_length=100)
    plots = serializers.SerializerMethodField()

    def get_plots(self, instance):
        data = list(instance.plots.order_by('code').values('id', 'name', 'code', 'area', 'crop_type', 'geometry'))
        if self.context['view'].get_membership().role.name not in {'administrador', 'superadmin', 'productor', 'exportaciones', 'documental'}:
            for plot in data:
                plot['geometry'] = None
        return data

    def to_representation(self, instance):
        data = super().to_representation(instance)
        if self.context['view'].get_membership().role.name not in {'administrador', 'superadmin', 'productor', 'exportaciones', 'documental'}:
            data['geometry'] = None
        return data

    def validate_geometry(self, value):
        return PlotSerializer().validate_geometry(value) if value else {}

    def validate(self, attrs):
        attrs = super().validate(attrs)
        area = attrs.get('area', getattr(self.instance, 'area', Decimal(0)))
        if area <= 0:
            raise serializers.ValidationError({'area': 'Indica un área mayor que cero.'})
        unit = attrs.get('area_unit', getattr(self.instance, 'area_unit', 'hectarea'))
        area_ha = area * (100 if unit == 'km2' else 1)
        existing_area = sum(self.instance.plots.values_list('area', flat=True)) if self.instance else Decimal(0)
        if existing_area + sum(p['area'] for p in attrs.get('new_plots', [])) > area_ha:
            raise serializers.ValidationError({'new_plots': 'La suma de las parcelas no puede superar el área de la finca (1 km² = 100 ha).'})
        if attrs.get('new_plots'):
            from users.access import require
            require(self.context['view'].get_membership().role.name, 'plots', 'create')
        return attrs

    def _add_plots(self, farm, plots):
        from users.access import audit
        area_ha = farm.area * (100 if farm.area_unit == 'km2' else 1)
        if sum(farm.plots.values_list('area', flat=True)) + sum(p['area'] for p in plots) > area_ha:
            raise serializers.ValidationError({'new_plots': 'Las parcelas superan el área de la finca.'})
        for data in plots:
            plot = Plot.objects.create(organization=farm.organization, farm=farm,
                code='PAR-' + uuid4().hex[:12].upper(), **data)
            audit(self.context['request'], farm.organization, 'plot.created', plot)

    @transaction.atomic
    def create(self, validated_data):
        plots = validated_data.pop('new_plots', [])
        validated_data.setdefault('code', 'FIN-' + uuid4().hex[:12].upper())
        farm = super().create(validated_data)
        self._add_plots(farm, plots)
        return farm

    @transaction.atomic
    def update(self, instance, validated_data):
        instance = Farm.objects.select_for_update().get(pk=instance.pk)
        plots = validated_data.pop('new_plots', [])
        farm = super().update(instance, validated_data)
        self._add_plots(farm, plots)
        return farm

    class Meta:
        model = Farm
        exclude = ("organization", "created_at", "updated_at")


class CropSerializer(TenantSerializer):
    class Meta:
        model = Crop
        exclude = ("organization", "created_at", "updated_at")


class PlotSerializer(TenantSerializer):
    geometry = serializers.JSONField()
    code = serializers.CharField(max_length=40, required=False)
    farm_name = serializers.CharField(source='farm.name', read_only=True)

    def validate(self, attrs):
        attrs = super().validate(attrs)
        farm = attrs.get('farm', getattr(self.instance, 'farm', None))
        area = attrs.get('area', getattr(self.instance, 'area', Decimal(0)))
        if farm is not None:
            others = farm.plots.exclude(pk=getattr(self.instance, 'pk', None))
            if area <= 0 or sum(others.values_list('area', flat=True)) + area > farm.area * (100 if farm.area_unit == 'km2' else 1):
                raise serializers.ValidationError({'area': 'El área debe ser positiva y la suma de parcelas no puede superar el área de la finca, en hectáreas.'})
        return attrs

    @transaction.atomic
    def create(self, validated_data):
        Farm.objects.select_for_update().get(pk=validated_data['farm'].pk)
        self.validate(validated_data)
        validated_data.setdefault('code', 'PAR-' + uuid4().hex[:12].upper())
        return super().create(validated_data)

    @transaction.atomic
    def update(self, instance, validated_data):
        farm = validated_data.get('farm', instance.farm)
        Farm.objects.select_for_update().get(pk=farm.pk)
        self.validate(validated_data)
        return super().update(instance, validated_data)

    class Meta:
        model = Plot
        exclude = ("organization", "created_at", "updated_at")

    def validate_geometry(self, value):
        if not isinstance(value, dict) or value.get("type") not in {"Point", "Polygon", "MultiPolygon"}:
            raise serializers.ValidationError("Usa GeoJSON Point, Polygon o MultiPolygon.")
        coordinates = value.get("coordinates")
        if coordinates is None:
            raise serializers.ValidationError("GeoJSON requiere coordinates.")

        def check_position(position):
            if isinstance(position, (list, tuple)) and len(position) >= 2 and all(isinstance(n, (int, float)) for n in position[:2]):
                lon, lat = position[:2]
                return -180 <= lon <= 180 and -90 <= lat <= 90
            if isinstance(position, (list, tuple)) and position:
                return all(check_position(item) for item in position)
            return False

        if not check_position(coordinates):
            raise serializers.ValidationError("Coordenadas fuera de rango o GeoJSON inválido.")
        if value["type"] in {"Polygon", "MultiPolygon"} and not _closed_rings(value["type"], coordinates):
            raise serializers.ValidationError("Cada anillo del polígono debe cerrar en su punto inicial y tener al menos 4 puntos.")
        return value

    def to_representation(self, instance):
        data = super().to_representation(instance)
        membership = self.context["view"].get_membership()
        if membership.role.name not in {"administrador", "superadmin", "productor", "exportaciones", "documental"}:
            data["geometry"] = None
        return data


def _closed_rings(geometry_type, coordinates):
    polygons = [coordinates] if geometry_type == "Polygon" else coordinates
    if not isinstance(polygons, list) or not polygons:
        return False
    for polygon in polygons:
        if not isinstance(polygon, list) or not polygon:
            return False
        for ring in polygon:
            if not isinstance(ring, list) or len(ring) < 4 or ring[0] != ring[-1]:
                return False
    return True


class HarvestSerializer(TenantSerializer):
    farm_name = serializers.CharField(source='plot.farm.name', read_only=True)
    plot_name = serializers.CharField(source='plot.name', read_only=True)

    class Meta:
        model = Harvest
        exclude = ("organization", "created_at", "updated_at")


class CertificationSerializer(TenantSerializer):
    class Meta:
        model = Certification
        exclude = ("organization", "created_at", "updated_at")


class ProductLotSerializer(TenantSerializer):
    class Meta:
        model = ProductLot
        exclude = ("organization", "created_at", "updated_at")
        read_only_fields = ("public_id", "quantity_available")


class LotRelationshipSerializer(TenantSerializer):
    actor = serializers.StringRelatedField(read_only=True)

    class Meta:
        model = LotRelationship
        exclude = ("organization", "updated_at")
        read_only_fields = ("actor", "created_at")

    def validate(self, attrs):
        attrs = super().validate(attrs)
        source = attrs.get("source_lot")
        target = attrs.get("target_lot")
        if source and target:
            if source.pk == target.pk:
                raise serializers.ValidationError("Un lote no puede derivarse de sí mismo.")
            if source.product_type != target.product_type:
                raise serializers.ValidationError("Los lotes relacionados deben ser del mismo producto.")
            if source.unit != target.unit:
                raise serializers.ValidationError({"target_lot": "Los lotes relacionados deben usar la misma unidad."})
            organization_id = self.context["view"].organization_id
            edges = list(LotRelationship.objects.filter(organization_id=organization_id).values_list("source_lot_id", "target_lot_id"))
            graph = {}
            for parent, child in edges:
                graph.setdefault(parent, set()).add(child)
            pending = [target.pk]
            visited = set()
            while pending:
                node = pending.pop()
                if node == source.pk:
                    raise serializers.ValidationError("La relación crearía un ciclo de trazabilidad.")
                if node not in visited:
                    visited.add(node)
                    pending.extend(graph.get(node, ()))
        return attrs


class InventoryMovementSerializer(TenantSerializer):
    actor = serializers.StringRelatedField(read_only=True)

    class Meta:
        model = InventoryMovement
        exclude = ("organization", "updated_at")
        read_only_fields = ("actor", "created_at")


class ExportSerializer(TenantSerializer):
    status_display = serializers.CharField(source="get_status_display", read_only=True)
    importer_name = serializers.CharField(source="importer.business_name", read_only=True)
    allocations = serializers.SerializerMethodField()
    allowed_transitions = serializers.SerializerMethodField()

    class Meta:
        model = ExportOperation
        exclude = ("organization", "updated_at")
        read_only_fields = ("status", "responsible", "created_at")

    def get_allowed_transitions(self, obj):
        from .workflow import allowed_transitions
        role = self.context['view'].get_membership().role.name
        if '_export_transition_grants' not in self.context:
            from users.access import permissions
            self.context['_export_transition_grants'] = permissions(role).get('exports', [])
        return allowed_transitions(obj.status, role, self.context['_export_transition_grants'])

    def get_allocations(self, obj):
        return [
            {"lot_id": item.lot_id, "lot_code": item.lot.code, "quantity": str(item.quantity), "unit": item.unit}
            for item in obj.allocations.all()
        ]

    def to_representation(self, instance):
        data = super().to_representation(instance)
        role = self.context["view"].get_membership().role.name
        if role not in {"administrador", "superadmin", "exportaciones", "comercial", "financiero", "gerencia"}:
            data.pop("commercial_value", None)
            data.pop("currency", None)
            data.pop("commercial_terms", None)
            data.pop("notes", None)
        return data


class AllocationSerializer(TenantSerializer):
    class Meta:
        model = ExportLotAllocation
        exclude = ("organization", "updated_at")
        read_only_fields = ("reserved", "created_at")


class ExportStatusHistorySerializer(serializers.ModelSerializer):
    actor = serializers.StringRelatedField(read_only=True)

    class Meta:
        model = ExportStatusHistory
        fields = ("id", "previous_status", "new_status", "actor", "notes", "created_at")


class TraceabilityEventSerializer(TenantSerializer):
    actor = serializers.StringRelatedField(read_only=True)

    class Meta:
        model = TraceabilityEvent
        exclude = ("organization", "updated_at")
        read_only_fields = ("actor", "created_at")
