import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/services/api_client.dart';
import 'package:frontend/core/theme/app_theme.dart';
import 'package:frontend/features/auth/models/auth_user.dart';
import 'package:frontend/features/workspace/workspace_screen.dart';
import 'package:frontend/features/workspace/operation_map.dart';
import 'package:frontend/features/workspace/workflow.dart';

Map<String, dynamic> field(
  String key,
  String label, {
  String type = 'text',
  String? endpoint,
  bool required = true,
}) => {
  'key': key,
  'label': label,
  'type': type,
  'required': required,
  'endpoint': ?endpoint,
};
Map<String, dynamic> descriptor(
  String key, {
  bool create = false,
  List<Map<String, dynamic>> fields = const [],
}) => {
  'key': key,
  'label':
      {
        'exports': 'Exportaciones',
        'lots': 'Lotes',
        'documents': 'Documentos',
        'activities': 'Actividades',
        'export-allocations': 'Reservas de lotes',
      }[key] ??
      key,
  'permissions': [
    'view',
    if (create) ...['create', 'update', 'submit'],
  ],
  'can_create': create,
  'can_update': create,
  'can_report': false,
  'actions': [],
  'fields': fields,
};

class RedesignApi extends ApiClient {
  RedesignApi(this.role);
  final String role;
  final calls = <String>[];
  final writes = <Map<String, dynamic>>[];
  String? org;
  bool failTasks = false;
  bool partialPanel = false;
  List<Map<String, dynamic>> pending = [];
  final export = <String, dynamic>{
    'id': 7,
    'code': 'EXP-7',
    'status': 'borrador',
    'destination_country': 'Alemania',
    'importer': 1,
    'importer_name': 'Cliente real',
    'allocations': [],
    'allowed_transitions': ['pendiente_documentacion', 'cancelada'],
  };
  @override
  Future<String?> get activeOrganizationId async => org;
  @override
  Future<void> setActiveOrganization(String? id) async {
    org = id;
  }

  List<Map<String, dynamic>> get tools {
    if (role != 'exportaciones') {
      return [for (final key in workModules(role)) descriptor(key)];
    }
    return [
      descriptor(
        'exports',
        create: true,
        fields: [
          field('code', 'Código'),
          field('importer', 'Cliente', type: 'relation', endpoint: 'clients'),
          field('destination_country', 'País de destino'),
          field('commercial_terms', 'Condiciones comerciales', required: false),
        ],
      ),
      descriptor('lots'),
      descriptor('documents'),
      descriptor(
        'activities',
        create: true,
        fields: [
          field('title', 'Título'),
          field('completed', 'Completada', type: 'bool', required: false),
        ],
      ),
      descriptor(
        'export-allocations',
        create: true,
        fields: [
          field('export', 'Exportación', type: 'relation', endpoint: 'exports'),
          field('lot', 'Lote', type: 'relation', endpoint: 'lots'),
          field('quantity', 'Cantidad', type: 'number'),
        ],
      ),
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> getAll(String path) async {
    calls.add(path);
    if (path == '/organizations/') {
      return [
        {'id': 1, 'name': 'Empresa uno'},
      ];
    }
    if (path == '/clients/') {
      return [
        {'id': 1, 'business_name': 'Cliente real'},
      ];
    }
    if (path == '/lots/') {
      return [
        {'id': 9, 'code': 'LOTE-9'},
      ];
    }
    if (path == '/exports/') return [export];
    return [];
  }

  @override
  Future<Map<String, dynamic>> getMap(String path) async {
    calls.add(path);
    if (path == '/workspace/') {
      if (failTasks) {
        throw const ApiException('Servidor temporalmente no disponible.');
      }
      return {
        'role': role,
        'role_label': friendlyRole(role),
        'organization': 'Empresa uno',
        'modules': tools,
        'metrics': [
          for (var i = 0; i < 8; i++)
            {'label': 'Indicador $i', 'value': i, 'module': tools.first['key']},
        ],
        'panels': partialPanel
            ? [
                {
                  'label': 'Operaciones recientes',
                  'module': 'exports',
                  'items': [
                    {'id': 7, 'code': 'EXP-7', 'status': 'borrador'},
                  ],
                },
              ]
            : [],
        'recent_activity': [],
        'pending_tasks': pending,
        'contexts': [
          {
            'organization_id': 1,
            'organization__name': 'Empresa uno',
            'role__name': role,
          },
        ],
      };
    }
    if (path == '/activities/3/') {
      return {'id': 3, 'title': 'Revisar factura', 'completed': false};
    }
    if (path == '/exports/7/') return export;
    if (path.startsWith('/exports/?')) {
      return {
        'count': 1,
        'results': [export],
      };
    }
    return {'count': 0, 'results': []};
  }

  @override
  Future<Map<String, dynamic>> patch(
    String path,
    Map<String, dynamic> data,
  ) async {
    writes.add({'path': path, ...data});
    pending = [];
    return {'id': 3, ...data};
  }

  @override
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> data,
  ) async {
    calls.add(path);
    writes.add({'path': path, ...data});
    return path == '/exports/' ? {...export, ...data} : {'id': 10, ...data};
  }
}

String friendlyRole(String role) => {
  'productor': 'Productor',
  'exportaciones': 'Gestor',
  'documental': 'Documental',
  'logistica': 'Transportador',
  'financiero': 'Financiero',
  'importador': 'Importador',
  'administrador': 'Administrador empresarial',
  'superadmin': 'Superadministrador',
}[role]!;

Future<void> mount(
  WidgetTester tester,
  RedesignApi api, {
  Size size = const Size(360, 780),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: WorkspaceScreen(
          api: api,
          user: AuthUser(
            id: 1,
            email: 'user@test.local',
            fullName: 'Ana Pérez',
            role: api.role,
            roleDisplay: friendlyRole(api.role),
            isPlatform: api.role == 'superadmin',
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder nav(String label) =>
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

void main() {
  for (final role in [
    'productor',
    'exportaciones',
    'documental',
    'logistica',
    'financiero',
    'importador',
    'administrador',
    'superadmin',
  ]) {
    testWidgets(
      '$role has five destinations and a real work context on a small phone',
      (tester) async {
        final api = RedesignApi(role);
        await mount(tester, api);
        expect(find.byType(NavigationDestination), findsNWidgets(5));
        expect(nav(workLabel(role)), findsOneWidget);
        expect(find.text('Indicador 5'), findsNothing);
        await tester.tap(nav('Perfil'));
        await tester.pumpAndSettle();
        expect(find.text('Rol activo: ${friendlyRole(role)}'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('create a draft then reserve a lot inside the same dossier', (
    tester,
  ) async {
    final api = RedesignApi('exportaciones');
    await mount(tester, api);
    await tester.tap(nav('Operaciones'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nueva exportación'));
    await tester.pumpAndSettle();
    expect(find.text('Iniciar operación'), findsOneWidget);
    await tester.tap(find.text('Guardar borrador'));
    await tester.pumpAndSettle();
    expect(api.writes, isEmpty);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Código *'),
      'EXP-7',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'País de destino *'),
      'Alemania',
    );
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cliente real').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar borrador'));
    await tester.pumpAndSettle();
    expect(api.writes.single['path'], '/exports/');
    expect(api.writes.single['importer'], 1);
    expect(find.text('Etapa 1 de 5'), findsOneWidget);
    expect(find.text('Plan de trabajo · 5 etapas'), findsOneWidget);
    await tester.tap(find.text('Plan de trabajo · 5 etapas'));
    await tester.pumpAndSettle();
    for (final stage in lifecycleStages) {
      expect(find.text(stage), findsOneWidget);
    }
    for (final guide in lifecycleGuides) {
      expect(find.text(guide), findsOneWidget);
    }
    await tester.tap(find.text('Preparar productos y lotes'));
    await tester.pumpAndSettle();
    expect(find.text('Productos y lotes reservados'), findsOneWidget);
    expect(find.text('1. Pedido y mercancía'), findsOneWidget);
    expect(find.text('Opciones adicionales'), findsOneWidget);
    expect(find.text('Tareas y solicitudes al equipo'), findsNothing);
    await tester.ensureVisible(find.text('Reservar lote'));
    await tester.tap(find.text('Reservar lote'));
    await tester.pumpAndSettle();
    // The export is bound to this dossier and cannot be switched in the form.
    expect(
      find.widgetWithText(DropdownButtonFormField<String>, 'Exportación *'),
      findsNothing,
    );
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('LOTE-9').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Cantidad *'),
      '12',
    );
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(api.writes.last, {
      'path': '/export-allocations/',
      'export': 7,
      'lot': 9,
      'quantity': '12',
    });
    expect(api.calls, contains('/documents/?export=7'));
    expect(
      api.calls.where((c) => c.contains('finance') || c.contains('vehicles')),
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('returning to work restores its search', (tester) async {
    final api = RedesignApi('exportaciones');
    await mount(tester, api);
    await tester.tap(nav('Operaciones'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'EXP-7');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(nav('Perfil'));
    await tester.pumpAndSettle();
    await tester.tap(nav('Operaciones'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'EXP-7',
    );
    expect(api.calls.last, contains('search=EXP-7'));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'map requests only tools permitted to an importer and invents no position',
    (tester) async {
      final api = RedesignApi('importador');
      await mount(tester, api);
      await tester.tap(nav('Mapa'));
      await tester.pumpAndSettle();
      expect(find.text('Aún no hay coordenadas registradas'), findsOneWidget);
      expect(api.calls, isNot(contains('/plots/')));
      expect(api.calls, isNot(contains('/traceability-events/')));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a recent operation loads its complete dossier before opening', (
    tester,
  ) async {
    final api = RedesignApi('exportaciones')..partialPanel = true;
    await mount(tester, api);
    await tester.scrollUntilVisible(
      find.text('EXP-7'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('EXP-7'));
    await tester.pumpAndSettle();
    expect(api.calls, contains('/exports/7/'));
    expect(find.text('Cliente real'), findsOneWidget);
    expect(find.text('Etapa 1 de 5'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a transport assignment opens its next permitted event directly',
    (tester) async {
      final api = LogisticsActionApi()
        ..pending = [
          {
            'id': 'transports:4',
            'module': 'transports',
            'record_id': 4,
            'title': 'Recoger carga',
            'status': 'asignado',
            'overdue': false,
          },
        ];
      await mount(tester, api);
      await tester.tap(nav('Tareas'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Recoger carga'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Registrar avance'));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(DropdownButtonFormField<String>, 'Transporte *'),
        findsNothing,
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      expect(find.text('Recogida'), findsOneWidget);
      expect(find.text('Entrega'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('an assigned task opens its real record and can be completed', (
    tester,
  ) async {
    final api = RedesignApi('exportaciones')
      ..pending = [
        {
          'id': 'activities:3',
          'module': 'activities',
          'record_id': 3,
          'title': 'Revisar factura',
          'status': 'pendiente',
          'overdue': true,
          'due_at': '2026-01-01T10:00:00Z',
        },
      ];
    await mount(tester, api);
    await tester.tap(nav('Tareas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Revisar factura'));
    await tester.pumpAndSettle();
    expect(api.calls, contains('/activities/3/'));
    await tester.tap(find.text('Editar').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(api.writes.last, {
      'path': '/activities/3/',
      'title': 'Revisar factura',
      'completed': true,
    });
    await tester.tap(nav('Tareas'));
    await tester.pumpAndSettle();
    expect(find.text('Sin pendientes en esta vista'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'registered parcel geometry renders and opens coordinate details',
    (tester) async {
      final api = ParcelApi();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: OperationMap(api: api, modules: const {'plots', 'farms'}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Parcela · Finca Sierra'), findsNothing);
      await tester.tap(find.text('P-1'));
      await tester.pumpAndSettle();
      expect(find.text('Parcela · Finca Sierra'), findsOneWidget);
      expect(find.textContaining('Longitud: -76.600000'), findsOneWidget);
      expect(find.textContaining('No es seguimiento GPS'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'GeoJSON preserves longitude/latitude and rejects invalid coordinates',
    () {
      expect(
        geoCoordinates({
          'type': 'Point',
          'coordinates': [-76.6, 1.2],
        }),
        [const Offset(-76.6, 1.2)],
      );
      expect(
        geoCoordinates({
          'type': 'Point',
          'coordinates': [1000, 1.2],
        }),
        isEmpty,
      );
      expect(
        geoCoordinates({
          'type': 'Feature',
          'geometry': {
            'type': 'Polygon',
            'coordinates': [
              [
                [-76, 1],
                [-75, 1],
                [-75, 2],
                [-76, 1],
              ],
            ],
          },
        }).length,
        4,
      );
      expect(geoCoordinates(eventGeometry({'lat': 1.2, 'lng': -76.6})), [
        const Offset(-76.6, 1.2),
      ]);
      expect(
        geoCoordinates(eventGeometry({'name': 'Puerto de destino'})),
        isEmpty,
      );
    },
  );
}

class ParcelApi extends ApiClient {
  @override
  Future<List<Map<String, dynamic>>> getAll(String path) async =>
      path == '/farms/'
      ? [
          {'id': 2, 'name': 'Finca Sierra'},
        ]
      : [
          {
            'id': 1,
            'code': 'P-1',
            'farm': 2,
            'geometry': {
              'type': 'Polygon',
              'coordinates': [
                [
                  [-76.6, 1.2],
                  [-76.59, 1.2],
                  [-76.59, 1.21],
                  [-76.6, 1.2],
                ],
              ],
            },
          },
        ];
}

class LogisticsActionApi extends RedesignApi {
  LogisticsActionApi() : super('logistica');
  @override
  List<Map<String, dynamic>> get tools => [
    {...descriptor('transports'), 'can_update': true},
    descriptor(
      'transport-events',
      create: true,
      fields: [
        field(
          'transport',
          'Transporte',
          type: 'relation',
          endpoint: 'transports',
        ),
        {
          ...field('event_type', 'Tipo de avance', type: 'choice'),
          'choices': [
            {'value': 'recogida', 'label': 'Recogida'},
            {'value': 'inicio', 'label': 'Inicio'},
            {'value': 'entrega', 'label': 'Entrega'},
            {'value': 'seguimiento', 'label': 'Seguimiento'},
            {'value': 'incidencia', 'label': 'Incidencia'},
          ],
        },
      ],
    ),
  ];
  @override
  Future<Map<String, dynamic>> getMap(String path) async =>
      path == '/transports/4/'
      ? {
          'id': 4,
          'export': 7,
          'status': 'asignado',
          'pickup_place': 'Finca',
          'delivery_place': 'Bodega',
        }
      : super.getMap(path);
}
