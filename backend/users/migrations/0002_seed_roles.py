from django.db import migrations


ROLES = [
    ("administrador", "Administrador del sistema"),
    ("exportaciones", "Gestion operativa de exportaciones"),
    ("comercial", "Gestion comercial"),
    ("logistica", "Gestion logistica"),
    ("financiero", "Gestion financiera"),
    ("gerencia", "Vista gerencial"),
]


def create_roles(apps, schema_editor):
    Role = apps.get_model("users", "Role")
    for name, description in ROLES:
        Role.objects.update_or_create(
            name=name,
            defaults={"description": description, "is_active": True},
        )


def remove_roles(apps, schema_editor):
    Role = apps.get_model("users", "Role")
    Role.objects.filter(name__in=[name for name, _ in ROLES]).delete()


class Migration(migrations.Migration):
    dependencies = [
        ("users", "0001_initial"),
    ]

    operations = [
        migrations.RunPython(create_roles, remove_roles),
    ]
