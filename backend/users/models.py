from django.contrib.auth.models import AbstractUser, BaseUserManager
from django.db import models


class Role(models.Model):
    SUPERADMIN = "superadmin"
    ADMINISTRADOR = "administrador"
    PRODUCTOR = "productor"
    EXPORTACIONES = "exportaciones"
    DOCUMENTAL = "documental"
    COMERCIAL = "comercial"
    LOGISTICA = "logistica"
    FINANCIERO = "financiero"
    GERENCIA = "gerencia"
    IMPORTADOR = "importador"

    ROLE_CHOICES = [
        (SUPERADMIN, "Superadministrador"),
        (ADMINISTRADOR, "Administrador"),
        (PRODUCTOR, "Productor o proveedor"),
        (EXPORTACIONES, "Exportaciones"),
        (DOCUMENTAL, "Responsable documental"),
        (COMERCIAL, "Comercial"),
        (LOGISTICA, "Logistica"),
        (FINANCIERO, "Financiero"),
        (GERENCIA, "Gerencia"),
        (IMPORTADOR, "Cliente o importador"),
    ]

    name = models.CharField(max_length=40, choices=ROLE_CHOICES, unique=True)
    description = models.CharField(max_length=160, blank=True)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["name"]

    def __str__(self):
        return self.get_name_display()


class Organization(models.Model):
    name = models.CharField(max_length=180)
    tax_id = models.CharField(max_length=40, blank=True)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["name"]

    def __str__(self):
        return self.name


class Membership(models.Model):
    organization = models.ForeignKey(Organization, on_delete=models.CASCADE, related_name="memberships")
    user = models.ForeignKey("User", on_delete=models.CASCADE, related_name="memberships")
    role = models.ForeignKey(Role, on_delete=models.PROTECT, related_name="memberships")
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [models.UniqueConstraint(fields=["organization", "user"], name="unique_org_membership")]


class AuditEvent(models.Model):
    organization = models.ForeignKey(Organization, on_delete=models.CASCADE, related_name="audit_events", null=True, blank=True)
    actor = models.ForeignKey("User", on_delete=models.SET_NULL, null=True, related_name="audit_events")
    action = models.CharField(max_length=80)
    resource_type = models.CharField(max_length=80)
    resource_id = models.CharField(max_length=80, blank=True)
    metadata = models.JSONField(default=dict, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]


class UserManager(BaseUserManager):
    use_in_migrations = True

    def create_user(self, email, password=None, **extra_fields):
        if not email:
            raise ValueError("El correo electronico es obligatorio.")
        email = self.normalize_email(email)
        user = self.model(email=email, username=email, **extra_fields)
        user.set_password(password)
        user.save(using=self._db)
        return user

    def create_superuser(self, email, password=None, **extra_fields):
        extra_fields.setdefault("is_staff", True)
        extra_fields.setdefault("is_superuser", True)
        extra_fields.setdefault("is_active", True)

        if extra_fields.get("is_staff") is not True:
            raise ValueError("El superusuario debe tener is_staff=True.")
        if extra_fields.get("is_superuser") is not True:
            raise ValueError("El superusuario debe tener is_superuser=True.")

        return self.create_user(email, password, **extra_fields)


class User(AbstractUser):
    account_status = models.CharField(max_length=20, choices=[("activa", "Activa"), ("suspendida", "Suspendida"), ("desactivada", "Desactivada")], default="activa")
    username = models.CharField(max_length=150, unique=True, blank=True)
    email = models.EmailField(unique=True)
    role = models.ForeignKey(
        Role,
        on_delete=models.PROTECT,
        related_name="users",
        null=True,
        blank=True,
    )
    position = models.CharField(max_length=80, blank=True)

    USERNAME_FIELD = "email"
    REQUIRED_FIELDS = []

    objects = UserManager()

    def save(self, *args, **kwargs):
        if self.email:
            self.email = self.__class__.objects.normalize_email(self.email)
            self.username = self.email
        super().save(*args, **kwargs)

    def __str__(self):
        return self.email


class RoleGrant(models.Model):
    role = models.ForeignKey(Role, on_delete=models.CASCADE)
    module = models.CharField(max_length=80)
    action = models.CharField(max_length=20)
    allowed = models.BooleanField(default=True)

    class Meta:
        constraints = [models.UniqueConstraint(fields=['role', 'module', 'action'], name='unique_role_module_action')]


class Invitation(models.Model):
    import uuid
    organization = models.ForeignKey(Organization, on_delete=models.CASCADE)
    email = models.EmailField()
    role = models.ForeignKey(Role, on_delete=models.PROTECT)
    token = models.UUIDField(default=uuid.uuid4, unique=True, editable=False)
    expires_at = models.DateTimeField()
    accepted_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
