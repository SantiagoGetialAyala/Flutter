from django.db import migrations


# https://european-union.europa.eu/principles-countries-history/eu-countries_en
COUNTRIES = [
    ('DE', 'Alemania'), ('AT', 'Austria'), ('BE', 'Bélgica'),
    ('BG', 'Bulgaria'), ('CY', 'Chipre'), ('HR', 'Croacia'),
    ('DK', 'Dinamarca'), ('SK', 'Eslovaquia'), ('SI', 'Eslovenia'),
    ('ES', 'España'), ('EE', 'Estonia'), ('FI', 'Finlandia'),
    ('FR', 'Francia'), ('GR', 'Grecia'), ('HU', 'Hungría'),
    ('IE', 'Irlanda'), ('IT', 'Italia'), ('LV', 'Letonia'),
    ('LT', 'Lituania'), ('LU', 'Luxemburgo'), ('MT', 'Malta'),
    ('NL', 'Países Bajos'), ('PL', 'Polonia'), ('PT', 'Portugal'),
    ('CZ', 'Chequia'), ('RO', 'Rumanía'), ('SE', 'Suecia'),
]


def seed(apps, schema_editor):
    Country = apps.get_model('catalog', 'Country')
    for code, name in COUNTRIES:
        Country.objects.using(schema_editor.connection.alias).update_or_create(
            code=code, defaults={'name': name, 'is_active': True})


class Migration(migrations.Migration):
    dependencies = [('catalog', '0005_client_user')]
    operations = [migrations.RunPython(seed, migrations.RunPython.noop)]
