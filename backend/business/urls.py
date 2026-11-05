from django.urls import path
from rest_framework.routers import DefaultRouter
from rest_framework import serializers
from users.management import (PlatformViewSet, PlatformOrganizationViewSet, PlatformUserViewSet, RoleViewSet, GrantViewSet, AuditViewSet, MemberViewSet, InvitationViewSet, AcceptInvitationView)
from . import models as m
from .views import BusinessViewSet, DocumentViewSet, TransportViewSet, TransportEventViewSet, ApprovalViewSet, OrderViewSet, FinanceViewSet
from .serializers import serializer_for

router = DefaultRouter()
BUSINESS_VIEWS = {}
MODELS = {
    'suppliers': m.Supplier, 'organization-settings': m.OrganizationSetting,
    'requirements': m.Requirement, 'checklist': m.ChecklistItem, 'compliance': m.ComplianceEvaluation,
    'documents': m.Document, 'transports': m.Transport, 'vehicles': m.Vehicle,
    'drivers': m.Driver, 'transport-events': m.TransportEvent, 'exchange-rates': m.ExchangeRate,
    'quotes': m.Quote, 'finance': m.FinanceEntry, 'activities': m.Activity,
    'incidents': m.Incident, 'approvals': m.Approval, 'orders': m.Order, 'notifications': m.Notification,
}
SPECIAL = {'documents': DocumentViewSet, 'transports': TransportViewSet, 'transport-events': TransportEventViewSet, 'approvals': ApprovalViewSet, 'orders': OrderViewSet, 'finance': FinanceViewSet}
for module, model in MODELS.items():
    cls = SPECIAL.get(module) or type(model.__name__ + 'ViewSet', (BusinessViewSet,), {'module': module, 'queryset': model.objects.all().order_by('-pk'), 'serializer_class': serializer_for(model), 'search_fields': tuple(f.name for f in model._meta.fields if f.get_internal_type() in ('CharField', 'TextField'))})
    if module == 'notifications':
        cls.http_method_names = ['get', 'patch', 'head', 'options']
    if module == 'compliance':
        cls.http_method_names = ['get', 'post', 'head', 'options']
    BUSINESS_VIEWS[module] = cls
    router.register(module, cls, basename=module)

for module, model in {'platform-settings': m.PlatformSetting, 'technical-incidents': m.TechnicalIncident}.items():
    serializer = type(model.__name__ + 'Serializer', (serializers.ModelSerializer,), {'Meta': type('Meta', (), {'model': model, 'fields': '__all__'})})
    cls = type(model.__name__ + 'ViewSet', (PlatformViewSet,), {'module': module, 'queryset': model.objects.all().order_by('-pk'), 'serializer_class': serializer})
    BUSINESS_VIEWS[module] = cls
    router.register(module, cls, basename=module)

for module, cls in {'platform-organizations': PlatformOrganizationViewSet, 'platform-users': PlatformUserViewSet, 'roles': RoleViewSet, 'grants': GrantViewSet, 'audit': AuditViewSet, 'members': MemberViewSet, 'invitations': InvitationViewSet}.items():
    BUSINESS_VIEWS[module] = cls
    router.register(module, cls, basename=module)

from .workspace import WorkspaceView, TeamView, RoleOptionsView, ServiceStatusView
urlpatterns = [path('workspace/', WorkspaceView.as_view()), path('team/', TeamView.as_view()), path('role-options/', RoleOptionsView.as_view()), path('service-status/', ServiceStatusView.as_view()), path('invitations/accept/', AcceptInvitationView.as_view())] + router.urls
