from django.db import connection
from django.core.exceptions import FieldDoesNotExist
from django.db.models import Sum
from django.utils import timezone
from rest_framework import serializers
from rest_framework.exceptions import PermissionDenied
from rest_framework.response import Response
from rest_framework.views import APIView
from users.access import is_platform, membership_for, permissions, require
from users.models import AuditEvent, Membership, Organization, Role, User
from operations import views as ov
from catalog import views as cv
from . import models as m
from .scoping import scope

LABELS = {
'countries': 'Catálogo común de países', 'organizations': 'Información de empresa', 'producers': 'Productores', 'farms': 'Fincas autorizadas', 'crops': 'Cultivos', 'plots': 'Parcelas y geolocalización', 'harvests': 'Cosechas', 'certifications': 'Certificaciones', 'lots': 'Lotes e inventario', 'inventory-movements': 'Movimientos de inventario', 'lot-relationships': 'Mezclas y transformaciones', 'traceability-events': 'Trazabilidad', 'exports': 'Exportaciones', 'export-allocations': 'Reservas de lotes', 'products': 'Productos', 'clients': 'Clientes e importadores', 'suppliers': 'Proveedores', 'documents': 'Expedientes y documentos', 'requirements': 'Requisitos documentales', 'checklist': 'Lista de verificación', 'compliance': 'Evaluaciones de cumplimiento', 'transports': 'Transportes', 'vehicles': 'Vehículos autorizados', 'drivers': 'Conductores autorizados', 'transport-events': 'Seguimiento y evidencias', 'exchange-rates': 'Tipos de cambio', 'quotes': 'Cotizaciones', 'finance': 'Costos, ingresos y pagos', 'activities': 'Cronograma y responsables', 'incidents': 'Incidencias', 'approvals': 'Aprobaciones empresariales', 'orders': 'Pedidos y recepciones', 'notifications': 'Notificaciones', 'members': 'Equipo y roles', 'invitations': 'Invitaciones al equipo', 'organization-settings': 'Parámetros de empresa', 'platform-organizations': 'Organizaciones registradas', 'platform-users': 'Cuentas de la plataforma', 'roles': 'Roles globales', 'grants': 'Matriz de permisos', 'platform-settings': 'Configuración y funcionalidades', 'technical-incidents': 'Incidentes técnicos', 'audit': 'Auditoría y seguridad', 'service-status': 'Estado de servicios'}
FIELD_LABELS = dict(zip(
'name email user role is_active code identification phone location producer farm crop plot harvest lot source_lot target_lot export importer country product_type quantity quantity_initial quantity_available unit area geometry title document_type shared_with_client issued_on expires_on status review_notes requirement passed notes result vehicle driver assigned_to pickup_place delivery_place scheduled_pickup scheduled_delivery actual_pickup actual_delivery waybill transport event_type event_at evidence operator plate description license_number license_expires_on base_currency target_currency rate rate_date source supplier amount currency valid_until selected kind category counterparty exchange_rate base_amount due_date paid_amount payment_status reference recipient message read key value enabled severity resolution reason destination_country destination_place incoterm commercial_terms commercial_value estimated_departure estimated_arrival actual_departure actual_arrival business_name address position first_name last_name password module action allowed tax_id'.split(),
'Nombre|Correo|Cuenta vinculada|Rol|Activo|Código|Identificación|Teléfono|Ubicación|Productor|Finca|Cultivo|Parcela|Cosecha|Lote|Lote de origen|Lote resultante|Exportación|Importador|País|Producto|Cantidad|Cantidad inicial|Disponible|Unidad|Área|Ubicación GeoJSON|Título|Tipo de documento|Compartir con cliente|Emisión|Vencimiento|Estado|Resultado de revisión|Requisito|Verificado|Observaciones|Resultado|Vehículo|Conductor|Responsable|Recogida|Entrega|Fecha de recogida|Fecha prevista de entrega|Recogida real|Entrega real|Guía|Transporte|Tipo de evento|Fecha y hora|Documento de evidencia|Transportador|Placa|Descripción|Licencia|Vencimiento de licencia|Moneda de origen|Moneda de destino|Tasa de cambio|Fecha de tasa|Fuente|Proveedor|Importe|Moneda|Válida hasta|Seleccionada|Tipo de registro|Categoría|Contraparte|Tipo de cambio|Importe convertido|Fecha de pago|Importe pagado|Estado del pago|Referencia|Destinatario|Mensaje|Leída|Parámetro|Valor|Habilitado|Severidad|Resolución|Justificación|País de destino|Lugar de destino|Incoterm|Condiciones comerciales|Valor comercial|Salida prevista|Llegada prevista|Salida real|Llegada real|Razón social|Dirección|Cargo|Nombres|Apellidos|Contraseña|Módulo|Acción|Permitido|NIT'.split('|')))


def registry():
    from .urls import BUSINESS_VIEWS
    from users.views import OrganizationViewSet
    return {**BUSINESS_VIEWS, 'organizations': OrganizationViewSet,
        'producers': ov.ProducerViewSet, 'farms': ov.FarmViewSet, 'crops': ov.CropViewSet,
        'plots': ov.PlotViewSet, 'harvests': ov.HarvestViewSet, 'certifications': ov.CertificationViewSet,
        'lots': ov.ProductLotViewSet, 'lot-relationships': ov.LotRelationshipViewSet,
        'inventory-movements': ov.InventoryMovementViewSet, 'exports': ov.ExportViewSet,
        'export-allocations': ov.ExportLotAllocationViewSet, 'traceability-events': ov.TraceabilityEventViewSet,
        'clients': cv.ClientViewSet, 'products': cv.ProductViewSet, 'countries': cv.CountryViewSet}


RELATIONS = {'user': 'team', 'assigned_to': 'team', 'operator': 'team', 'role': 'role-options', 'producer': 'producers', 'farm': 'farms', 'crop': 'crops', 'plot': 'plots', 'harvest': 'harvests', 'lot': 'lots', 'source_lot': 'lots', 'target_lot': 'lots', 'export': 'exports', 'importer': 'clients', 'country': 'countries', 'requirement': 'requirements', 'vehicle': 'vehicles', 'driver': 'drivers', 'transport': 'transports', 'evidence': 'documents', 'supplier': 'suppliers', 'exchange_rate': 'exchange-rates', 'recipient': 'team'}


def descriptor(module, cls, allowed, role):
    serializer = cls.serializer_class()
    fields = []
    for name, field in serializer.fields.items():
        if field.read_only or name in ('id', 'organization'):
            continue
        if module == 'platform-users' and name == 'is_active':
            continue
        if role == 'productor' and name in ('user', 'shared_with_client', 'export'):
            continue
        if role == 'logistica' and name in ('operator', 'producer'):
            continue
        if role == 'logistica' and module == 'transports' and name not in ('vehicle', 'driver', 'waybill'):
            continue
        data = {'key': name, 'label': FIELD_LABELS.get(name, str(field.label or name).replace('_', ' ').capitalize()), 'required': field.required, 'nullable': field.allow_null}
        if isinstance(field, serializers.BooleanField):
            data['type'] = 'bool'
        elif name in RELATIONS:
            data.update(type='relation', endpoint=RELATIONS[name])
        elif isinstance(field, serializers.ChoiceField):
            data.update(type='choice', choices=[{'value': str(k), 'label': str(v)} for k, v in field.choices.items()])
        elif isinstance(field, serializers.JSONField):
            data['type'] = 'json'
        elif isinstance(field, serializers.DateTimeField):
            data['type'] = 'datetime'
        elif isinstance(field, serializers.DateField):
            data['type'] = 'date'
        elif isinstance(field, (serializers.DecimalField, serializers.IntegerField)):
            data['type'] = 'number'
        else:
            data['type'] = 'password' if name == 'password' else 'text'
        if name == 'account_status':
            data['label'] = 'Estado de la cuenta'
        if field.default is not serializers.empty and not callable(field.default):
            data['default'] = field.default
        else:
            try:
                model_field = serializer.Meta.model._meta.get_field(name)
                if model_field.has_default():
                    data['default'] = model_field.get_default()
            except FieldDoesNotExist:
                pass
        fields.append(data)
    # Only expose actions implemented by this particular viewset.
    actions = []
    for name, label, permission in [('submit', 'Enviar a revisión', 'submit'), ('approve', 'Aprobar', 'approve'), ('reject', 'Solicitar corrección / rechazar', 'reject'), ('confirm', 'Confirmar recepción', 'submit'), ('upload', 'Cargar nueva versión', 'upload'), ('download', 'Descargar archivo', 'download'), ('history', 'Historial', 'view'), ('traceability', 'Trazabilidad', 'view')]:
        if hasattr(cls, name) and permission in allowed:
            actions.append({'key': name, 'label': label})
    methods = cls.http_method_names
    return {'key': module, 'label': LABELS.get(module, module), 'permissions': allowed, 'fields': fields, 'actions': actions, 'can_create': 'create' in allowed and 'post' in methods and module not in ('members', 'notifications') and not (module == 'transports' and role == 'logistica'), 'can_update': 'update' in allowed and ('put' in methods or 'patch' in methods) and module not in ('invitations',), 'can_report': hasattr(cls, 'report') and 'export' in allowed}


class WorkspaceView(APIView):
    def get(self, request):
        platform = is_platform(request.user) and not request.headers.get('X-Organization-ID')
        membership = None if platform else membership_for(request, exceptional=True)
        role = 'superadmin' if platform else membership.role.name
        allowed = permissions(role)
        modules = [descriptor(key, cls, allowed[key], role) for key, cls in registry().items() if 'view' in allowed.get(key, [])]
        counters = []
        if platform:
            counters = [{'label': 'Organizaciones activas', 'value': Organization.objects.filter(is_active=True).count()}, {'label': 'Usuarios registrados', 'value': User.objects.count()}, {'label': 'Operaciones agregadas', 'value': ov.ExportOperation.objects.count()}, {'label': 'Alertas de seguridad', 'value': AuditEvent.objects.filter(action__startswith='security.').count()}, {'label': 'Incidentes técnicos abiertos', 'value': m.TechnicalIncident.objects.exclude(status='resuelto').count()}]
        else:
            def count(model, **filters):
                return scope(model.objects.all(), membership, request.user).filter(**filters).count()
            candidates = {'productor': [('Fincas registradas', ov.Farm, {}), ('Lotes activos', ov.ProductLot, {'is_active': True}), ('Entregas realizadas', m.Transport, {'status': 'entregado'}), ('Documentos pendientes', m.Document, {'status__in': ['borrador', 'pendiente', 'correcciones', 'rechazado']})],
            'administrador': [('Exportaciones activas', ov.ExportOperation, {'status__in': ['borrador', 'pendiente_documentacion', 'en_revision', 'aprobada_despacho', 'preparacion_logistica', 'transporte_terrestre', 'embarcada', 'transito_internacional', 'arribada']}), ('Operaciones terminadas', ov.ExportOperation, {'status__in': ['entregada', 'cerrada']}), ('Documentos pendientes', m.Document, {'status': 'pendiente'}), ('Alertas logísticas', m.Incident, {'status__in': ['abierta', 'en_proceso']})],
            'documental': [('Documentos pendientes', m.Document, {'status': 'pendiente'}), ('Documentos rechazados', m.Document, {'status__in': ['rechazado', 'correcciones']}), ('Certificados próximos a vencer', m.Document, {'expires_on__range': [timezone.localdate(), timezone.localdate() + timezone.timedelta(days=30)]}), ('Exportaciones por aprobar', ov.ExportOperation, {'status': 'en_revision'}), ('Validaciones realizadas', m.ComplianceEvaluation, {})],
            'logistica': [('Transportes asignados', m.Transport, {}), ('Próximas recogidas', m.Transport, {'status': 'asignado'}), ('Cargas en tránsito', m.Transport, {'status': 'en_transito'}), ('Entregas realizadas', m.Transport, {'status': 'entregado'}), ('Entregas pendientes', m.Transport, {'status__in': ['recogido', 'en_transito']}), ('Incidencias activas', m.Incident, {'status__in': ['abierta', 'en_proceso']})],
            'importador': [('Pedidos activos', m.Order, {'received_at__isnull': True}), ('Envíos en tránsito', m.Transport, {'status': 'en_transito'}), ('Entregas realizadas', m.Order, {'received_at__isnull': False}), ('Documentos disponibles', m.Document, {}), ('Notificaciones', m.Notification, {'read': False})],
            'financiero': [('Pagos pendientes', m.FinanceEntry, {'payment_status__in': ['pendiente', 'parcial']}), ('Cotizaciones', m.Quote, {}), ('Tipos de cambio registrados', m.ExchangeRate, {})]}
            base = [('Operaciones pendientes', ov.ExportOperation, {'status__in': ['borrador', 'pendiente_documentacion', 'requiere_correcciones']}), ('Próximos embarques', ov.ExportOperation, {'estimated_departure__gte': timezone.localdate()}), ('Exportaciones retrasadas', ov.ExportOperation, {'estimated_arrival__lt': timezone.localdate(), 'actual_arrival__isnull': True}), ('Incidencias activas', m.Incident, {'status__in': ['abierta', 'en_proceso']})]
            for label, model, filters in candidates.get(role, base):
                counters.append({'label': label, 'value': count(model, **filters)})
            if role == 'productor':
                required = set(m.Requirement.objects.filter(organization=membership.organization, mandatory=True, is_active=True).values_list('document_type', flat=True))
                provided = set(scope(m.Document.objects.all(), membership, request.user).filter(status='aprobado').values_list('document_type', flat=True))
                counters.append({'label': 'Documentos faltantes', 'value': len(required - provided)})
                counters.append({'label': 'Alertas de cumplimiento', 'value': count(ov.Certification, expires_on__lt=timezone.localdate())})
                for row in scope(ov.ProductLot.objects.all(), membership, request.user).values('unit').annotate(total=Sum('quantity_available')):
                    counters.append({'label': 'Producción disponible (' + row['unit'] + ')', 'value': row['total']})
            if role in ('administrador', 'exportaciones', 'comercial', 'gerencia'):
                for row in scope(ov.ExportLotAllocation.objects.all(), membership, request.user).filter(export__status__in=['entregada', 'cerrada']).values('unit').annotate(total=Sum('quantity')):
                    counters.append({'label': 'Volumen exportado (' + row['unit'] + ')', 'value': row['total']})
            if role in ('financiero', 'administrador', 'gerencia'):
                for row in scope(m.FinanceEntry.objects.all(), membership, request.user).values('base_currency', 'kind').annotate(total=Sum('base_amount')):
                    counters.append({'label': row['kind'].capitalize() + ' (' + row['base_currency'] + ')', 'value': row['total']})
        recent = AuditEvent.objects.filter(organization=membership.organization) if membership and role in ('administrador', 'gerencia') else AuditEvent.objects.filter(organization__isnull=True) if platform else AuditEvent.objects.filter(actor=request.user, organization=membership.organization)
        panels = []
        if membership:
            from types import SimpleNamespace
            choices = {
                'productor': [('lots', 'Mis lotes disponibles'), ('documents', 'Documentos y observaciones de origen'), ('transports', 'Entregas relacionadas')],
                'documental': [('documents', 'Expedientes por revisar'), ('compliance', 'Historial de validaciones')],
                'logistica': [('transports', 'Mis recogidas y entregas'), ('incidents', 'Incidencias de mis cargas')],
                'financiero': [('finance', 'Movimientos y pagos recientes'), ('quotes', 'Comparación de cotizaciones')],
                'importador': [('orders', 'Mis pedidos e historial comercial'), ('transports', 'Mis envíos'), ('documents', 'Documentos compartidos')],
            }
            context_view = SimpleNamespace(get_membership=lambda: membership)
            for module, label in choices.get(role, [('exports', 'Operaciones recientes'), ('activities', 'Cronograma de operaciones'), ('documents', 'Seguimiento documental')]):
                if 'view' not in allowed.get(module, []):
                    continue
                cls = registry()[module]
                records = scope(cls.queryset.all(), membership, request.user).order_by('-pk')[:5]
                data = cls.serializer_class(records, many=True, context={'view': context_view, 'request': request}).data
                keep = ('id', 'code', 'title', 'description', 'reference', 'name', 'status', 'due_at', 'scheduled_pickup', 'scheduled_delivery', 'estimated_departure', 'quantity_available', 'quantity', 'unit', 'amount', 'currency', 'payment_status', 'result', 'expires_on', 'review_notes', 'received_at')
                panels.append({'label': label, 'module': module, 'items': [{key: value for key, value in row.items() if key in keep} for row in data]})
            if role == 'financiero':
                totals = scope(m.FinanceEntry.objects.all(), membership, request.user).values('export_id', 'base_currency', 'kind').annotate(total=Sum('base_amount'))
                margins = {}
                for row in totals:
                    key = (row['export_id'], row['base_currency'])
                    item = margins.setdefault(key, {'title': 'Exportación #' + str(key[0]), 'currency': key[1], 'costo': 0, 'ingreso': 0, 'presupuesto': 0})
                    item[row['kind']] = row['total']
                for item in margins.values():
                    item['margen'] = item['ingreso'] - item['costo']
                    item['variacion_presupuestaria'] = item['costo'] - item['presupuesto']
                panels.append({'label': 'Rentabilidad por operación', 'module': 'finance', 'items': sorted(margins.values(), key=lambda row: row['margen'], reverse=True)})
        return Response({'role': role, 'role_label': dict(Role.ROLE_CHOICES).get(role, role), 'organization': membership.organization.name if membership else 'Administración de plataforma', 'modules': modules, 'metrics': counters, 'panels': panels, 'recent_activity': list(recent.values('action', 'resource_type', 'created_at')[:10])})


class TeamView(APIView):
    def get(self, request):
        member = membership_for(request)
        if member.role.name not in ('administrador', 'exportaciones', 'comercial', 'documental', 'gerencia', 'financiero', 'logistica'):
            raise PermissionDenied('No tienes acceso al directorio del equipo.')
        return Response([{'id': row.user_id, 'name': row.user.get_full_name() or row.user.email, 'email': row.user.email, 'role': row.role.name} for row in Membership.objects.filter(organization=member.organization, is_active=True).select_related('user', 'role')])


class RoleOptionsView(APIView):
    def get(self, request):
        roles = Role.objects.filter(is_active=True)
        if not is_platform(request.user):
            member = membership_for(request)
            require(member.role.name, 'members', 'view')
            roles = roles.exclude(name='superadmin')
        return Response([{'id': row.name, 'name': row.get_name_display()} for row in roles])


class ServiceStatusView(APIView):
    def get(self, request):
        if not is_platform(request.user):
            raise PermissionDenied('Solo administración de plataforma.')
        database = 'disponible'
        try:
            with connection.cursor() as cursor:
                cursor.execute('SELECT 1')
        except Exception:
            database = 'no disponible'
        return Response({'api': 'disponible', 'database': database, 'checked_at': timezone.now()})
