from rest_framework.routers import DefaultRouter

from .views import (
    CertificationViewSet, CropViewSet, ExportLotAllocationViewSet, ExportViewSet,
    FarmViewSet, HarvestViewSet, InventoryMovementViewSet, PlotViewSet,
    ProductLotViewSet, ProducerViewSet, TraceabilityEventViewSet, LotRelationshipViewSet,
)

router = DefaultRouter()
router.register("producers", ProducerViewSet, basename="producer")
router.register("farms", FarmViewSet, basename="farm")
router.register("crops", CropViewSet, basename="crop")
router.register("plots", PlotViewSet, basename="plot")
router.register("harvests", HarvestViewSet, basename="harvest")
router.register("certifications", CertificationViewSet, basename="certification")
router.register("lots", ProductLotViewSet, basename="lot")
router.register("lot-relationships", LotRelationshipViewSet, basename="lot-relationship")
router.register("inventory-movements", InventoryMovementViewSet, basename="inventory-movement")
router.register("exports", ExportViewSet, basename="export")
router.register("export-allocations", ExportLotAllocationViewSet, basename="export-allocation")
router.register("traceability-events", TraceabilityEventViewSet, basename="traceability-event")

urlpatterns = router.urls
