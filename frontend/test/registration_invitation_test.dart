import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/routes/app_router.dart';
import 'package:frontend/core/services/api_client.dart';
import 'package:frontend/core/services/auth_service.dart';
import 'package:frontend/features/auth/screens/register_screen.dart';

class InvitationApi extends ApiClient {
  Map<String, dynamic>? registration;
  bool tokensSaved = false;
  String? requestPath;

  @override
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> data,
  ) async {
    requestPath = path;
    registration = data;
    return {
      'access': 'access-token',
      'refresh': 'refresh-token',
      'user': {
        'id': 1,
        'email': data['email'],
        'role': path == '/auth/register/' ? 'productor' : 'administrador',
      },
    };
  }

  @override
  Future<void> saveTokens(String access, String refresh) async {
    tokensSaved = true;
  }
}

void main() {
  testWidgets(
    'invitation registration enters company without choosing a role',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = InvitationApi();
      await tester.pumpWidget(
        MaterialApp(
          home: RegisterScreen(authService: AuthService(apiClient: api)),
          routes: {
            AppRoutes.dashboard: (_) =>
                const Scaffold(body: Text('Mi empresa')),
          },
        ),
      );
      expect(
        find.widgetWithText(DropdownButtonFormField<String>, 'Tipo de cuenta'),
        findsNothing,
      );
      expect(find.widgetWithText(TextFormField, 'Código de invitación'), findsNothing);
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Correo'),
        'productor@empresa.test',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Contraseña'),
        'Fuerte-y-segura-739!',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirmar contraseña'),
        'Fuerte-y-segura-739!',
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Crear cuenta'));
      await tester.pumpAndSettle();
      expect(api.requestPath, '/auth/register/');
      expect(api.registration!.containsKey('role'), isFalse);
      expect(api.registration!.containsKey('invitation_code'), isFalse);
      expect(api.registration?['email'], 'productor@empresa.test');
      expect(api.tokensSaved, isTrue);
      expect(find.text('Mi empresa'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'registration requires the invited email without asking for a code or role',
    (tester) async {
      final api = InvitationApi();
      await tester.pumpWidget(
        MaterialApp(
          home: RegisterScreen(authService: AuthService(apiClient: api)),
        ),
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Contraseña'),
        'Fuerte-y-segura-739!',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirmar contraseña'),
        'Fuerte-y-segura-739!',
      );
      final button = find.widgetWithText(ElevatedButton, 'Crear cuenta');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(
        find.text('Ingresa el correo.'),
        findsOneWidget,
      );
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(api.registration, isNull);
    },
  );

  testWidgets(
    'company registration is separate and creates its owner without choosing a role',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = InvitationApi();
      await tester.pumpWidget(
        MaterialApp(
          home: RegisterScreen(
            authService: AuthService(apiClient: api),
            createCompany: true,
          ),
          routes: {
            AppRoutes.dashboard: (_) =>
                const Scaffold(body: Text('Mi empresa')),
          },
        ),
      );
      expect(
        find.widgetWithText(TextFormField, 'Código de invitación'),
        findsNothing,
      );
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nombre de la empresa'),
        'Exportadora prueba',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Correo'),
        'admin@empresa.test',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Contraseña'),
        'Fuerte-y-segura-739!',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirmar contraseña'),
        'Fuerte-y-segura-739!',
      );
      await tester.tap(
        find.widgetWithText(ElevatedButton, 'Crear empresa y cuenta'),
      );
      await tester.pumpAndSettle();
      expect(api.requestPath, '/auth/register-company/');
      expect(api.registration?['company_name'], 'Exportadora prueba');
      expect(api.registration!.containsKey('role'), isFalse);
      expect(api.registration!.containsKey('invitation_code'), isFalse);
      expect(api.tokensSaved, isTrue);
      expect(find.text('Mi empresa'), findsOneWidget);
    },
  );
}
