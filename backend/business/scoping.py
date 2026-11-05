from django.db.models import Q


def scope(queryset, membership, user):
    """Apply object ownership after tenant filtering, including related resources."""
    model = queryset.model._meta.model_name
    role = membership.role.name
    qs = queryset.filter(organization=membership.organization)
    if model == 'notification':
        return qs.filter(recipient=user)
    if role == 'productor':
        paths = {
            'producer': 'user', 'farm': 'producer__user', 'crop': 'farm__producer__user',
            'plot': 'farm__producer__user', 'harvest': 'plot__farm__producer__user',
            'certification': 'producer__user', 'productlot': 'producer__user',
            'inventorymovement': 'lot__producer__user', 'lotrelationship': 'source_lot__producer__user',
            'traceabilityevent': 'lot__producer__user',
            'exportoperation': 'allocations__lot__producer__user',
            'transport': 'export__allocations__lot__producer__user',
            'transportevent': 'transport__export__allocations__lot__producer__user',
            'incident': 'export__allocations__lot__producer__user',
        }
        if model == 'document':
            return qs.filter(producer__user=user).distinct()
        return qs.filter(**{paths[model]: user}).distinct() if model in paths else qs.none()
    if role == 'importador':
        paths = {'client': 'user', 'exportoperation': 'importer__user', 'order': 'export__importer__user', 'transport': 'export__importer__user', 'incident': 'export__importer__user'}
        if model == 'document':
            return qs.filter(export__importer__user=user, shared_with_client=True, status='aprobado')
        return qs.filter(**{paths[model]: user}).distinct() if model in paths else qs.none()
    if role == 'logistica':
        paths = {'transport': 'assigned_to', 'transportevent': 'transport__assigned_to', 'vehicle': 'operator', 'driver': 'operator', 'exportoperation': 'transports__assigned_to', 'activity': 'assigned_to', 'incident': 'transport__assigned_to'}
        if model == 'document':
            return qs.filter(owner=user)
        return qs.filter(**{paths[model]: user}).distinct() if model in paths else qs.none()
    return qs
