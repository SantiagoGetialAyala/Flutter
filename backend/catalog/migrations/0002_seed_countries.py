from django.db import migrations


COUNTRIES = [
    ("Alemania", "DE"),
    ("Belgica", "BE"),
    ("Espana", "ES"),
    ("Francia", "FR"),
    ("Italia", "IT"),
    ("Paises Bajos", "NL"),
    ("Portugal", "PT"),
]


def create_countries(apps, schema_editor):
    Country = apps.get_model("catalog", "Country")
    for name, code in COUNTRIES:
        Country.objects.update_or_create(
            code=code,
            defaults={"name": name, "is_active": True},
        )


def remove_countries(apps, schema_editor):
    Country = apps.get_model("catalog", "Country")
    Country.objects.filter(code__in=[code for _, code in COUNTRIES]).delete()


class Migration(migrations.Migration):
    dependencies = [("catalog", "0001_initial")]

    operations = [migrations.RunPython(create_countries, remove_countries)]
