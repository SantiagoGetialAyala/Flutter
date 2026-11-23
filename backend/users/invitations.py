from django.core.exceptions import ValidationError as DjangoValidationError
from django.db import transaction
from django.utils import timezone
from rest_framework.exceptions import ValidationError

from .models import AuditEvent, Invitation, Membership, Role


@transaction.atomic
def accept_invitation(user, token):
    try:
        invitation = Invitation.objects.select_for_update().select_related('role').get(
            token=token, email__iexact=user.email, accepted_at__isnull=True,
            expires_at__gt=timezone.now(), organization__is_active=True,
            role__is_active=True,
            role__name__in=Role.BUSINESS_ROLES,
        )
    except (Invitation.DoesNotExist, ValueError, DjangoValidationError):
        raise ValidationError({'invitation_code': 'Invitación inválida, vencida o destinada a otro correo.'})
    Membership.objects.update_or_create(
        organization=invitation.organization, user=user,
        defaults={'role': invitation.role, 'is_active': True},
    )
    if user.role_id is None:
        user.role = invitation.role
        user.save(update_fields=['role'])
    invitation.accepted_at = timezone.now()
    invitation.save(update_fields=['accepted_at'])
    AuditEvent.objects.create(
        actor=user, organization=invitation.organization,
        action='invitation.accepted', resource_type='invitation',
        resource_id=str(invitation.pk),
    )
    return invitation
