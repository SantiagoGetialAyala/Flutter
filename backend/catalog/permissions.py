from rest_framework.permissions import SAFE_METHODS, BasePermission

from users.models import Role


def user_role(user):
    if not user or not user.is_authenticated or not user.role:
        return None
    return user.role.name


class IsAdminRole(BasePermission):
    def has_permission(self, request, view):
        return user_role(request.user) == Role.ADMINISTRADOR


class ProductPermission(BasePermission):
    write_roles = {Role.ADMINISTRADOR, Role.EXPORTACIONES, Role.COMERCIAL}

    def has_permission(self, request, view):
        if request.method in SAFE_METHODS:
            return request.user and request.user.is_authenticated
        return user_role(request.user) in self.write_roles


class ClientPermission(BasePermission):
    write_roles = {Role.ADMINISTRADOR, Role.COMERCIAL, Role.EXPORTACIONES}

    def has_permission(self, request, view):
        if request.method in SAFE_METHODS:
            return request.user and request.user.is_authenticated
        return user_role(request.user) in self.write_roles
