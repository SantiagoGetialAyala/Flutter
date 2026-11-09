import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/services/api_client.dart';
import 'package:frontend/core/services/auth_service.dart';
import 'package:frontend/core/theme/app_theme.dart';
import 'package:frontend/features/auth/models/auth_user.dart';
import 'package:frontend/features/auth/screens/login_screen.dart';
import 'package:frontend/features/workspace/workspace_screen.dart';

const captureDesign = bool.fromEnvironment('CAPTURE_DESIGN');
const demoUser = AuthUser(
  id: 1,
  email: 'carlos@test.local',
  fullName: 'Carlos Martínez',
  roleDisplay: 'Gestor de exportaciones',
  role: 'exportaciones',
);

class DesignApi extends ApiClient {
  String? org;
  @override
  Future<String?> get activeOrganizationId async => org;
  @override
  Future<void> setActiveOrganization(String? id) async {
    org = id;
  }

  final exports = <Map<String, dynamic>>[
    {
      'id': 1,
      'code': 'EXP-2026-0042',
      'destination_country': 'Alemania',
      'origin_country': 'Colombia',
      'status': 'transito_internacional',
      'importer_name': 'EuroCafé GmbH',
      'net_weight': '12000',
      'estimated_departure': '2026-11-15',
      'estimated_arrival': '2026-12-02',
      'incoterm': 'FOB',
      'commercial_value': '48000',
      'currency': 'EUR',
      'allocations': [
        {
          'lot_id': 1,
          'lot_code': 'LOT-CAF-0345',
          'quantity': '12000',
          'unit': 'kg',
        },
      ],
    },
    {
      'id': 2,
      'code': 'EXP-2026-0039',
      'destination_country': 'Bélgica',
      'status': 'en_revision',
      'net_weight': '8000',
      'estimated_departure': '2026-11-20',
      'allocations': [],
    },
    {
      'id': 3,
      'code': 'EXP-2026-0038',
      'destination_country': 'Francia',
      'status': 'aprobada_despacho',
      'net_weight': '15000',
      'estimated_departure': '2026-11-10',
      'allocations': [],
    },
  ];
  Map<String, dynamic> module(String key, String label) => {
    'key': key,
    'label': label,
    'permissions': ['view'],
    'can_create': false,
    'can_update': false,
    'can_report': false,
    'fields': [],
    'actions': [],
  };
  @override
  Future<List<Map<String, dynamic>>> getAll(String path) async {
    if (path == '/organizations/') {
      return [
        {'id': 1, 'name': 'Café de Origen SAS', 'tax_id': '900.123.456'},
        {'id': 2, 'name': 'Cooperativa Andina', 'tax_id': '901.654.321'},
      ];
    }
    if (path.contains('/history/')) {
      return [
        {'new_status': 'borrador', 'created_at': '2026-11-01T14:00:00Z'},
        {
          'new_status': 'pendiente_documentacion',
          'created_at': '2026-11-02T15:20:00Z',
        },
        {'new_status': 'en_revision', 'created_at': '2026-11-03T16:00:00Z'},
        {
          'new_status': 'aprobada_despacho',
          'created_at': '2026-11-04T13:30:00Z',
        },
        {
          'new_status': 'transito_internacional',
          'created_at': '2026-11-05T14:10:00Z',
        },
      ];
    }
    if (path.contains('/documents/')) {
      return [
        {
          'id': 1,
          'title': 'Certificado de origen',
          'document_type': 'origen',
          'status': 'aprobado',
          'export': 1,
        },
      ];
    }
    return [];
  }

  @override
  Future<Map<String, dynamic>> getMap(String path) async {
    if (path == '/workspace/') {
      return {
        'role': 'exportaciones',
        'role_label': 'Gestor de exportaciones',
        'organization': org == '2'
            ? 'Cooperativa Andina'
            : 'Café de Origen SAS',
        'metrics': [
          {'label': 'Exportaciones activas', 'value': 24},
          {'label': 'Documentos pendientes', 'value': 6},
          {'label': 'En tránsito', 'value': 8},
          {'label': 'Completadas', 'value': 12},
          {'label': 'Lotes disponibles', 'value': 14},
        ],
        'modules': [
          module('exports', 'Exportaciones'),
          module('lots', 'Lotes e inventario'),
          module('documents', 'Documentos'),
          module('transports', 'Transportes'),
          module('clients', 'Clientes'),
          module('finance', 'Reportes'),
        ],
        'panels': [
          {
            'label': 'Exportaciones en curso',
            'module': 'exports',
            'items': exports.take(2).toList(),
          },
        ],
        'recent_activity': [
          {'action': 'export.created', 'created_at': '2026-11-04T14:30:00Z'},
        ],
      };
    }
    final detail = RegExp(r'^/exports/(\d+)/$').firstMatch(path);
    if (detail != null) {
      return exports.firstWhere((e) => '${e['id']}' == detail.group(1));
    }
    if (path.startsWith('/exports/')) return {'results': exports, 'count': 3};
    return {'results': [], 'count': 0};
  }
}

class FinanceDesignApi extends DesignApi {
  @override
  Future<Map<String, dynamic>> getMap(String path) async {
    if (path == '/finance/report/') {
      return {
        'operations': [
          {
            'export': 1,
            'currency': 'EUR',
            'ingreso': '48000',
            'costo': '2400',
            'presupuesto': '3000',
            'margin': '45600',
            'budget_variance': '-600',
          },
          {
            'export': 2,
            'currency': 'USD',
            'ingreso': '200',
            'costo': '100',
            'presupuesto': '150',
            'margin': '100',
            'budget_variance': '-50',
          },
        ],
        'pending_payments': 2,
      };
    }
    final data = await super.getMap(path);
    if (path == '/workspace/') {
      for (final module in data['modules']) {
        if (module['key'] == 'finance') module['can_report'] = true;
      }
    }
    return data;
  }
}

Future<void> capture(WidgetTester tester, String name) async {
  if (!captureDesign) return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('capture')),
    );
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory('../output/design');
    await directory.create(recursive: true);
    await File(
      '${directory.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> mount(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('capture'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light().copyWith(
          textTheme: AppTheme.light().textTheme.apply(
            fontFamily: 'PreviewArial',
          ),
          chipTheme: AppTheme.light().chipTheme.copyWith(
            labelStyle: const TextStyle(
              fontFamily: 'PreviewArial',
              fontSize: 12,
            ),
          ),
        ),
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    await precacheImage(
      const AssetImage('assets/images/origin-hero.jpg'),
      tester.element(find.byType(Scaffold).first),
    );
  });
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    if (captureDesign) {
      final font = File('/System/Library/Fonts/Supplemental/Arial.ttf');
      if (font.existsSync()) {
        final loader = FontLoader('PreviewArial')
          ..addFont(
            Future.value(ByteData.sublistView(await font.readAsBytes())),
          );
        await loader.load();
        await (FontLoader('Roboto')..addFont(
              Future.value(ByteData.sublistView(await font.readAsBytes())),
            ))
            .load();
      }
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    }
  });
  testWidgets(
    'mobile workspace navigation, detail tabs and organization switching',
    (tester) async {
      final api = DesignApi();
      await mount(tester, WorkspaceScreen(api: api, user: demoUser));
      expect(tester.takeException(), isNull);
      expect(find.byType(NavigationBar), findsOneWidget);
      await capture(tester, 'inicio-movil');
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Operaciones'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('EXP-2026-0042'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, 'exportaciones-movil');
      await tester.tap(find.text('EXP-2026-0042'));
      await tester.pumpAndSettle();
      expect(find.text('Resumen'), findsOneWidget);
      expect(find.text('Seguimiento'), findsOneWidget);
      expect(find.text('EuroCafé GmbH'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, 'detalle-exportacion');
      await tester.tap(find.text('Seguimiento'));
      await tester.pumpAndSettle();
      expect(find.text('Borrador'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, 'seguimiento-exportacion');
      await tester.tap(find.byIcon(Icons.arrow_back_ios_new).last);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Cambiar organización'));
      await tester.pumpAndSettle();
      expect(find.text('Cooperativa Andina'), findsOneWidget);
      await tester.tap(find.text('Cooperativa Andina'));
      await tester.pumpAndSettle();
      expect(api.org, '2');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('desktop workspace has grouped navigation without overflow', (
    tester,
  ) async {
    await mount(
      tester,
      WorkspaceScreen(api: DesignApi(), user: demoUser),
      size: const Size(1440, 960),
    );
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.widgetWithText(ListTile, 'Operaciones'), findsOneWidget);
    await capture(tester, 'inicio-escritorio');
    await tester.tap(find.text('Buscar en gestión'));
    await tester.pumpAndSettle();
    expect(find.text('Exportaciones y ventas'), findsOneWidget);
    expect(find.text('Documentación'), findsOneWidget);
    expect(find.text('Logística'), findsOneWidget);
    // Tools stay hidden until their group is opened.
    expect(find.widgetWithText(ListTile, 'Transportes'), findsNothing);
    await tester.tap(find.text('Logística'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Transportes'), findsOneWidget);
    await tester.tap(find.text('Documentación'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Transportes'), findsNothing);
    expect(find.widgetWithText(ListTile, 'Documentos'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await capture(tester, 'gestion-escritorio');
  });
  testWidgets('mobile tools sheet expands groups and opens a tool', (
    tester,
  ) async {
    await mount(tester, WorkspaceScreen(api: DesignApi(), user: demoUser));
    await tester.tap(find.byTooltip('Buscar en gestión'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Logística'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Transportes'), findsOneWidget);
    await tester.tap(find.text('Documentación'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Transportes'), findsNothing);
    await tester.tap(find.widgetWithText(ListTile, 'Documentos'));
    await tester.pumpAndSettle();
    expect(
      find.text('Herramientas y catálogos disponibles para tu rol'),
      findsNothing,
    );
    expect(
      find.text(
        'Sube los archivos de soporte, consulta sus versiones y revisa su aprobación.',
      ),
      findsOneWidget,
    );
    expect(find.text('Documentos'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
  testWidgets('login fits narrow mobile screens', (tester) async {
    await mount(
      tester,
      LoginScreen(authService: AuthService(apiClient: DesignApi())),
    );
    expect(find.text('Inicia sesión'), findsWidgets);
    expect(tester.takeException(), isNull);
    await capture(tester, 'acceso-movil');
    await tester.scrollUntilVisible(
      find.widgetWithText(ElevatedButton, 'Inicia sesión'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'platform login clears a stale company context without justification',
    (tester) async {
      final api = DesignApi()..org = '1';
      const user = AuthUser(
        id: 2,
        email: 'platform@test.local',
        fullName: 'Administrador',
        roleDisplay: 'Superadministrador',
        role: 'superadmin',
        isPlatform: true,
      );
      await mount(tester, WorkspaceScreen(api: api, user: user));
      expect(api.org, isNull);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('financial report separates currencies and renders on mobile', (
    tester,
  ) async {
    await mount(
      tester,
      WorkspaceScreen(api: FinanceDesignApi(), user: demoUser),
    );
    await tester.tap(find.byTooltip('Buscar en gestión'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Más herramientas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finanzas'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Costos y pagos'));
    await tester.pumpAndSettle();
    expect(find.text('48.000'), findsWidgets);
    expect(find.text('48.200'), findsNothing);
    expect(find.text('Costos e ingresos'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await capture(tester, 'reporte-financiero');
  });
}
