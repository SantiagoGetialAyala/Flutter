from django.contrib.auth import authenticate
from django.contrib.auth.password_validation import validate_password
from rest_framework import serializers
from rest_framework_simplejwt.serializers import TokenObtainPairSerializer

from .models import Role, User


class UserSerializer(serializers.ModelSerializer):
    role = serializers.SerializerMethodField()
    role_display = serializers.SerializerMethodField()
    full_name = serializers.SerializerMethodField()
    is_platform = serializers.SerializerMethodField()

    class Meta:
        model = User
        fields = (
            "id",
            "email",
            "first_name",
            "last_name",
            "full_name",
            "role",
            "role_display",
            "position",
            "is_active",
            "is_platform",
        )

    def get_is_platform(self, obj):
        from .access import is_platform
        return is_platform(obj)

    def get_role(self, obj):
        return obj.role.name if obj.role else None

    def get_role_display(self, obj):
        return obj.role.get_name_display() if obj.role else "Sin rol asignado"

    def get_full_name(self, obj):
        return obj.get_full_name() or obj.email


class LoginSerializer(TokenObtainPairSerializer):
    username_field = User.EMAIL_FIELD

    def validate(self, attrs):
        email = attrs.get("email") or attrs.get("username")
        password = attrs.get("password")

        if not email or not password:
            raise serializers.ValidationError("Ingresa correo/usuario y contrasena.")

        user = authenticate(
            request=self.context.get("request"),
            username=email,
            password=password,
        )

        if user is None:
            from .models import AuditEvent
            AuditEvent.objects.create(action='security.login_failed', resource_type='authentication')
            raise serializers.ValidationError("Credenciales incorrectas.")
        if not user.is_active:
            raise serializers.ValidationError("El usuario esta inactivo.")

        refresh = self.get_token(user)
        return {
            "refresh": str(refresh),
            "access": str(refresh.access_token),
            "user": UserSerializer(user).data,
        }


class RegisterSerializer(serializers.Serializer):
    first_name = serializers.CharField(max_length=150, required=False, allow_blank=True)
    last_name = serializers.CharField(max_length=150, required=False, allow_blank=True)
    email = serializers.EmailField()
    password = serializers.CharField(write_only=True, trim_whitespace=False)
    password_confirm = serializers.CharField(write_only=True, trim_whitespace=False)
    # Public self-registration is intentionally limited to non-privileged profiles.
    role = serializers.ChoiceField(
        choices=(Role.PRODUCTOR, Role.COMERCIAL, Role.IMPORTADOR),
        default=Role.COMERCIAL,
    )

    def validate_email(self, value):
        email = User.objects.normalize_email(value)
        if User.objects.filter(email=email).exists():
            raise serializers.ValidationError("Ya existe un usuario con este correo.")
        return email

    def validate(self, attrs):
        if attrs["password"] != attrs["password_confirm"]:
            raise serializers.ValidationError("Las contrasenas no coinciden.")
        validate_password(attrs["password"])
        return attrs

    def create(self, validated_data):
        role_name = validated_data.pop("role", Role.COMERCIAL)
        validated_data.pop("password_confirm")
        password = validated_data.pop("password")
        role = Role.objects.filter(name=role_name, is_active=True).first()

        return User.objects.create_user(
            password=password,
            role=role,
            is_active=True,
            **validated_data,
        )

    def to_representation(self, instance):
        refresh = TokenObtainPairSerializer.get_token(instance)
        return {
            "refresh": str(refresh),
            "access": str(refresh.access_token),
            "user": UserSerializer(instance).data,
        }


class UserAdminSerializer(serializers.ModelSerializer):
    role = serializers.SlugRelatedField(
        queryset=Role.objects.filter(is_active=True),
        slug_field="name",
        required=False,
        allow_null=True,
    )
    role_display = serializers.SerializerMethodField()
    password = serializers.CharField(
        write_only=True,
        required=False,
        allow_blank=True,
        trim_whitespace=False,
    )

    class Meta:
        model = User
        fields = (
            "id",
            "email",
            "first_name",
            "last_name",
            "full_name",
            "role",
            "role_display",
            "position",
            "is_active",
            "account_status",
            "password",
        )
        read_only_fields = ("id", "full_name", "role_display")

    full_name = serializers.SerializerMethodField()

    def get_full_name(self, obj):
        return obj.get_full_name() or obj.email

    def get_role_display(self, obj):
        return obj.role.get_name_display() if obj.role else "Sin rol asignado"

    def validate(self, attrs):
        if 'account_status' in attrs:
            attrs['is_active'] = attrs['account_status'] == 'activa'
        elif 'is_active' in attrs:
            attrs['account_status'] = 'activa' if attrs['is_active'] else 'desactivada'
        return attrs

    def validate_email(self, value):
        email = User.objects.normalize_email(value)
        queryset = User.objects.filter(email=email)
        if self.instance:
            queryset = queryset.exclude(pk=self.instance.pk)
        if queryset.exists():
            raise serializers.ValidationError("Ya existe un usuario con este correo.")
        return email

    def validate_password(self, value):
        if value:
            validate_password(value)
        return value

    def create(self, validated_data):
        password = validated_data.pop("password", None)
        if not password:
            raise serializers.ValidationError({"password": "La contrasena es obligatoria."})
        return User.objects.create_user(password=password, **validated_data)

    def update(self, instance, validated_data):
        password = validated_data.pop("password", None)
        for attr, value in validated_data.items():
            setattr(instance, attr, value)
        if password:
            instance.set_password(password)
        instance.save()
        return instance
