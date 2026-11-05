from django.contrib import admin
from django.urls import include, path

urlpatterns = [
    path("admin/", admin.site.urls),
    path("api/auth/", include("users.urls")),
    path("api/", include("business.urls")),
    path("api/", include("users.api_urls")),
    path("api/", include("catalog.urls")),
    path("api/", include("operations.urls")),
]
