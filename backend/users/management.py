from datetime import timedelta
from django.db import transaction
from django.utils import timezone
from rest_framework import serializers, viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import PermissionDenied, ValidationError
from rest_framework.response import Response
from rest_framework.views import APIView
from operations.views import OrganizationScopedViewSet
from .access import ACTIONS, MATRIX, PLATFORM, action_for, audit, is_platform, require
from .models import AuditEvent, Invitation, Membership, Organization, Role, RoleGrant, User
from .serializers import UserAdminSerializer


class MemberSerializer(serializers.ModelSerializer):
    email = serializers.EmailField(source='user.email', read_only=True)
    name = serializers.CharField(source='user.get_full_name', read_only=True)
    role = serializers.SlugRelatedField(slug_field='name', queryset=Role.objects.filter(is_active=True, name__in=Role.BUSINESS_ROLES))
    class Meta:
        model = Membership
        fields = ('id', 'user', 'email', 'name', 'role', 'is_active')

    def validate(self, attrs):
        # User links cannot be moved between memberships.
        if self.instance and 'user' in attrs and attrs['user'] != self.instance.user:
            raise ValidationError({'user': 'Crea una nueva membresía para otra cuenta.'})
        if self.instance and self.instance.user == self.context['request'].user and (attrs.get('is_active') is False or ('role' in attrs and attrs['role'].name != Role.ADMINISTRADOR)):
            raise ValidationError('No puedes revocar tu propia administración.')
        return attrs


class MemberViewSet(OrganizationScopedViewSet):
    search_fields = ('user__email', 'user__first_name', 'user__last_name', 'role__name')
    module = 'members'
    queryset = Membership.objects.select_related('user', 'role')
    serializer_class = MemberSerializer

    def perform_destroy(self, instance):
        if instance.user == self.request.user:
            raise ValidationError('No puedes revocar tu propia membresía.')
        instance.is_active = False
        instance.save()
        audit(self.request, self.organization, 'membership.revoked', instance)


class InvitationSerializer(serializers.ModelSerializer):
    role = serializers.SlugRelatedField(slug_field='name', queryset=Role.objects.filter(is_active=True, name__in=Role.BUSINESS_ROLES))
    class Meta:
        model = Invitation
        fields = ('id', 'email', 'role', 'token', 'expires_at', 'accepted_at', 'created_at')
        read_only_fields = ('token', 'accepted_at', 'created_at', 'expires_at')


class InvitationViewSet(OrganizationScopedViewSet):
    search_fields = ('email', 'role__name')
    module = 'invitations'
    queryset = Invitation.objects.select_related('role')
    serializer_class = InvitationSerializer
    http_method_names = ['get', 'post', 'head', 'options']

    def perform_create(self, serializer):
        obj = serializer.save(organization=self.organization, expires_at=timezone.now() + timedelta(days=7))
        audit(self.request, self.organization, 'invitation.created', obj)


class AcceptInvitationView(APIView):
    def post(self, request):
        from .invitations import accept_invitation
        accept_invitation(request.user, request.data.get('token'))
        return Response({'detail': 'Ya puedes acceder a la organización.'})


class PlatformViewSet(viewsets.ModelViewSet):
    def get_queryset(self):
        queryset = super().get_queryset()
        return queryset if queryset.ordered else queryset.order_by("pk")

    def check_permissions(self, request):
        super().check_permissions(request)
        if not is_platform(request.user):
            raise PermissionDenied('Se requiere administración de plataforma.')
        require('superadmin', self.module, action_for(self, request))

    def perform_create(self, serializer):
        obj = serializer.save()
        audit(self.request, None, self.module + '.created', obj)

    def perform_update(self, serializer):
        obj = serializer.save()
        audit(self.request, None, self.module + '.updated', obj)

    def perform_destroy(self, instance):
        raise PermissionDenied('Conserva el registro y desactívalo para mantener la auditoría.')


class PlatformOrganizationSerializer(serializers.ModelSerializer):
    administrator_email = serializers.EmailField(write_only=True, required=True, label='Correo del primer administrador')
    administrator_invitation = serializers.SerializerMethodField()

    class Meta:
        model = Organization
        fields = ('id', 'name', 'tax_id', 'is_active', 'created_at', 'updated_at', 'administrator_email', 'administrator_invitation')
        read_only_fields = ('id', 'created_at', 'updated_at')

    def validate(self, attrs):
        if self.instance is None and not attrs.get('administrator_email'):
            raise ValidationError({'administrator_email': 'Indica quién administrará la empresa.'})
        if self.instance is not None and attrs.get('administrator_email'):
            raise ValidationError({'administrator_email': 'La invitación inicial se configura al crear la empresa.'})
        return attrs

    @transaction.atomic
    def create(self, validated_data):
        email = User.objects.normalize_email(validated_data.pop('administrator_email'))
        organization = super().create(validated_data)
        role = Role.objects.get(name=Role.ADMINISTRADOR, is_active=True)
        invitation = Invitation.objects.create(organization=organization, email=email, role=role, expires_at=timezone.now() + timedelta(days=7))
        organization._initial_invitation = invitation
        audit(self.context['request'], organization, 'organization.administrator_invited', invitation)
        return organization

    def get_administrator_invitation(self, obj):
        invitation = getattr(obj, '_initial_invitation', None)
        if invitation is None and getattr(self.context.get('view'), 'action', None) == 'retrieve':
            invitation = Invitation.objects.filter(organization=obj, role__name=Role.ADMINISTRADOR, accepted_at__isnull=True, expires_at__gt=timezone.now()).order_by('-created_at').first()
        if invitation is None:
            return None
        return {'email': invitation.email, 'token': str(invitation.token), 'expires_at': invitation.expires_at}


class PlatformOrganizationViewSet(PlatformViewSet):
    search_fields = ('name', 'tax_id')
    module = 'platform-organizations'
    queryset = Organization.objects.all()
    serializer_class = PlatformOrganizationSerializer


class PlatformUserViewSet(PlatformViewSet):
    search_fields = ('email', 'first_name', 'last_name')
    module = 'platform-users'
    queryset = User.objects.select_related('role').all().order_by('email')
    serializer_class = UserAdminSerializer

    def perform_update(self, serializer):
        if serializer.instance.pk == self.request.user.pk and (serializer.validated_data.get('is_active') is False or ('role' in serializer.validated_data and serializer.validated_data['role'] != serializer.instance.role)):
            raise ValidationError('No puedes desactivar tu propia cuenta.')
        super().perform_update(serializer)


class RoleSerializer(serializers.ModelSerializer):
    class Meta:
        model = Role
        fields = ('id', 'name', 'description', 'is_active')
    def validate(self, attrs):
        if self.instance and attrs.get('name', self.instance.name) != self.instance.name:
            raise ValidationError('El identificador de rol es estable; edita su descripción o permisos.')
        return attrs


class RoleViewSet(PlatformViewSet):
    module = 'roles'
    queryset = Role.objects.filter(name__in=(*Role.BUSINESS_ROLES, Role.SUPERADMIN))
    serializer_class = RoleSerializer

    def perform_update(self, serializer):
        if serializer.instance.pk == self.request.user.role_id and serializer.validated_data.get('is_active') is False:
            raise ValidationError('No puedes desactivar el rol de tu sesión administrativa.')
        super().perform_update(serializer)


class GrantSerializer(serializers.ModelSerializer):
    role = serializers.SlugRelatedField(slug_field='name', queryset=Role.objects.all())
    action = serializers.ChoiceField(choices=ACTIONS)
    class Meta:
        model = RoleGrant
        fields = '__all__'
    def validate_module(self, value):
        modules = {module for grants in MATRIX.values() for module in grants}
        if value not in modules:
            raise ValidationError('Módulo desconocido.')
        return value
    def validate(self, attrs):
        role = attrs.get('role', getattr(self.instance, 'role', None))
        module = attrs.get('module', getattr(self.instance, 'module', None))
        if role.name != 'superadmin' and module in PLATFORM.split():
            raise ValidationError('Los permisos de plataforma son exclusivos del superadministrador.')
        return attrs


class GrantViewSet(PlatformViewSet):
    module = 'grants'
    queryset = RoleGrant.objects.select_related('role')
    serializer_class = GrantSerializer

    @action(detail=False, methods=['get'])
    def matrix(self, request):
        from .access import permissions
        return Response({name: permissions(name) for name in (*Role.BUSINESS_ROLES, Role.SUPERADMIN)})


class AuditSerializer(serializers.ModelSerializer):
    class Meta:
        model = AuditEvent
        fields = '__all__'


class AuditViewSet(PlatformViewSet):
    module = 'audit'
    queryset = AuditEvent.objects.all()
    serializer_class = AuditSerializer
    http_method_names = ['get', 'head', 'options']
