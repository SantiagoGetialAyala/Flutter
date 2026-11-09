import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:frontend/features/workspace/location_field.dart';

class PlacesBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) => throw UnsupportedError(key);
  @override
  Future<String> loadString(String key, {bool cache = true}) =>
      SynchronousFuture(
        jsonEncode([
          {
            'department': 'Bogotá, D.C.',
            'name': 'Bogotá, D.C.',
            'latitude': 4.649251,
            'longitude': -74.106992,
          },
          {
            'department': 'Antioquia',
            'name': 'Medellín',
            'latitude': 6.246631,
            'longitude': -75.581775,
          },
          {
            'department': 'Amazonas',
            'name': 'Leticia',
            'latitude': -4.2,
            'longitude': -69.9,
          },
        ]),
      );
}

class LocalTiles extends TileProvider {
  final image = MemoryImage(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGP4DwQACfsD/fteaysAAAAASUVORK5CYII=',
    ),
  );
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      image;
}

Future<void> openPicker(
  WidgetTester tester, {
  String label = 'Elegir ubicación en OpenStreetMap',
}) async {
  await tester.ensureVisible(find.text(label));
  await tester.tap(find.text(label));
  await tester.pump();
  await tester.pumpAndSettle();
}

Future<void> choosePlace(
  WidgetTester tester,
  String label,
  String value,
) async {
  final field = find.widgetWithText(DropdownButtonFormField<String>, label);
  await tester.ensureVisible(field);
  await tester.tap(field);
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text(value).last);
  await tester.tap(find.text(value).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'municipality centers the map but only an explicit tap and confirmation saves the farm point',
    (tester) async {
      Map<String, dynamic>? selected;
      tester.view.physicalSize = const Size(1100, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (_, child) =>
              DefaultAssetBundle(bundle: PlacesBundle(), child: child!),
          home: Scaffold(
            body: Form(
              child: LocationField(
                label: 'Ubicación de la finca',
                center: const LatLng(4.60, -74.08),
                tileProvider: LocalTiles(),
                onChanged: (value) => selected = value,
              ),
            ),
          ),
        ),
      );
      await openPicker(tester);
      expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
      final confirm = find.widgetWithText(FilledButton, 'Usar esta ubicación');
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      expect(selected, isNull);
      await tester.tapAt(tester.getCenter(find.byType(FlutterMap)));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(selected, isNull);
      expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      final point = pointFromGeometry(selected)!;
      expect(point.latitude, closeTo(4.60, .001));
      expect(point.longitude, closeTo(-74.08, .001));
      expect(find.byType(FlutterMap), findsNothing);
    },
  );

  testWidgets(
    'department filters municipalities and selected municipality moves the map without saving a fictitious parcel',
    (tester) async {
      Map<String, dynamic>? selected;
      tester.view.physicalSize = const Size(1100, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (_, child) =>
              DefaultAssetBundle(bundle: PlacesBundle(), child: child!),
          home: Scaffold(
            body: Form(
              child: LocationField(
                label: 'Ubicación de la parcela',
                tileProvider: LocalTiles(),
                onChanged: (value) => selected = value,
              ),
            ),
          ),
        ),
      );
      await openPicker(tester);
      await choosePlace(tester, 'Departamento de Colombia', 'Bogotá, D.C.');
      final municipalities = tester.widget<DropdownButton<String>>(
        find.descendant(
          of: find.widgetWithText(DropdownButtonFormField<String>, 'Municipio'),
          matching: find.byType(DropdownButton<String>),
        ),
      );
      expect(municipalities.items!.map((item) => item.value), ['Bogotá, D.C.']);
      await choosePlace(tester, 'Municipio', 'Bogotá, D.C.');
      final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
      expect(
        map.mapController!.camera.center.latitude,
        closeTo(4.649251, .000001),
      );
      expect(
        map.mapController!.camera.center.longitude,
        closeTo(-74.106992, .000001),
      );
      final confirm = find.widgetWithText(FilledButton, 'Usar esta ubicación');
      expect(selected, isNull);
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      await tester.tapAt(tester.getCenter(find.byType(FlutterMap)));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
      await choosePlace(tester, 'Departamento de Colombia', 'Antioquia');
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      await choosePlace(tester, 'Municipio', 'Medellín');
      await tester.tapAt(tester.getCenter(find.byType(FlutterMap)));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(pointFromGeometry(selected)!.latitude, closeTo(6.246631, .001));
      expect(pointFromGeometry(selected)!.longitude, closeTo(-75.581775, .001));
    },
  );

  testWidgets(
    'manual coordinates remain available and cancelling the map preserves them on a phone',
    (tester) async {
      Map<String, dynamic>? selected;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (_, child) =>
              DefaultAssetBundle(bundle: PlacesBundle(), child: child!),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Form(
                child: LocationField(
                  label: 'Ubicación de la parcela',
                  tileProvider: LocalTiles(),
                  department: 'Antioquia',
                  municipality: 'Medellín',
                  onChanged: (value) => selected = value,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Ingresar coordenadas manualmente'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Latitud'),
        '6.25',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Longitud'),
        '-75.58',
      );
      await tester.pumpAndSettle();
      await openPicker(tester, label: 'Cambiar ubicación en el mapa');
      expect(find.text('Antioquia'), findsOneWidget);
      expect(find.text('Medellín'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(selected, pointGeometry(const LatLng(6.25, -75.58)));
    },
  );
}
