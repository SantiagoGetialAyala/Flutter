from django.db import migrations


ROLES = [
    ("superadmin", "Superadministrador de plataforma"),
    ("productor", "Productor o proveedor agrícola"),
    ("documental", "Responsable documental y cumplimiento"),
    ("importador", "Cliente o importador europeo"),
]


def seed_roles(apps, schema_editor):
    Role = apps.get_model("users", "Role")
    for name, description in ROLES:
        Role.objects.update_or_create(name=name, defaults={"description": description, "is_active": True})


class Migration(migrations.Migration):
    dependencies = [("users", "0003_organization_alter_role_name_auditevent_membership")]
    operations = [migrations.RunPython(seed_roles, migrations.RunPython.noop)]
