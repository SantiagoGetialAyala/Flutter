import base64
import binascii
import hashlib
from pathlib import Path
from django.core.files.base import ContentFile
from django.db import transaction
from django.db.models import Max, Sum
from django.utils import timezone
from rest_framework import viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import PermissionDenied, ValidationError
from rest_framework.response import Response
from operations.views import OrganizationScopedViewSet
from users.access import audit, require
from . import models as m
from .serializers import serializer_for


class BusinessViewSet(OrganizationScopedViewSet):
    def get_queryset(self):
        queryset = super().get_queryset()
        fields = {field.name for field in queryset.model._meta.fields}
        if 'status' in fields and self.request.query_params.get('status'):
            queryset = queryset.filter(status=self.request.query_params['status'])
        if 'export' in fields and self.request.query_params.get('export'):
            from rest_framework import serializers
            export_id = serializers.IntegerField(min_value=1).run_validation(self.request.query_params['export'])
            queryset = queryset.filter(export_id=export_id)
        return queryset

    @transaction.atomic
    def perform_create(self, serializer):
        extra = {'organization': self.organization}
        names = {f.name for f in serializer.Meta.model._meta.fields}
        for field in ('owner', 'actor', 'evaluator', 'evaluated_by', 'requested_by', 'reported_by'):
            if field in names:
                extra[field] = self.request.user
        if serializer.Meta.model == m.Incident:
            extra['status'] = 'abierta'
        obj = serializer.save(**extra)
        audit(self.request, self.organization, self.module + '.created', obj)

    @action(detail=False, methods=['get'])
    def report(self, request):
        return Response({'module': self.module, 'generated_at': timezone.now(), 'records': self.get_serializer(self.filter_queryset(self.get_queryset()), many=True).data})


class DocumentViewSet(BusinessViewSet):
    module = 'documents'
    queryset = m.Document.objects.all().order_by('-pk').prefetch_related('versions')
    serializer_class = serializer_for(m.Document)
    search_fields = ('title', 'document_type', 'status')

    @action(detail=True, methods=['post'])
    @transaction.atomic
    def upload(self, request, pk=None):
        doc = m.Document.objects.select_for_update().get(pk=self.get_object().pk, pk__in=self.get_queryset().values('pk'))
        filename = Path(str(request.data.get('filename', ''))).name
        if not filename or Path(filename).suffix.lower() not in {'.pdf', '.png', '.jpg', '.jpeg', '.webp', '.txt', '.csv', '.docx', '.xlsx'}:
            raise ValidationError('Selecciona PDF, imagen o documento de oficina válido.')
        try:
            data = base64.b64decode(request.data.get('content', ''), validate=True)
        except (binascii.Error, ValueError, TypeError):
            raise ValidationError('El contenido del archivo no es válido.')
        if not data or len(data) > 10 * 1024 * 1024:
            raise ValidationError('El archivo debe tener entre 1 byte y 10 MB.')
        version = m.DocumentVersion.objects.create(document=doc, number=(doc.versions.aggregate(n=Max('number'))['n'] or 0) + 1, filename=filename, sha256=hashlib.sha256(data).hexdigest(), uploaded_by=request.user, file=ContentFile(data, name=filename))
        doc.status, doc.reviewer, doc.reviewed_at, doc.review_notes = 'borrador', None, None, ''
        doc.save()
        # A new version invalidates the related checklist until revalidated.
        if doc.export_id:
            m.ChecklistItem.objects.filter(export=doc.export, requirement__document_type=doc.document_type).update(passed=False)
        audit(request, self.organization, 'document.version_uploaded', doc, {'version': version.number, 'sha256': version.sha256})
        return Response(self.get_serializer(doc).data)

    @action(detail=True, methods=['get'])
    def download(self, request, pk=None):
        doc = self.get_object()
        versions = doc.versions.all()
        version_id = request.query_params.get('version')
        # Clients receive only the latest approved version, never superseded files.
        if version_id and self.get_membership().role.name != 'importador':
            from rest_framework import serializers
            version_id = serializers.IntegerField(min_value=1).run_validation(version_id)
            versions = versions.filter(pk=version_id)
        version = versions.first()
        if version is None:
            raise ValidationError('No hay un archivo cargado.')
        with version.file.open('rb') as source:
            content = base64.b64encode(source.read()).decode()
        audit(request, self.organization, 'document.downloaded', doc, {'version': version.number})
        return Response({'filename': version.filename, 'content': content, 'sha256': version.sha256})

    @action(detail=True, methods=['post'])
    def submit(self, request, pk=None):
        doc = self.get_object()
        if doc.status not in ('borrador', 'correcciones', 'rechazado') or not doc.versions.exists():
            raise ValidationError('Carga una versión antes de enviarla a revisión.')
        doc.status = 'pendiente'
        doc.save()
        audit(request, self.organization, 'document.submitted', doc)
        return Response(self.get_serializer(doc).data)

    def review(self, request, approved):
        doc = m.Document.objects.select_for_update().get(pk=self.get_object().pk, pk__in=self.get_queryset().values('pk'))
        if doc.status != 'pendiente':
            raise ValidationError('Solo se revisan documentos pendientes.')
        if self.get_membership().role.name != 'administrador' and (doc.owner_id == request.user.pk or (doc.versions.first() and doc.versions.first().uploaded_by_id == request.user.pk)):
            raise PermissionDenied('Otra persona debe validar el documento que cargaste.')
        notes = str(request.data.get('notes', '')).strip()
        if not approved and not notes:
            raise ValidationError('Indica la corrección o el motivo de rechazo.')
        if approved and (not doc.versions.exists() or (doc.expires_on and doc.expires_on < timezone.localdate())):
            raise ValidationError('No se puede aprobar un documento sin archivo o vencido.')
        doc.status = 'aprobado' if approved else 'correcciones' if request.data.get('corrections') else 'rechazado'
        doc.reviewer, doc.reviewed_at, doc.review_notes = request.user, timezone.now(), notes
        doc.save()
        m.Notification.objects.create(organization=self.organization, recipient=doc.owner, title='Revisión documental: ' + doc.title, message=f'{doc.status}: {notes}')
        audit(request, self.organization, 'document.' + doc.status, doc, {'notes': notes})
        return Response(self.get_serializer(doc).data)

    @action(detail=True, methods=['post'])
    @transaction.atomic
    def approve(self, request, pk=None):
        return self.review(request, True)

    @action(detail=True, methods=['post'])
    @transaction.atomic
    def reject(self, request, pk=None):
        return self.review(request, False)


class TransportViewSet(BusinessViewSet):
    module = 'transports'
    queryset = m.Transport.objects.all().order_by("-pk")
    serializer_class = serializer_for(m.Transport)

    def perform_create(self, serializer):
        require(self.get_membership().role.name, 'transports', 'assign')
        super().perform_create(serializer)
        obj = serializer.instance
        m.Notification.objects.create(organization=self.organization, recipient=obj.assigned_to, title='Transporte asignado', message=f'Carga {obj.pk}: {obj.pickup_place} → {obj.delivery_place}')


class TransportEventViewSet(BusinessViewSet):
    module = 'transport-events'
    queryset = m.TransportEvent.objects.all().order_by("-pk")
    serializer_class = serializer_for(m.TransportEvent)
    http_method_names = ['get', 'post', 'head', 'options']

    @transaction.atomic
    def perform_create(self, serializer):
        transport = m.Transport.objects.select_for_update().get(pk=serializer.validated_data['transport'].pk)
        kind = serializer.validated_data['event_type']
        if kind in ('recogida', 'inicio', 'entrega'):
            before, after = {'recogida': ('asignado', 'recogido'), 'inicio': ('recogido', 'en_transito'), 'entrega': ('en_transito', 'entregado')}[kind]
            if transport.status != before:
                raise ValidationError(f'El evento {kind} requiere transporte en estado {before}.')
            if not serializer.validated_data.get('evidence'):
                raise ValidationError({'evidence': 'Adjunta un documento con evidencia de recogida, salida o entrega.'})
            evidence = serializer.validated_data['evidence']
            if not evidence.versions.exists() or evidence.export_id != transport.export_id:
                raise ValidationError({'evidence': 'La evidencia debe contener un archivo y corresponder a esta exportación.'})
            previous = transport.events.order_by('-event_at').first()
            if previous and serializer.validated_data['event_at'] < previous.event_at:
                raise ValidationError('La fecha no puede ser anterior al último evento.')
            transport.status = after
            if kind == 'recogida':
                transport.actual_pickup = serializer.validated_data['event_at']
            if kind == 'entrega':
                transport.actual_delivery = serializer.validated_data['event_at']
            transport.save()
        super().perform_create(serializer)
        if kind == 'incidencia':
            m.Incident.objects.create(organization=self.organization, export=transport.export, transport=transport, title='Incidencia de transporte', description=serializer.validated_data.get('notes', ''), reported_by=self.request.user)


class ApprovalViewSet(BusinessViewSet):
    module = 'approvals'
    queryset = m.Approval.objects.all().order_by("-pk")
    serializer_class = serializer_for(m.Approval)

    def perform_update(self, serializer):
        if serializer.instance.status != 'pendiente':
            raise ValidationError('Las decisiones se conservan y no pueden editarse.')
        super().perform_update(serializer)

    @transaction.atomic
    def decide(self, request, approved):
        obj = m.Approval.objects.select_for_update().get(pk=self.get_object().pk, pk__in=self.get_queryset().values('pk'))
        if obj.status != 'pendiente' or obj.requested_by_id == request.user.pk:
            raise ValidationError('La solicitud debe estar pendiente y ser revisada por otra persona.')
        notes = str(request.data.get('notes', '')).strip()
        if not notes:
            raise ValidationError('Registra la justificación de la decisión.')
        obj.status, obj.decided_by, obj.decision_notes = ('aprobada' if approved else 'rechazada'), request.user, notes
        obj.save()
        audit(request, self.organization, 'approval.' + obj.status, obj, {'notes': notes})
        m.Notification.objects.create(organization=self.organization, recipient=obj.requested_by, title=obj.title, message=f'{obj.status}: {notes}')
        return Response(self.get_serializer(obj).data)

    @action(detail=True, methods=['post'])
    def approve(self, request, pk=None):
        return self.decide(request, True)

    @action(detail=True, methods=['post'])
    def reject(self, request, pk=None):
        return self.decide(request, False)


class OrderViewSet(BusinessViewSet):
    module = 'orders'
    queryset = m.Order.objects.all().order_by("-pk")
    serializer_class = serializer_for(m.Order)

    @action(detail=True, methods=['post'])
    @transaction.atomic
    def confirm(self, request, pk=None):
        order = m.Order.objects.select_for_update().get(pk=self.get_object().pk, pk__in=self.get_queryset().values('pk'))
        if order.export.importer.user_id != request.user.pk:
            raise PermissionDenied('Solo el cliente vinculado puede confirmar la recepción.')
        if order.received_at or order.export.status not in ('arribada', 'entregada', 'cerrada'):
            raise ValidationError('El pedido debe haber arribado y no tener recepción registrada.')
        order.received_at, order.received_by = timezone.now(), request.user
        order.reception_notes = request.data.get('notes', '')
        order.save()
        audit(request, self.organization, 'order.received', order)
        return Response(self.get_serializer(order).data)


class FinanceViewSet(BusinessViewSet):
    module = 'finance'
    queryset = m.FinanceEntry.objects.all().order_by("-pk")
    serializer_class = serializer_for(m.FinanceEntry)

    @action(detail=False, methods=['get'])
    def report(self, request):
        rows = list(self.get_queryset().values('export_id', 'base_currency', 'kind').annotate(total=Sum('base_amount')))
        operations = {}
        for row in rows:
            key = (row['export_id'], row['base_currency'])
            item = operations.setdefault(key, {'export': key[0], 'currency': key[1], 'costo': 0, 'ingreso': 0, 'presupuesto': 0})
            item[row['kind']] = row['total']
        for item in operations.values():
            item['margin'] = item['ingreso'] - item['costo']
            item['budget_variance'] = item['costo'] - item['presupuesto']
            item['margin_percent'] = round(item['margin'] / item['ingreso'] * 100, 2) if item['ingreso'] else None
        audit(request, self.organization, 'finance.report_exported', self.organization)
        return Response({'operations': sorted(operations.values(), key=lambda x: x['margin'], reverse=True), 'pending_payments': self.get_queryset().exclude(payment_status='pagado').exclude(kind='presupuesto').count()})
