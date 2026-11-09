import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/services/api_client.dart';
import '../../../core/theme/app_theme.dart';
import 'presentation.dart';

class FinanceReport extends StatefulWidget {
  const FinanceReport({
    super.key,
    required this.api,
    required this.revision,
    this.exportId,
  });
  final ApiClient api;
  final int revision;
  final int? exportId;
  @override
  State<FinanceReport> createState() => _FinanceReportState();
}

class _FinanceReportState extends State<FinanceReport> {
  String get _path =>
      '/finance/report/${widget.exportId == null ? '' : '?export=${widget.exportId}'}';
  late Future<Map<String, dynamic>> _report = widget.api.getMap(_path);
  String? _currency;
  @override
  void didUpdateWidget(FinanceReport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision ||
        oldWidget.exportId != widget.exportId) {
      _report = widget.api.getMap(_path);
    }
  }

  double _n(dynamic value) => double.tryParse('$value') ?? 0;
  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: _report,
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return snapshot.hasError
            ? Text('No se pudo cargar el reporte: ${snapshot.error}')
            : const LinearProgressIndicator();
      }
      final operations = (snapshot.data!['operations'] as List? ?? [])
          .cast<Map<String, dynamic>>();
      if (operations.isEmpty) return const SizedBox.shrink();
      final currencies = operations
          .map((r) => '${r['currency']}')
          .toSet()
          .toList();
      final currency = currencies.contains(_currency)
          ? _currency!
          : currencies.first;
      final rows = operations.where((r) => r['currency'] == currency).toList();
      final revenue = rows.fold<double>(0, (v, r) => v + _n(r['ingreso']));
      final cost = rows.fold<double>(0, (v, r) => v + _n(r['costo']));
      final budget = rows.fold<double>(0, (v, r) => v + _n(r['presupuesto']));
      final data = [
        ('Ingresos registrados', revenue),
        ('Costos acumulados', cost),
        ('Margen de operación', revenue - cost),
        ('Presupuesto', budget),
      ];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Resultados de tu operación',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              DropdownButton<String>(
                value: currency,
                underline: const SizedBox.shrink(),
                items: [
                  for (final code in currencies)
                    DropdownMenuItem(
                      value: code,
                      child: Text(code, style: const TextStyle(fontSize: 12)),
                    ),
                ],
                onChanged: (v) => setState(() => _currency = v),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, box) {
              final width = (box.maxWidth - 11) / 2;
              return Wrap(
                spacing: 11,
                runSpacing: 11,
                children: [
                  for (final item in data)
                    SizedBox(
                      width: width,
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.$1,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.muted,
                                ),
                              ),
                              const SizedBox(height: 9),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  number(item.$2),
                                  style: const TextStyle(
                                    fontSize: 23,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                currency,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: AppTheme.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Costos e ingresos',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      SizedBox(
                        width: 100,
                        height: 100,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            CustomPaint(
                              size: const Size(100, 100),
                              painter: _CostRing(cost: cost, revenue: revenue),
                            ),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  revenue == 0
                                      ? '—'
                                      : '${(cost / revenue * 100).round()}%',
                                  style: const TextStyle(
                                    fontSize: 21,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const Text(
                                  'costo / ingreso',
                                  style: TextStyle(
                                    fontSize: 8,
                                    color: AppTheme.muted,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 26),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _legend(
                              'Ingresos',
                              revenue,
                              const Color(0xFF2C7047),
                            ),
                            const SizedBox(height: 15),
                            _legend('Costos', cost, const Color(0xFFD8A33F)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (budget > 0) ...[
                    const SizedBox(height: 24),
                    const Text(
                      'Ejecución del presupuesto',
                      style: TextStyle(fontSize: 11, color: AppTheme.muted),
                    ),
                    const SizedBox(height: 9),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: LinearProgressIndicator(
                        value: (cost / budget).clamp(0, 1),
                        backgroundColor: AppTheme.line,
                        color: cost > budget
                            ? const Color(0xFFC68B3D)
                            : AppTheme.forest,
                        minHeight: 6,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${number((cost - budget).abs())} $currency ${cost > budget ? 'por encima' : 'por debajo'} del presupuesto',
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppTheme.muted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      );
    },
  );
  Widget _legend(String label, double amount, Color color) => Row(
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: AppTheme.muted),
            ),
            Text(
              number(amount),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    ],
  );
}

class _CostRing extends CustomPainter {
  const _CostRing({required this.cost, required this.revenue});
  final double cost, revenue;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12;
    final ring = rect.deflate(7);
    final total = cost + revenue;
    paint.color = AppTheme.line;
    canvas.drawArc(ring, 0, math.pi * 2, false, paint);
    if (total <= 0) return;
    final angle = revenue / total * math.pi * 2;
    paint.color = const Color(0xFF2C7047);
    canvas.drawArc(ring, -math.pi / 2, angle, false, paint);
    paint.color = const Color(0xFFD8A33F);
    canvas.drawArc(
      ring,
      -math.pi / 2 + angle,
      math.pi * 2 - angle,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_CostRing oldDelegate) =>
      cost != oldDelegate.cost || revenue != oldDelegate.revenue;
}
