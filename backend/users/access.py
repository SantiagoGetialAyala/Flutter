"""Single source of truth for module/action permissions and tenant selection."""
from types import SimpleNamespace
from rest_framework.exceptions import PermissionDenied, ValidationError
from .models import AuditEvent, Membership, Organization, Role

ACTIONS = ('view', 'create', 'update', 'delete', 'submit', 'approve', 'reject', 'assign', 'upload', 'download', 'export', 'manage')
READ = {'view'}
EDIT = {'view', 'create', 'update', 'export'}
MATRIX = {}


def grant(roles, modules, actions):
    for role in roles.split():
        for module in modules.split():
            MATRIX.setdefault(role, {}).setdefault(module, set()).update(actions)


ORIGIN = 'producers farms crops plots harvests certifications lots inventory-movements lot-relationships traceability-events'
BUSINESS = ORIGIN + ' products clients suppliers exports export-allocations documents requirements checklist compliance transports vehicles drivers transport-events finance quotes exchange-rates activities incidents approvals orders notifications members invitations organization-settings'
grant('administrador', BUSINESS, ACTIONS)
grant('productor', ORIGIN, EDIT)
grant('productor', 'documents', {'view', 'create', 'upload', 'download', 'submit'})
grant('productor', 'transports transport-events incidents', READ)
grant('exportaciones comercial', 'products clients suppliers exports export-allocations activities incidents approvals orders', EDIT | {'submit', 'assign'})
grant('exportaciones comercial', ORIGIN + ' documents requirements checklist compliance transports vehicles drivers transport-events', READ)
grant('exportaciones comercial', 'documents', {'upload', 'download', 'create', 'submit'})
grant('documental', 'documents requirements checklist compliance', EDIT | {'upload', 'download', 'submit', 'approve', 'reject'})
grant('documental', ORIGIN + ' exports activities incidents approvals', READ)
grant('documental', 'exports', {'approve', 'reject', 'submit'})
grant('documental', 'incidents', EDIT)
grant('logistica', 'transports transport-events', EDIT | {'submit', 'upload'})
grant('logistica', 'vehicles drivers', EDIT)
grant('logistica', 'incidents', EDIT)
grant('logistica', 'exports activities', READ)
grant('financiero', 'finance quotes exchange-rates', EDIT | {'submit', 'approve', 'reject'})
grant('financiero', 'exports clients suppliers approvals', READ)
grant('gerencia', BUSINESS, READ | {'export'})
grant('gerencia', 'approvals', {'approve', 'reject'})
grant('importador', 'exports orders documents transports', READ)
grant('importador', 'documents', {'download'})
grant('importador', 'orders', {'submit'})
grant('importador', 'incidents', {'view', 'create'})
grant('administrador productor exportaciones documental comercial logistica financiero gerencia importador', 'notifications', {'view', 'update'})
PLATFORM = 'platform-organizations platform-users roles grants platform-settings technical-incidents audit service-status'
grant('superadmin', PLATFORM, ACTIONS)


def is_platform(user):
    return user.is_authenticated and (user.is_superuser or (user.role and user.role.is_active and user.role.name == Role.SUPERADMIN))


def permissions(role):
    from .models import RoleGrant
    result = {module: set(actions) for module, actions in MATRIX.get(role, {}).items()}
    for override in RoleGrant.objects.filter(role__name=role):
        if override.allowed:
            result.setdefault(override.module, set()).add(override.action)
        else:
            result.setdefault(override.module, set()).discard(override.action)
    from business.models import PlatformSetting
    disabled = set(PlatformSetting.objects.filter(key__startswith='module.', enabled=False).values_list('key', flat=True))
    return {key: sorted(value) for key, value in result.items() if value and (role == 'superadmin' or 'module.' + key not in disabled)}


def require(role, module, action):
    if action not in permissions(role).get(module, []):
        raise PermissionDenied('Tu rol no tiene permiso para esta acción.')


def membership_for(request, *, exceptional=False):
    memberships = Membership.objects.filter(user=request.user, is_active=True, organization__is_active=True, role__is_active=True).select_related('organization', 'role')
    org_id = request.headers.get('X-Organization-ID')
    if org_id:
        try:
            org_id = int(org_id)
        except (ValueError, TypeError):
            raise PermissionDenied('Identificador de organización inválido.')
        membership = memberships.filter(organization_id=org_id).first()
        if membership:
            return membership
        if exceptional and is_platform(request.user):
            reason = request.headers.get('X-Access-Reason', '').strip()
            if len(reason) < 15:
                raise PermissionDenied('El acceso excepcional exige una justificación de al menos 15 caracteres en X-Access-Reason.')
            organization = Organization.objects.filter(pk=org_id, is_active=True).first()
            if organization is None:
                raise PermissionDenied('Organización inactiva o inexistente.')
            if request.method not in ('GET', 'HEAD', 'OPTIONS'):
                raise PermissionDenied('El acceso excepcional de plataforma es de consulta.')
            AuditEvent.objects.create(organization=organization, actor=request.user, action='security.exceptional_access', resource_type='organization', resource_id=str(org_id), metadata={'reason': reason, 'path': request.path})
            return SimpleNamespace(organization=organization, organization_id=org_id, role=SimpleNamespace(name='gerencia'), exceptional=True)
        raise PermissionDenied('No perteneces a la organización solicitada.')
    found = list(memberships[:2])
    if len(found) > 1:
        raise ValidationError({'organization': 'Selecciona una organización mediante X-Organization-ID.'})
    if not found:
        raise PermissionDenied('Necesitas una organización activa para acceder a este módulo.')
    return found[0]


def action_for(view, request):
    return {'list': 'view', 'retrieve': 'view', 'metadata': 'view', 'create': 'create', 'update': 'update', 'partial_update': 'update', 'destroy': 'delete', 'history': 'view', 'traceability': 'view', 'report': 'export', 'download': 'download', 'upload': 'upload', 'submit': 'submit', 'approve': 'approve', 'reject': 'reject', 'assign': 'assign', 'confirm': 'submit', 'transition': 'submit'}.get(view.action, 'view')


def audit(request, organization, action, obj, metadata=None):
    AuditEvent.objects.create(actor=request.user, organization=organization, action=action, resource_type=obj._meta.model_name, resource_id=str(obj.pk), metadata=metadata or {})

# Coordinators assign transport; operators act only on assigned records.
grant('administrador exportaciones comercial', 'transports', EDIT | {'assign'})
grant('logistica', 'documents', {'view', 'create', 'upload', 'download', 'submit'})
grant('logistica', 'transports', {'submit'})
grant('logistica', 'vehicles drivers', {'create', 'update'})

grant('administrador', 'organizations', EDIT)

# Invitation tokens are visible only to organization administrators.
MATRIX['gerencia'].pop('invitations', None)
MATRIX['gerencia'].pop('members', None)

# Four business roles: administration owns the commercial, document and finance work.
MATRIX['administrador']['orders'] = EDIT | {'submit'}
for module in ('transport-events', 'vehicles', 'drivers'):
    MATRIX['administrador'][module] = set(READ)

grant('superadmin', 'countries', ACTIONS)
