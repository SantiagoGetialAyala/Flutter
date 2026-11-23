import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ('business', '0002_align_order_quantity_precision'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.AlterField(
            model_name='order',
            name='export',
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.PROTECT,
                related_name='orders',
                to='operations.exportoperation',
            ),
        ),
        migrations.AlterField(
            model_name='order',
            name='reference',
            field=models.CharField(blank=True, max_length=100),
        ),
        migrations.AlterField(
            model_name='order',
            name='description',
            field=models.TextField(blank=True),
        ),
        migrations.AddField(
            model_name='order',
            name='requested_by',
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.PROTECT,
                related_name='import_requests',
                to=settings.AUTH_USER_MODEL,
            ),
        ),
        migrations.AddField(
            model_name='order',
            name='product_type',
            field=models.CharField(
                choices=[('cafe', 'Café'), ('cacao', 'Cacao')],
                default='cafe',
                max_length=20,
            ),
        ),
        migrations.AddField(
            model_name='order',
            name='destination_country',
            field=models.CharField(blank=True, max_length=100),
        ),
        migrations.AddField(
            model_name='order',
            name='requested_document_1',
            field=models.CharField(blank=True, max_length=150),
        ),
        migrations.AddField(
            model_name='order',
            name='requested_document_2',
            field=models.CharField(blank=True, max_length=150),
        ),
        migrations.AddField(
            model_name='order',
            name='requested_document_3',
            field=models.CharField(blank=True, max_length=150),
        ),
    ]
