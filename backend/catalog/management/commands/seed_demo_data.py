from django.core.management.base import BaseCommand

from catalog.models import Client, Country, Product
from users.models import Role, User


class Command(BaseCommand):
    help = "Crea datos demo no destructivos para probar roles y estadisticas."

    demo_password = "Ritech2026!"

    def handle(self, *args, **options):
        self._create_users()
        self._create_products()
        self._create_clients()

        self.stdout.write(self.style.SUCCESS("Datos demo listos."))
        self.stdout.write(f"Clave demo para todos los usuarios: {self.demo_password}")
        self.stdout.write(f"Usuarios: {User.objects.count()}")
        self.stdout.write(f"Productos: {Product.objects.count()}")
        self.stdout.write(f"Clientes: {Client.objects.count()}")

    def _create_users(self):
        demos = [
            ("admin.demo@ritech.local", Role.ADMINISTRADOR, "Ana", "Torres"),
            ("exportaciones.demo@ritech.local", Role.EXPORTACIONES, "Laura", "Rojas"),
            ("comercial.demo@ritech.local", Role.COMERCIAL, "Carlos", "Gomez"),
            ("logistica.demo@ritech.local", Role.LOGISTICA, "Marta", "Lopez"),
            ("financiero.demo@ritech.local", Role.FINANCIERO, "Diego", "Perez"),
            ("gerencia.demo@ritech.local", Role.GERENCIA, "Valentina", "Mejia"),
        ]

        for email, role_name, first_name, last_name in demos:
            role = Role.objects.get(name=role_name)
            user, created = User.objects.get_or_create(
                email=email,
                defaults={
                    "first_name": first_name,
                    "last_name": last_name,
                    "role": role,
                    "is_active": True,
                },
            )
            if created:
                user.set_password(self.demo_password)
                user.save(update_fields=["password"])
            elif user.role_id != role.id or not user.is_active:
                user.role = role
                user.is_active = True
                user.save(update_fields=["role", "is_active"])

    def _create_products(self):
        products = [
            ("Cafe Premium", "cafe", "Cafe especial listo para exportacion", 500, "kg"),
            ("Cacao Premium", "cacao", "Cacao seco seleccionado", 200, "kg"),
            ("Cafe Organico", "cafe", "Cafe organico de origen colombiano", 350, "kg"),
            ("Cacao Estandar", "cacao", "Cacao en grano para cliente industrial", 420, "kg"),
        ]

        for name, product_type, description, quantity, unit in products:
            Product.objects.get_or_create(
                name=name,
                defaults={
                    "product_type": product_type,
                    "description": description,
                    "quantity": quantity,
                    "unit": unit,
                    "is_active": True,
                },
            )

    def _create_clients(self):
        colombia = self._country("Colombia")
        alemania = self._country("Alemania") or colombia
        francia = self._country("Francia") or colombia

        clients = [
            (
                "Euro Coffee GmbH",
                "contacto@eurocoffee.de",
                "+49 30 1000 2000",
                "Berlin",
                alemania,
            ),
            (
                "Cacao France SAS",
                "contacto@cacaofrance.fr",
                "+33 1 2000 3000",
                "Paris",
                francia,
            ),
            (
                "Global Trade",
                "sales@globaltrade.co",
                "+57 1 555 2020",
                "Bogota",
                colombia,
            ),
        ]

        for business_name, email, phone, address, country in clients:
            Client.objects.get_or_create(
                business_name=business_name,
                defaults={
                    "email": email,
                    "phone": phone,
                    "address": address,
                    "country": country,
                    "is_active": True,
                },
            )

    def _country(self, name):
        return Country.objects.filter(name__icontains=name).first() or Country.objects.first()
