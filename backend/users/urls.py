from django.urls import path
from rest_framework_simplejwt.views import TokenRefreshView

from .views import CompanyRegisterView, CurrentUserView, LoginView, LogoutView, RegisterView

urlpatterns = [
    path("register-company/", CompanyRegisterView.as_view(), name="register_company"),
    path("register/", RegisterView.as_view(), name="register"),
    path("login/", LoginView.as_view(), name="login"),
    path("refresh/", TokenRefreshView.as_view(), name="token_refresh"),
    path("me/", CurrentUserView.as_view(), name="current_user"),
    path("logout/", LogoutView.as_view(), name="logout"),
]
