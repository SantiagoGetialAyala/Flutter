"""Actionable work derived from real records and existing access grants."""
from django.utils import timezone
from django.db.models import OuterRef, Subquery
from . import models as m
from .scoping import scope


def pending_tasks(membership, user, allowed):
    tasks = []
    role = membership.role.name
    task_roles = {
        'transports': {'logistica'},
        'finance': {'administrador', 'financiero'},
        'approvals': {'administrador', 'gerencia'},
        'orders': {'importador'},
    }

    def collect(module, model, title, action, filters, exclude=None, due=None, review=False):
        if module in task_roles and role not in task_roles[module]:
            return
        grants = allowed.get(module, [])
        if 'view' not in grants or not set(action).intersection(grants):
            return
        qs = scope(model.objects.all(), membership, user).filter(**filters)
        if exclude:
            qs = qs.exclude(**exclude)
        if review:
            latest = m.DocumentVersion.objects.filter(document_id=OuterRef('pk')).order_by('-number')
            qs = qs.exclude(owner=user).annotate(latest_uploader=Subquery(latest.values('uploaded_by_id')[:1])).exclude(latest_uploader=user.pk)
        qs = qs.order_by(due or 'created_at', 'pk')
        for row in qs[:12]:
            deadline = getattr(row, due, None) if due else None
            tasks.append({
                'id': f'{module}:{row.pk}', 'module': module, 'record_id': row.pk,
                'export_id': getattr(row, 'export_id', None),
                'title': title(row), 'status': getattr(row, 'status', getattr(row, 'payment_status', 'pendiente')),
                'due_at': deadline, 'overdue': bool(deadline and (deadline < timezone.now() if hasattr(deadline, 'hour') else deadline < timezone.localdate())),
            })

    if role == 'documental':
        collect('documents', m.Document, lambda r: 'Revisar: ' + r.title, ['approve', 'reject'], {'status': 'pendiente'}, review=True)
    else:
        collect('documents', m.Document, lambda r: 'Completar: ' + r.title, ['upload', 'submit'], {'status__in': ['borrador', 'correcciones', 'rechazado'], 'owner': user})
        if role == 'administrador':
            collect('documents', m.Document, lambda r: 'Revisar: ' + r.title, ['approve', 'reject'], {'status': 'pendiente'})
    collect('activities', m.Activity, lambda r: r.title, ['update'], {'assigned_to': user, 'completed': False}, due='due_at')
    collect('transports', m.Transport, lambda r: f'Atender envío #{r.pk}: {r.pickup_place} → {r.delivery_place}', ['update'], {'assigned_to': user, 'status__in': ['asignado', 'recogido', 'en_transito']}, due='scheduled_pickup')
    collect('finance', m.FinanceEntry, lambda r: 'Registrar pago: ' + r.description, ['update'], {'payment_status__in': ['pendiente', 'parcial']}, due='due_date')
    collect('approvals', m.Approval, lambda r: 'Decidir: ' + r.title, ['approve', 'reject'], {'status': 'pendiente'}, exclude={'requested_by': user})
    collect('orders', m.Order, lambda r: 'Confirmar recepción: ' + r.reference, ['submit'], {'received_at__isnull': True, 'export__importer__user': user, 'export__status__in': ['arribada', 'entregada', 'cerrada']})
    if role in {'administrador', 'exportaciones', 'comercial', 'documental'} and 'view' in allowed.get('exports', []):
        from operations.models import ExportOperation
        from operations.workflow import allowed_transitions
        exports = scope(ExportOperation.objects.all(), membership, user).exclude(
            status__in=['cerrada', 'cancelada', 'rechazada'])
        if role in {'exportaciones', 'comercial'}:
            exports = exports.filter(responsible=user).exclude(status='en_revision')
        else:
            if role == 'documental':
                exports = exports.filter(status='en_revision')
        for row in exports.order_by('created_at')[:12]:
            transitions = allowed_transitions(row.status, role, allowed.get('exports', []))
            if transitions:
                tasks.append({'id': f'exports:{row.pk}', 'module': 'exports',
                    'record_id': row.pk, 'export_id': row.pk,
                    'title': ('Validar despacho: ' if role == 'documental' else 'Continuar operación: ') + row.code, 'status': row.status,
                    'due_at': None, 'overdue': False})
    return sorted(tasks, key=lambda r: (not r['overdue'], str(r['due_at'] or '9999'), r['id']))[:40]
