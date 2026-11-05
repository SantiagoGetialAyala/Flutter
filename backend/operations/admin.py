from django.contrib import admin

from .models import (
    Certification, Crop, ExportLotAllocation, ExportOperation, ExportStatusHistory,
    Farm, Harvest, InventoryMovement, LotRelationship, Plot, ProductLot, Producer,
    TraceabilityEvent,
)


class TenantAdmin(admin.ModelAdmin):
    list_filter = ("organization",)
    readonly_fields = ("created_at", "updated_at")


for model in (Producer, Farm, Crop, Plot, Harvest, Certification, ProductLot,
              LotRelationship, InventoryMovement, ExportOperation, ExportLotAllocation,
              ExportStatusHistory, TraceabilityEvent):
    admin.site.register(model, TenantAdmin)
