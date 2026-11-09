import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/services/api_client.dart';
import 'package:frontend/features/workspace/finance_report.dart';
import 'package:frontend/features/workspace/presentation.dart';

class ReportApi extends ApiClient {
  final calls = <String>[];
  @override
  Future<Map<String, dynamic>> getMap(String path) async {
    calls.add(path);
    return {
      'operations': [
        {
          'export': path.endsWith('=7') ? 7 : 8,
          'currency': 'EUR',
          'ingreso': path.endsWith('=7') ? 2500 : 1000,
          'costo': 300,
          'presupuesto': 0,
        },
      ],
    };
  }
}

void main() {
  testWidgets(
    'dossier report requests its export and refreshes when the export changes',
    (tester) async {
      final api = ReportApi();
      Future<void> open(int exportId) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: FinanceReport(api: api, revision: 1, exportId: exportId),
            ),
          ),
        ),
      );
      await open(7);
      await tester.pumpAndSettle();
      expect(api.calls, ['/finance/report/?export=7']);
      expect(find.text(number(2200)), findsOneWidget);
      await open(8);
      await tester.pumpAndSettle();
      expect(api.calls.last, '/finance/report/?export=8');
      expect(find.text(number(700)), findsOneWidget);
      expect(find.text(number(2200)), findsNothing);
    },
  );
}
