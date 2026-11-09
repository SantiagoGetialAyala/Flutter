import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/services/api_client.dart';
import 'package:frontend/features/workspace/record_form.dart';

class FourRolesApi extends ApiClient {
  @override
  Future<List<Map<String, dynamic>>> getAll(String path) async => [
    {
      'id': 'administrador',
      'name': 'Administrador',
      'description':
          'Invita al equipo y gestiona exportaciones, documentos y pagos.',
    },
    {
      'id': 'productor',
      'name': 'Productor',
      'description': 'Registra sus fincas, cosechas y lotes.',
    },
    {
      'id': 'logistica',
      'name': 'Transportador',
      'description':
          'Registra recogida, salida y entrega de sus envíos asignados.',
    },
    {
      'id': 'importador',
      'name': 'Importador',
      'description': 'Consulta sus pedidos y confirma la recepción.',
    },
  ];
}

void main() {
  testWidgets(
    'invitation shows four roles and explains the selected responsibility',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RecordForm(
              api: FourRolesApi(),
              module: {
                'key': 'invitations',
                'label': 'Invitar personas',
                'fields': [
                  {
                    'key': 'role',
                    'label': 'Rol',
                    'type': 'relation',
                    'endpoint': 'role-options',
                    'required': true,
                  },
                ],
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final field = find.byType(DropdownButtonFormField<String>);
      final dropdown = tester.widget<DropdownButton<String>>(
        find.descendant(
          of: field,
          matching: find.byType(DropdownButton<String>),
        ),
      );
      expect(dropdown.items!.map((item) => item.value), [
        'administrador',
        'productor',
        'logistica',
        'importador',
      ]);
      await tester.tap(field);
      await tester.pumpAndSettle();
      for (final label in [
        'Administrador',
        'Productor',
        'Transportador',
        'Importador',
      ]) {
        expect(find.text(label).last, findsOneWidget);
      }
      expect(find.text('Comercial'), findsNothing);
      expect(find.text('Financiero'), findsNothing);
      expect(find.text('Gerencia'), findsNothing);
      await tester.tap(find.text('Transportador').last);
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Registra recogida, salida y entrega de sus envíos asignados.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
