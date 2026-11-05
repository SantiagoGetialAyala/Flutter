from rest_framework import viewsets
from rest_framework.exceptions import PermissionDenied, ValidationError
from rest_framework.permissions import IsAuthenticated

from users.models import Membership

from .models import Client, Country, Product
from .permissions import ClientPermission, IsAdminRole, ProductPermission
from .serializers import ClientSerializer, CountrySerializer, ProductSerializer


class CountryViewSet(viewsets.ModelViewSet):
    queryset = Country.objects.all()
    serializer_class = CountrySerializer

    def get_permissions(self):
        if self.request.method in ("GET", "HEAD", "OPTIONS"):
            return [IsAuthenticated()]
        from users.access import is_platform
        from rest_framework.permissions import BasePermission
        class PlatformPermission(BasePermission):
            def has_permission(self, request, view):
                if not is_platform(request.user):
                    return False
                from users.access import require, action_for
                require('superadmin', 'countries', action_for(view, request))
                return True
        return [PlatformPermission()]

    def perform_create(self, serializer):
        obj = serializer.save()
        from users.access import audit
        audit(self.request, None, 'country.created', obj)

    def perform_update(self, serializer):
        obj = serializer.save()
        from users.access import audit
        audit(self.request, None, 'country.updated', obj)

    def perform_destroy(self, instance):
        instance.is_active = False
        instance.save()
        from users.access import audit
        audit(self.request, None, 'country.deactivated', instance)


from operations.views import OrganizationScopedViewSet


class OrganizationCatalogViewSet(OrganizationScopedViewSet):
    def perform_destroy(self, instance):
        instance.is_active = False
        instance.save()
        from users.access import audit
        audit(self.request, self.organization, 'catalog.deactivated', instance)


class ProductViewSet(OrganizationCatalogViewSet):
    queryset = Product.objects.select_related("organization")
    serializer_class = ProductSerializer



class ClientViewSet(OrganizationCatalogViewSet):
    queryset = Client.objects.select_related("country", "organization")
    serializer_class = ClientSerializer

