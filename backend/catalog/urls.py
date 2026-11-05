from rest_framework.routers import DefaultRouter

from .views import ClientViewSet, CountryViewSet, ProductViewSet

router = DefaultRouter()
router.register("countries", CountryViewSet, basename="country")
router.register("products", ProductViewSet, basename="product")
router.register("clients", ClientViewSet, basename="client")

urlpatterns = router.urls
