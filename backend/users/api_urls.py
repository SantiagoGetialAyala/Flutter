from rest_framework.routers import DefaultRouter

from .views import OrganizationViewSet, UserViewSet

router = DefaultRouter()
router.register("users", UserViewSet, basename="user")
router.register("organizations", OrganizationViewSet, basename="organization")

urlpatterns = router.urls
