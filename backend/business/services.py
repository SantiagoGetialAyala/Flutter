from django.utils import timezone
from django.db.models import Q
from rest_framework.exceptions import ValidationError
from .models import ChecklistItem, Requirement


def ensure_compliance(export, *, require_evaluation=True):
    requirements = Requirement.objects.filter(organization=export.organization, is_active=True, mandatory=True).filter(Q(destination_country='') | Q(destination_country__iexact=export.destination_country))
    missing = []
    if not requirements.exists():
        raise ValidationError({'requirements': 'Configura al menos un requisito obligatorio antes de aprobar el expediente.'})
    today = timezone.localdate()
    for requirement in requirements:
        docs = export.documents.filter(document_type=requirement.document_type, status='aprobado', versions__isnull=False).filter(Q(expires_on__isnull=True) | Q(expires_on__gte=today))
        if not docs.exists() or not ChecklistItem.objects.filter(export=export, requirement=requirement, passed=True).exists():
            missing.append(requirement.name)
    if missing:
        raise ValidationError({'requirements': 'Requisitos pendientes o vencidos: ' + ', '.join(missing)})
    latest = export.evaluations.order_by('-created_at', '-pk').first()
    if require_evaluation and (latest is None or latest.result != 'conforme'):
        raise ValidationError({'compliance': 'Se requiere una evaluación de cumplimiento conforme.'})
