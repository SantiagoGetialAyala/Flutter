from django.db import migrations


def align_destinations(apps, schema_editor):
    # Destinations were stored as text before the country selector existed.
    # Keep destination-specific requirements aligned with the updated catalog.
    for app, model in [('operations', 'ExportOperation'), ('business', 'Requirement')]:
        records = apps.get_model(app, model).objects.using(schema_editor.connection.alias)
        for previous, current in [('Espana', 'España'), ('Belgica', 'Bélgica'), ('Paises Bajos', 'Países Bajos')]:
            records.filter(destination_country__iexact=previous).update(destination_country=current)


class Migration(migrations.Migration):
    dependencies = [
        ('catalog', '0006_eu_destinations'),
        ('operations', '0006_producer_user'),
        ('business', '0001_initial'),
    ]
    operations = [migrations.RunPython(align_destinations, migrations.RunPython.noop)]
