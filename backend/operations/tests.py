from datetime import date

from django.test import TestCase
from rest_framework.test import APIClient

from catalog.models import Client, Country
from users.models import Membership, Organization, Role, User
from .models import ProductLot


class OperationsApiTests(TestCase):
    def setUp(self):
        admin_role, _ = Role.objects.get_or_create(name=Role.ADMINISTRADOR)
        self.organization = Organization.objects.create(name="Cooperativa de prueba")
        self.user = User.objects.create_user(email="ops-admin@test.local", password="PruebaSegura123", role=admin_role)
        Membership.objects.create(user=self.user, organization=self.organization, role=admin_role)
        self.client = APIClient()
        self.client.force_authenticate(self.user)
        self.client.credentials(HTTP_X_ORGANIZATION_ID=str(self.organization.pk))

    def create_lot(self, quantity="100"):
        producer = self.client.post("/api/producers/", {"name": "Productor de prueba"}, format="json")
        self.assertEqual(producer.status_code, 201, producer.data)
        lot = self.client.post("/api/lots/", {
            "producer": producer.data["id"], "code": "CAFE-001", "product_type": "cafe",
            "quantity_initial": quantity, "unit": "kg", "variety": "Castillo",
        }, format="json")
        self.assertEqual(lot.status_code, 201, lot.data)
        return lot.data

    def test_origin_chain_and_geojson_are_persisted(self):
        producer = self.client.post("/api/producers/", {"name": "Finca Origen"}, format="json")
        farm = self.client.post("/api/farms/", {
            "producer": producer.data["id"], "code": "FIN-01", "name": "La Esperanza", "area": "12.500",
        }, format="json")
        crop = self.client.post("/api/crops/", {
            "farm": farm.data["id"], "name": "Café Castillo", "product_type": "cafe", "variety": "Castillo", "planted_area": "2.250",
        }, format="json")
        self.assertEqual(crop.status_code, 201, crop.data)
        plot = self.client.post("/api/plots/", {
            "farm": farm.data["id"], "crop": crop.data["id"], "code": "PAR-01", "area": "2.250", "crop_type": "cafe",
            "geometry": {"type": "Point", "coordinates": [-75.5, 6.2]},
        }, format="json")
        self.assertEqual(plot.status_code, 201, plot.data)
        harvest = self.client.post("/api/harvests/", {
            "plot": plot.data["id"], "harvest_date": date.today().isoformat(),
            "product_type": "cafe", "quantity": "250", "unit": "kg",
        }, format="json")
        self.assertEqual(harvest.status_code, 201, harvest.data)
        lot = self.client.post("/api/lots/", {
            "producer": producer.data["id"], "harvest": harvest.data["id"], "code": "LOTE-01",
            "product_type": "cafe", "quantity_initial": "250", "unit": "kg",
        }, format="json")
        self.assertEqual(lot.status_code, 201, lot.data)
        self.assertEqual(lot.data["quantity_available"], "250.000")

    def test_invalid_geojson_is_rejected(self):
        producer = self.client.post("/api/producers/", {"name": "Productor"}, format="json")
        farm = self.client.post("/api/farms/", {"producer": producer.data["id"], "code": "F1", "name": "Finca", "area": "1"}, format="json")
        response = self.client.post("/api/plots/", {
            "farm": farm.data["id"], "code": "P1", "area": "1", "crop_type": "cafe",
            "geometry": {"type": "Point", "coordinates": [-250, 6]},
        }, format="json")
        self.assertEqual(response.status_code, 400)

    def test_inventory_cannot_become_negative(self):
        lot = self.create_lot("25")
        response = self.client.post("/api/inventory-movements/", {
            "lot": lot["id"], "movement_type": "salida", "quantity": "26",
        }, format="json")
        self.assertEqual(response.status_code, 400)
        self.assertEqual(ProductLot.objects.get(pk=lot["id"]).quantity_available, 25)

    def test_lot_transformation_updates_both_balances_and_traceability(self):
        source = self.create_lot("100")
        producer_id = source["producer"]
        target = self.client.post("/api/lots/", {
            "producer": producer_id, "code": "CAFE-002", "product_type": "cafe",
            "quantity_initial": "0", "unit": "kg",
        }, format="json")
        self.assertEqual(target.status_code, 201, target.data)
        response = self.client.post("/api/lot-relationships/", {
            "source_lot": source["id"], "target_lot": target.data["id"],
            "relation_type": "transformacion", "quantity": "50", "output_quantity": "48",
        }, format="json")
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(ProductLot.objects.get(pk=source["id"]).quantity_available, 50)
        self.assertEqual(ProductLot.objects.get(pk=target.data["id"]).quantity_available, 48)

    def test_export_allocation_reserves_inventory_and_rejects_excess(self):
        lot = self.create_lot("30")
        country, _ = Country.objects.get_or_create(code="DE", defaults={"name": "Alemania"})
        client = Client.objects.create(business_name="Importador", email="buyer@test.local", country=country, organization=self.organization)
        export = self.client.post("/api/exports/", {
            "code": "EXP-001", "importer": client.pk, "destination_country": "Alemania",
        }, format="json")
        self.assertEqual(export.status_code, 201, export.data)
        too_much = self.client.post("/api/export-allocations/", {
            "export": export.data["id"], "lot": lot["id"], "quantity": "31", "unit": "kg",
        }, format="json")
        self.assertEqual(too_much.status_code, 400)
        reservation = self.client.post("/api/export-allocations/", {
            "export": export.data["id"], "lot": lot["id"], "quantity": "20", "unit": "kg",
        }, format="json")
        self.assertEqual(reservation.status_code, 201, reservation.data)
        self.assertEqual(ProductLot.objects.get(pk=lot["id"]).quantity_available, 10)

    def test_export_status_cannot_skip_required_steps(self):
        country = Country.objects.create(name="País destino", code="ZZ")
        client = Client.objects.create(business_name="Comprador", email="buyer2@test.local", country=country, organization=self.organization)
        export = self.client.post("/api/exports/", {
            "code": "EXP-002", "importer": client.pk, "destination_country": "Alemania",
        }, format="json")
        response = self.client.post(f"/api/exports/{export.data['id']}/transition/", {"status": "embarcada"}, format="json")
        self.assertEqual(response.status_code, 400)
        self.assertIn("Transición no permitida desde borrador.", str(response.data["status"]))

    def test_organization_membership_is_required(self):
        other_role, _ = Role.objects.get_or_create(name=Role.COMERCIAL)
        other = User.objects.create_user(email="outsider@test.local", password="PruebaSegura123", role=other_role)
        self.client.force_authenticate(other)
        response = self.client.get("/api/producers/")
        self.assertEqual(response.status_code, 403)

    def test_importer_membership_cannot_read_internal_origin_records(self):
        importer_role, _ = Role.objects.get_or_create(name=Role.IMPORTADOR)
        importer = User.objects.create_user(email="buyer-role@test.local", password="PruebaSegura123", role=importer_role)
        Membership.objects.create(user=importer, organization=self.organization, role=importer_role)
        self.client.force_authenticate(importer)
        response = self.client.get("/api/producers/")
        self.assertEqual(response.status_code, 403)
