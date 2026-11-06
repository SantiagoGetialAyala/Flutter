from decimal import Decimal
from rest_framework import serializers
from django.utils import timezone
from users.models import Membership, User
from operations.serializers import TenantSerializer
from . import models as m
from .scoping import scope

SERVER_FIELDS = ('organization', 'created_at', 'updated_at', 'owner', 'reviewer', 'reviewed_at', 'review_notes', 'actor', 'evaluator', 'evaluated_by', 'requested_by', 'decided_by', 'decision_notes', 'reported_by', 'received_by', 'received_at', 'reception_notes', 'base_amount')


class BusinessSerializer(TenantSerializer):
    def validate(self, attrs):
        # Validate every relationship, including partial updates, on the server.
        attrs = serializers.ModelSerializer.validate(self, attrs)
        view, user = self.context['view'], self.context['request'].user
        membership = view.get_membership()
        for field, value in attrs.items():
            if isinstance(value, User):
                memberships = Membership.objects.filter(organization=membership.organization, user=value, is_active=True, role__is_active=True)
                if not memberships.exists():
                    raise serializers.ValidationError({field: 'El usuario debe ser miembro activo de la organización.'})
                if field in ('assigned_to', 'operator') and isinstance(self.Meta.model(), (m.Transport, m.Vehicle, m.Driver)) and not memberships.filter(role__name='logistica').exists():
                    raise serializers.ValidationError({field: 'Selecciona una cuenta de logística de esta organización.'})
            elif hasattr(value, 'organization_id'):
                if not scope(type(value).objects.all(), membership, user).filter(pk=value.pk).exists():
                    raise serializers.ValidationError({field: 'Recurso fuera de tu ámbito autorizado.'})
        if self.Meta.model == m.Notification and set(attrs) - {'read'}:
            raise serializers.ValidationError('Solo puedes marcar tus notificaciones como leídas o no leídas.')
        for key in ('currency', 'base_currency', 'target_currency'):
            if key in attrs:
                attrs[key] = attrs[key].upper()
                if len(attrs[key]) != 3 or not attrs[key].isalpha():
                    raise serializers.ValidationError({key: 'Usa un código de moneda de tres letras.'})
        obj = self.instance
        get = lambda key, default=None: attrs.get(key, getattr(obj, key, default))
        if isinstance(self.Meta.model(), m.Document):
            if not get('export') and not get('producer'):
                raise serializers.ValidationError('Vincula el documento con una exportación o un productor.')
            if membership.role.name == 'productor' and get('shared_with_client'):
                raise serializers.ValidationError('Solo el equipo exportador puede compartir documentos con clientes.')
            if obj and obj.status not in ('borrador', 'correcciones', 'rechazado'):
                raise serializers.ValidationError('El documento en revisión o aprobado no se puede editar. Carga una nueva versión.')
            if get('issued_on') and get('expires_on') and get('expires_on') < get('issued_on'):
                raise serializers.ValidationError('El vencimiento debe ser posterior a la emisión.')
        if isinstance(self.Meta.model(), m.Transport):
            if membership.role.name == 'logistica':
                if obj is None or any(key in attrs for key in ('assigned_to', 'export', 'pickup_place', 'delivery_place', 'scheduled_pickup', 'scheduled_delivery')):
                    raise serializers.ValidationError('El coordinador asigna las cargas y rutas. Logística registra vehículo, guía y eventos.')
            assigned = get('assigned_to')
            for field in ('vehicle', 'driver'):
                item = get(field)
                if item and (not item.is_active or item.operator_id != assigned.pk):
                    raise serializers.ValidationError({field: 'Debe estar autorizado para el transportador asignado.'})
            if get('driver') and get('driver').license_expires_on < timezone.localdate():
                raise serializers.ValidationError({'driver': 'La licencia está vencida.'})
            if get('scheduled_delivery') and get('scheduled_delivery') < get('scheduled_pickup'):
                raise serializers.ValidationError('La entrega no puede ser anterior a la recogida.')
        if isinstance(self.Meta.model(), (m.Vehicle, m.Driver)):
            if membership.role.name == 'logistica':
                attrs['operator'] = user
            elif not get('operator'):
                raise serializers.ValidationError({'operator': 'Selecciona un transportador autorizado.'})
        if isinstance(self.Meta.model(), m.Incident):
            if get('transport') and get('transport').export_id != get('export').pk:
                raise serializers.ValidationError('El transporte debe pertenecer a la exportación.')
            if get('status') == 'resuelta' and not get('resolution'):
                raise serializers.ValidationError({'resolution': 'Describe la resolución de la incidencia.'})
        if isinstance(self.Meta.model(), m.FinanceEntry):
            amount, paid = get('amount'), get('paid_amount', Decimal(0))
            if paid > amount:
                raise serializers.ValidationError({'paid_amount': 'El pago no puede superar el importe.'})
            attrs['payment_status'] = 'pagado' if paid == amount else 'parcial' if paid else 'pendiente'
            source, target, rate = get('currency', 'EUR'), get('base_currency', 'EUR'), get('exchange_rate')
            if source != target:
                if not rate or rate.base_currency != source or rate.target_currency != target:
                    raise serializers.ValidationError({'exchange_rate': 'Selecciona un tipo de cambio de la moneda original a la moneda de reporte.'})
                attrs['base_amount'] = (amount * rate.rate).quantize(Decimal('.01'))
            else:
                attrs['base_amount'] = amount
        if isinstance(self.Meta.model(), m.ExchangeRate) and get('base_currency') == get('target_currency'):
            raise serializers.ValidationError('Las monedas deben ser distintas.')
        if isinstance(self.Meta.model(), m.ComplianceEvaluation) and get('result') == 'conforme':
            # A conforming evaluation requires the current checklist and documents.
            from .services import ensure_compliance
            ensure_compliance(get('export'), require_evaluation=False)
        return attrs

    def to_representation(self, instance):
        data = super().to_representation(instance)
        if isinstance(instance, m.Document):
            data['versions'] = list(instance.versions.values('id', 'number', 'filename', 'sha256', 'created_at'))
            latest = instance.versions.first()
            user_id = self.context['request'].user.pk
            data['can_review'] = (instance.status == 'pendiente' and instance.owner_id != user_id and
                (latest is None or latest.uploaded_by_id != user_id))
            data['can_approve'] = (data['can_review'] and latest is not None and
                (instance.expires_on is None or instance.expires_on >= timezone.localdate()))
            data['can_submit'] = instance.status in ('borrador', 'correcciones', 'rechazado') and latest is not None
        if isinstance(instance, m.Order):
            data['can_confirm'] = (instance.received_at is None and
                instance.export.importer.user_id == self.context['request'].user.pk and
                instance.export.status in ('arribada', 'entregada', 'cerrada'))
        if self.context['view'].get_membership().role.name == 'importador':
            if isinstance(instance, m.Transport):
                data = {key: value for key, value in data.items() if key in ('id', 'export', 'delivery_place', 'scheduled_delivery', 'actual_delivery', 'status')}
            if isinstance(instance, m.Document):
                data = {key: value for key, value in data.items() if key in ('id', 'title', 'document_type', 'export', 'issued_on', 'expires_on', 'versions', 'status')}
        return data


def serializer_for(model):
    protected = [f.name for f in model._meta.fields if f.name in SERVER_FIELDS]
    if model in (m.Document, m.Transport, m.Approval):
        protected += ['status']
    if model == m.Transport:
        protected += ['actual_pickup', 'actual_delivery']
    if model == m.Notification:
        protected += [f.name for f in model._meta.fields if f.name != 'read']
    if model == m.FinanceEntry:
        protected += ['payment_status']
    return type(model.__name__ + 'Serializer', (BusinessSerializer,), {'Meta': type('Meta', (), {'model': model, 'exclude': ('organization',), 'read_only_fields': tuple(protected), 'extra_kwargs': {'operator': {'required': False}} if model in (m.Vehicle, m.Driver) else {}})})
