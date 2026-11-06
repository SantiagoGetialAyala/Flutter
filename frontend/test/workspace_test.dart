import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/services/api_client.dart';
import 'package:frontend/features/auth/models/auth_user.dart';
import 'package:frontend/features/workspace/workspace_screen.dart';

class WorkspaceApi extends ApiClient {
  WorkspaceApi(this.role);
  final String role;
  Map<String, dynamic>? saved;
  String? organization;
  @override
  Future<String?> get activeOrganizationId async => organization;
  @override
  Future<void> setActiveOrganization(String? id) async {
    organization = id;
  }

  @override
  Future<List<Map<String, dynamic>>> getAll(String path) async =>
      path == '/organizations/'
      ? [
          {'id': 1, 'name': 'Empresa de prueba'},
        ]
      : [];
  @override
  Future<Map<String, dynamic>> getMap(String path) async =>
      path == '/workspace/'
      ? {
          'role': role,
          'role_label': role == 'productor' ? 'Productor' : 'Importador',
          'organization': 'Empresa de prueba',
          'metrics': [
            {
              'label': role == 'productor'
                  ? 'Lotes activos'
                  : 'Pedidos activos',
              'value': 2,
            },
          ],
          'recent_activity': [],
          'modules': [
            {
              'key': role == 'productor' ? 'producers' : 'orders',
              'label': role == 'productor' ? 'Productores' : 'Pedidos',
              'permissions': role == 'productor'
                  ? ['view', 'create', 'update']
                  : ['view', 'submit'],
              'can_create': role == 'productor',
              'can_update': role == 'productor',
              'can_report': false,
              'actions': [],
              'fields': [
                {
                  'key': 'name',
                  'label': 'Nombre',
                  'required': true,
                  'nullable': false,
                  'type': 'text',
                },
              ],
            },
          ],
        }
      : RegExp(r'^/(producers|orders)/\d+/$').hasMatch(path)
      ? {
          'id': 3,
          'name': role == 'productor' ? 'Origen propio' : 'Pedido propio',
        }
      : {
          'results': [
            {
              'id': 3,
              'name': role == 'productor' ? 'Origen propio' : 'Pedido propio',
            },
          ],
          'count': 1,
        };
  @override
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> data,
  ) async {
    saved = data;
    return {'id': 4, ...data};
  }

  @override
  Future<Map<String, dynamic>> patch(
    String path,
    Map<String, dynamic> data,
  ) async {
    saved = data;
    return {'id': 3, ...data};
  }
}

Future<void> openWorkspace(WidgetTester tester, WorkspaceApi api) async {
  tester.view.physicalSize = const Size(1440, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: WorkspaceScreen(
          api: api,
          user: AuthUser(
            id: 1,
            email: 'demo@test.local',
            fullName: 'Demo',
            roleDisplay: api.role,
            role: api.role,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'importer sees orders and no internal business modules or create button',
    (tester) async {
      final api = WorkspaceApi('importador');
      await openWorkspace(tester, api);
      expect(find.text('Pedidos activos'), findsOneWidget);
      expect(find.text('Costos, ingresos y pagos'), findsNothing);
      expect(find.text('Productores'), findsNothing);
      await tester.tap(find.text('Pedidos').first);
      await tester.pumpAndSettle();
      expect(find.text('Pedido propio'), findsOneWidget);
      expect(find.text('Nuevo registro'), findsNothing);
      expect(find.text('Editar'), findsNothing);
    },
  );

  testWidgets('producer creates origin through the authorized form', (
    tester,
  ) async {
    final api = WorkspaceApi('productor');
    await openWorkspace(tester, api);
    expect(find.text('Lotes activos'), findsOneWidget);
    await tester.tap(find.text('Buscar en gestión'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Producción e inventario'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Productores').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nuevo productor'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(find.text('Este campo es obligatorio.'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nombre *'),
      'Nueva finca de origen',
    );
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(api.saved, {'name': 'Nueva finca de origen'});
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('existing authorized origin can be edited', (tester) async {
    final api = WorkspaceApi('productor');
    await openWorkspace(tester, api);
    await tester.tap(find.text('Buscar en gestión'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Producción e inventario'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Productores').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Editar'));
    await tester.pumpAndSettle();
    expect(find.text('Origen propio'), findsWidgets);
    await tester.enterText(find.byType(TextFormField), 'Origen actualizado');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(api.saved, {'name': 'Origen actualizado'});
  });
}
