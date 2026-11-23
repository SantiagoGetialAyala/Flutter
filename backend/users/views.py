from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework import serializers, status, viewsets
from rest_framework.decorators import action
from rest_framework.views import APIView
from rest_framework_simplejwt.views import TokenObtainPairView

from catalog.permissions import IsAdminRole

from .models import Membership, Organization, Role, User
from .serializers import CompanyRegisterSerializer, LoginSerializer, RegisterSerializer, UserAdminSerializer, UserSerializer


class LoginView(TokenObtainPairView):
    permission_classes = [AllowAny]
    serializer_class = LoginSerializer


class RegisterView(APIView):
    permission_classes = [AllowAny]
    serializer_class = RegisterSerializer

    def post(self, request):
        serializer = self.serializer_class(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = serializer.save()
        return Response(serializer.to_representation(user), status=status.HTTP_201_CREATED)


class CompanyRegisterView(RegisterView):
    serializer_class = CompanyRegisterSerializer


class CurrentUserView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        data = UserSerializer(request.user).data
        from .access import is_platform
        data["is_platform"] = is_platform(request.user)
        data["organizations"] = OrganizationSerializer(
            Organization.objects.filter(memberships__user=request.user, memberships__is_active=True, is_active=True), many=True
        ).data
        return Response(data)


class OrganizationSerializer(serializers.ModelSerializer):
    class Meta:
        model = Organization
        fields = ("id", "name", "tax_id", "is_active", "created_at")
        read_only_fields = ("id", "is_active", "created_at")


class OrganizationViewSet(viewsets.ModelViewSet):
    search_fields = ('name', 'tax_id')
    serializer_class = OrganizationSerializer

    def get_queryset(self):
        from .access import is_platform
        if is_platform(self.request.user):
            return Organization.objects.all()
        return Organization.objects.filter(
            memberships__user=self.request.user,
            memberships__is_active=True,
            is_active=True,
        ).distinct()

    def perform_create(self, serializer):
        from rest_framework.exceptions import PermissionDenied
        raise PermissionDenied(
            "Crea la empresa desde Empresas en el panel de plataforma para generar su código de acceso."
        )

    def update(self, request, *args, **kwargs):
        membership = Membership.objects.filter(
            organization_id=kwargs.get("pk"), user=request.user, is_active=True,
            role__name__in=[Role.ADMINISTRADOR, Role.SUPERADMIN],
        ).exists()
        if not membership:
            from rest_framework.exceptions import PermissionDenied
            raise PermissionDenied("Se requiere rol administrador en esta organización.")
        from .access import require
        require(Role.ADMINISTRADOR, 'organizations', 'update')
        return super().update(request, *args, **kwargs)

    def destroy(self, request, *args, **kwargs):
        from rest_framework.exceptions import PermissionDenied
        raise PermissionDenied("Las organizaciones no se eliminan desde la API.")


class LogoutView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        return Response({"detail": "Sesion cerrada en el cliente."})


from .management import PlatformUserViewSet as UserViewSet
