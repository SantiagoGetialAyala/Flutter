"""Shared lifecycle rules used by the API and its authorized UI hints."""
TRANSITIONS = {
    'borrador': {'pendiente_documentacion', 'cancelada'},
    'pendiente_documentacion': {'en_revision', 'cancelada'},
    'en_revision': {'requiere_correcciones', 'aprobada_despacho', 'rechazada'},
    'requiere_correcciones': {'pendiente_documentacion', 'cancelada'},
    'aprobada_despacho': {'preparacion_logistica', 'bloqueada'},
    'preparacion_logistica': {'transporte_terrestre', 'embarcada', 'bloqueada'},
    'transporte_terrestre': {'embarcada', 'bloqueada'},
    'embarcada': {'transito_internacional', 'bloqueada'},
    'transito_internacional': {'arribada', 'bloqueada'},
    'arribada': {'entregada', 'bloqueada'},
    'entregada': {'cerrada'},
    'bloqueada': {'pendiente_documentacion', 'cancelada'},
}
LOGISTICS_STATES = {'transporte_terrestre', 'embarcada', 'transito_internacional', 'arribada', 'entregada'}
DOCUMENT_STATES = {'en_revision', 'requiere_correcciones', 'aprobada_despacho', 'rechazada'}


def allowed_transitions(status, role, grants=None):
    from users.access import permissions
    if grants is None:
        grants = permissions(role).get('exports', [])
    result = []
    for target in sorted(TRANSITIONS.get(status, set())):
        action = 'approve' if target == 'aprobada_despacho' else 'reject' if target in {'rechazada', 'requiere_correcciones', 'bloqueada'} else 'submit'
        if action not in grants:
            continue
        if target in LOGISTICS_STATES and role not in {'administrador', 'exportaciones', 'logistica'}:
            continue
        if target in DOCUMENT_STATES and role not in {'administrador', 'documental'}:
            continue
        if (target == 'bloqueada' or status == 'bloqueada') and role not in {'administrador', 'documental'}:
            continue
        result.append(target)
    return result
