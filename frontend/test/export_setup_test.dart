import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/services/api_client.dart';
import 'package:frontend/features/workspace/record_form.dart';

class SetupApi extends ApiClient {
  final clients = <Map<String, dynamic>>[];
  Map<String, dynamic>? saved;

  @override
  Future<List<Map<String, dynamic>>> getAll(String path) async => clients;

  @override
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> data,
  ) async {
    if (path == '/clients/') {
      final row = {'id': 7, ...data};
      clients.add(row);
      return row;
    }
    saved = data;
    return {'id': 9, ...data};
  }
}

Map<String, dynamic> field(String key, String label, String type) => {
  'key': key,
  'label': label,
  'type': type,
  'required': true,
};

Map<String, dynamic> module(
  String key,
  String label,
  List<Map<String, dynamic>> fields,
) => {'key': key, 'label': label, 'fields': fields, 'can_create': true};

Future<void> openForm(
  WidgetTester tester,
  SetupApi api,
  Map<String, dynamic> form, {
  List<Map<String, dynamic>> modules = const [],
}) async {
  tester.view.physicalSize = const Size(1000, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<bool>(
              context: context,
              builder: (_) =>
                  RecordForm(api: api, module: form, modules: modules),
            ),
            child: const Text('Abrir'),
          ),
        ),
      ),
    ),
  );
  if (form['key'] == 'farms') {
    await tester.runAsync(() async {
      await tester.tap(find.text('Abrir'));
      await tester.pump();
      await rootBundle.loadString('assets/data/colombia_municipalities.json');
    });
  } else {
    await tester.tap(find.text('Abrir'));
  }
  await tester.pumpAndSettle();
}

class FarmSetupApi extends SetupApi {
  @override
  Future<List<Map<String, dynamic>>> getAll(String path) async =>
      path == '/producers/'
      ? [
          {'id': 3, 'name': 'Pedro'},
        ]
      : super.getAll(path);
}

Future<void> choose(WidgetTester tester, String label, String value) async {
  final dropdown = find.widgetWithText(DropdownButtonFormField<String>, label);
  await tester.ensureVisible(dropdown);
  await tester.tap(dropdown);
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text(value).last);
  await tester.tap(find.text(value).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'farm combines surface, dependent municipality, location and its main parcel',
    (tester) async {
      final api = FarmSetupApi();
      await openForm(tester, api, module('farms', 'Fincas y parcelas', []));
      expect(find.text('Registrar finca y cultivo'), findsOneWidget);
      expect(find.text('Código'), findsNothing);
      expect(find.textContaining('No pudimos cargar'), findsNothing);
      expect(find.text('Productor: Pedro'), findsOneWidget);
      await choose(
        tester,
        'Unidad de superficie',
        'Kilómetros cuadrados (km²)',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Área total de la finca *'),
        '0.5',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nombre de la finca *'),
        'La Esperanza',
      );
      await choose(tester, 'Departamento *', 'Bogotá, D.C.');
      final municipality = tester.widget<DropdownButton<String>>(
        find.descendant(
          of: find.widgetWithText(
            DropdownButtonFormField<String>,
            'Municipio *',
          ),
          matching: find.byType(DropdownButton<String>),
        ),
      );
      expect(municipality.items!.map((item) => item.value).toList(), [
        'Bogotá, D.C.',
      ]);
      await choose(tester, 'Municipio *', 'Bogotá, D.C.');
      await choose(tester, '¿Qué cultivas? *', 'Café');
      await tester.tap(find.text('Guardar finca y parcelas'));
      await tester.pumpAndSettle();
      expect(api.saved, isNull);
      final manual = find.text('Ingresar coordenadas manualmente');
      await tester.ensureVisible(manual);
      await tester.tap(manual);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Latitud'),
        '4.60',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Longitud'),
        '-74.08',
      );
      await tester.tap(find.text('Guardar finca y parcelas'));
      await tester.pumpAndSettle();
      expect(api.saved!['area_unit'], 'km2');
      expect(api.saved!['producer'], 3);
      expect(api.saved!['department'], 'Bogotá, D.C.');
      expect(api.saved!['new_plots'], [
        {
          'name': 'Área principal',
          'area': '50.000',
          'crop_type': 'cafe',
          'geometry': {
            'type': 'Point',
            'coordinates': [-74.08, 4.60],
          },
        },
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'missing importer can be created without losing the export draft',
    (tester) async {
      final api = SetupApi();
      final client = module('clients', 'Importadores', [
        field('business_name', 'Razón social', 'text'),
      ]);
      final export = module('exports', 'Exportaciones', [
        field('code', 'Código', 'text'),
        {...field('importer', 'Importador', 'relation'), 'endpoint': 'clients'},
      ]);
      await openForm(tester, api, export, modules: [export, client]);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Código *'),
        'EXP-42',
      );
      expect(find.text('Falta registrar: Importadores.'), findsOneWidget);
      await tester.tap(find.text('Crear aquí: Importadores'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Razón social *'),
        'Comprador europeo',
      );
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(find.text('EXP-42'), findsOneWidget);
      expect(find.text('Comprador europeo'), findsOneWidget);
      await tester.tap(find.text('Guardar borrador'));
      await tester.pumpAndSettle();
      expect(api.saved, {'code': 'EXP-42', 'importer': 7});
    },
  );

  testWidgets(
    'parcel coordinates validate ranges and save longitude before latitude',
    (tester) async {
      final api = SetupApi();
      await openForm(
        tester,
        api,
        module('plots', 'Parcelas', [field('geometry', 'Ubicación', 'json')]),
      );
      await tester.tap(find.text('Ingresar coordenadas manualmente'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Latitud'),
        '91',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Longitud'),
        '-74.08',
      );
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(
        find.text('Ingresa una coordenada entre −90 y 90.'),
        findsOneWidget,
      );
      expect(api.saved, isNull);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Latitud'),
        '4.60',
      );
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(api.saved!['geometry'], {
        'type': 'Point',
        'coordinates': [-74.08, 4.6],
      });
    },
  );
}
