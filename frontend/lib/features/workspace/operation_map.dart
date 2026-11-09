import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/services/api_client.dart';
import '../../../core/theme/app_theme.dart';
import 'presentation.dart';

/// Coordinates are always [longitude, latitude], as in GeoJSON.
List<Offset> geoCoordinates(dynamic geometry) {
  if (geometry is! Map) return [];
  if (geometry['type'] == 'Feature') {
    return geoCoordinates(geometry['geometry']);
  }
  final type = geometry['type'];
  if (!['Point', 'Polygon', 'MultiPolygon', 'LineString'].contains(type)) {
    return [];
  }
  final points = <Offset>[];
  void visit(dynamic node) {
    if (node is! List) return;
    if (node.length >= 2 && node[0] is num && node[1] is num) {
      final lon = (node[0] as num).toDouble(),
          lat = (node[1] as num).toDouble();
      if (lon.isFinite && lat.isFinite && lon.abs() <= 180 && lat.abs() <= 90) {
        points.add(Offset(lon, lat));
      }
    } else {
      for (final part in node) {
        visit(part);
      }
    }
  }

  visit(geometry['coordinates']);
  return points;
}

Map<String, dynamic> eventGeometry(dynamic location) {
  if (location is! Map) return {};
  if (location['type'] != null) return Map<String, dynamic>.from(location);
  final lat = num.tryParse('${location['latitude'] ?? location['lat']}');
  final lon = num.tryParse(
    '${location['longitude'] ?? location['lng'] ?? location['lon']}',
  );
  return lat == null || lon == null
      ? {}
      : {
          'type': 'Point',
          'coordinates': [lon, lat],
        };
}

class OperationMap extends StatefulWidget {
  const OperationMap({
    super.key,
    required this.api,
    required this.modules,
    this.exportId,
  });
  final ApiClient api;
  final Set<String> modules;
  final int? exportId;
  @override
  State<OperationMap> createState() => _OperationMapState();
}

class _OperationMapState extends State<OperationMap> {
  List<Map<String, dynamic>> _features = [],
      _transports = [],
      _events = [],
      _exports = [];
  String? _error;
  bool _loading = true;
  int? _selected, _exportId;
  int _request = 0;
  final _transform = TransformationController();
  @override
  void initState() {
    super.initState();
    _exportId = widget.exportId;
    _load();
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
      _selected = null;
    });
    try {
      List<Map<String, dynamic>> farms = [],
          plots = [],
          events = [],
          transports = [],
          timeline = [],
          exports = _exports;
      if (_exportId != null) {
        final data = await widget.api.getMap('/exports/$_exportId/map/');
        plots = (data['plots'] as List? ?? []).cast<Map<String, dynamic>>();
        events = (data['events'] as List? ?? []).cast<Map<String, dynamic>>();
        transports = (data['transports'] as List? ?? [])
            .cast<Map<String, dynamic>>();
        timeline = (data['transport_events'] as List? ?? [])
            .cast<Map<String, dynamic>>();
      } else {
        // Only request endpoints exposed by the server for this membership.
        final result = await Future.wait([
          if (widget.modules.contains('plots')) widget.api.getAll('/plots/'),
          if (widget.modules.contains('traceability-events'))
            widget.api.getAll('/traceability-events/'),
          if (widget.modules.contains('transports'))
            widget.api.getAll('/transports/'),
          if (widget.modules.contains('transport-events'))
            widget.api.getAll('/transport-events/'),
          if (widget.modules.contains('exports'))
            widget.api.getAll('/exports/'),
          if (widget.modules.contains('farms')) widget.api.getAll('/farms/'),
        ]);
        var i = 0;
        if (widget.modules.contains('plots')) plots = result[i++];
        if (widget.modules.contains('traceability-events')) {
          events = result[i++];
        }
        if (widget.modules.contains('transports')) transports = result[i++];
        if (widget.modules.contains('transport-events')) timeline = result[i++];
        if (widget.modules.contains('exports')) exports = result[i++];
        if (widget.modules.contains('farms')) farms = result[i++];
      }
      final farmNames = {
        for (final farm in farms) '${farm['id']}': farm['name'],
      };
      final features = <Map<String, dynamic>>[
        for (final farm in farms)
          if (geoCoordinates(farm['geometry']).isNotEmpty)
            {
              'title': farm['name'],
              'subtitle':
                  'Finca · ${farm['municipality'] ?? ''}, ${farm['department'] ?? ''}',
              'geometry': farm['geometry'],
              'kind': 'Punto de referencia de la finca',
            },
        for (final p in plots)
          {
            'title':
                '${'${p['name'] ?? ''}'.trim().isEmpty ? p['code'] : p['name']}',
            'subtitle':
                'Parcela · ${p['farm__name'] ?? farmNames['${p['farm_id'] ?? p['farm']}'] ?? 'Finca vinculada'}',
            'geometry': p['geometry'],
            'kind': p['geometry']?['type'] == 'Point'
                ? 'Referencia de parcela (punto)'
                : 'Límites de parcela',
          },
        for (final e in events)
          if (geoCoordinates(eventGeometry(e['location'])).isNotEmpty)
            {
              'title': friendly(e['event_type']),
              'subtitle':
                  '${dateText(e['event_at'], time: true)} · ${e['notes'] ?? ''}',
              'geometry': eventGeometry(e['location']),
              'kind': 'Evento registrado',
            },
      ].where((p) => geoCoordinates(p['geometry']).isNotEmpty).toList();
      if (!mounted || request != _request) return;
      setState(() {
        _features = features;
        _transports = transports;
        _events = [...events, ...timeline]
          ..sort((a, b) => '${b['event_at']}'.compareTo('${a['event_at']}'));
        _exports = exports;
        _loading = false;
      });
      _transform.value = Matrix4.identity();
    } catch (e) {
      if (mounted && request == _request) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
    children: [
      const Text(
        'Origen y seguimiento',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 5),
      const Text(
        'Ubicaciones registradas de fincas, parcelas y eventos. Un punto es una referencia del terreno; los límites solo aparecen cuando se ha registrado un polígono.',
        style: TextStyle(color: AppTheme.muted),
      ),
      if (widget.exportId == null && _exports.isNotEmpty) ...[
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: _exportId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Filtrar por operación'),
          items: [
            const DropdownMenuItem<int>(
              value: null,
              child: Text('Todas las ubicaciones autorizadas'),
            ),
            for (final e in _exports)
              DropdownMenuItem(
                value: e['id'] as int,
                child: Text('${e['code']}', overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (id) {
            _exportId = id;
            _load();
          },
        ),
      ],
      const SizedBox(height: 16),
      if (_loading) const LinearProgressIndicator(),
      if (_error != null)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text('No pudimos cargar las ubicaciones. $_error'),
                TextButton(onPressed: _load, child: const Text('Reintentar')),
              ],
            ),
          ),
        ),
      if (!_loading && _error == null) ...[
        if (_features.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(
                    Icons.location_off_outlined,
                    size: 34,
                    color: AppTheme.muted,
                  ),
                  SizedBox(height: 12),
                  Text('Aún no hay coordenadas registradas'),
                  SizedBox(height: 6),
                  Text(
                    'Los nombres de fincas, ciudades y destinos no permiten ubicar un punto exacto. Registra una parcela o un evento con coordenadas.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          )
        else ...[
          Card(
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              height: 310,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Semantics(
                      label:
                          'Mapa geográfico de ${_features.length} ubicaciones. Selecciona una ubicación en la lista para ver sus coordenadas.',
                      child: InteractiveViewer(
                        transformationController: _transform,
                        minScale: 1,
                        maxScale: 8,
                        child: CustomPaint(
                          size: Size.infinite,
                          painter: _GeoPainter(_features, _selected),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 12,
                    top: 10,
                    child: Container(
                      padding: const EdgeInsets.all(7),
                      color: AppTheme.ivory,
                      child: const Text(
                        'N ↑  ·  Coordenadas registradas',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: IconButton.filledTonal(
                      tooltip: 'Restablecer mapa',
                      onPressed: () => _transform.value = Matrix4.identity(),
                      icon: const Icon(Icons.center_focus_strong),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Vista geográfica sin mapa base · amplía con dos dedos. No es seguimiento GPS.',
            style: TextStyle(color: AppTheme.muted, fontSize: 11),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < _features.length; i++)
            Card(
              child: ListTile(
                selected: _selected == i,
                leading: Text(
                  '${i + 1}',
                  style: const TextStyle(
                    color: AppTheme.forest,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                title: Text('${_features[i]['title']}'),
                subtitle: Text(
                  '${_features[i]['subtitle']} · ${_features[i]['kind']}\n${_coordinateSummary(_features[i])}',
                ),
                isThreeLine: true,
                trailing: const Icon(Icons.chevron_right),
                onTap: () => setState(() => _selected = i),
              ),
            ),
          if (_selected != null) _details(_features[_selected!]),
        ],
        const SizedBox(height: 16),
        const Text(
          'Puntos logísticos y planificación',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        if (_transports.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'No hay trayectos logísticos registrados en esta vista.',
            ),
          ),
        for (final t in _transports)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${t['pickup_place'] ?? 'Origen no compartido'} → ${t['delivery_place']}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    'Planificado · ${dateText(t['scheduled_pickup'] ?? t['scheduled_delivery'], time: true)}',
                  ),
                  Text('Estado registrado: ${friendly(t['status'])}'),
                  const Text(
                    'Sin coordenadas del trayecto; no se dibuja una ruta.',
                    style: TextStyle(fontSize: 11, color: AppTheme.muted),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
        const Text(
          'Timeline de eventos',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        if (_events.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Aún no hay eventos registrados.'),
          ),
        for (final e in _events)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(
              Icons.check_circle_outline,
              color: AppTheme.forest,
            ),
            title: Text(friendly(e['event_type'])),
            subtitle: Text(
              '${dateText(e['event_at'], time: true)}\n${e['notes'] ?? ''}',
            ),
          ),
      ],
    ],
  );

  Widget _details(Map<String, dynamic> feature) {
    final points = geoCoordinates(feature['geometry']);
    return Card(
      color: AppTheme.ivory,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${feature['title']}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            Text('${feature['subtitle']}'),
            const Text('Sistema WGS84 · grados decimales'),
            SelectableText(
              [
                for (var i = 0; i < points.length; i++)
                  '${points.length > 1 ? 'Vértice ${i + 1} · ' : ''}Longitud: ${points[i].dx.toStringAsFixed(6)} · Latitud: ${points[i].dy.toStringAsFixed(6)}',
              ].join('\n'),
            ),
            Text('${feature['kind']} · ${points.length} vértice(s)'),
          ],
        ),
      ),
    );
  }

  String _coordinateSummary(Map<String, dynamic> feature) {
    final points = geoCoordinates(feature['geometry']);
    final point = points.first;
    return '${points.length > 1 ? 'Primer vértice de ${points.length} · ' : ''}Lat: ${point.dy.toStringAsFixed(6)} · Lon: ${point.dx.toStringAsFixed(6)}';
  }
}

class _GeoPainter extends CustomPainter {
  _GeoPainter(this.features, this.selected);
  final List<Map<String, dynamic>> features;
  final int? selected;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(AppTheme.ivory, BlendMode.src);
    final all = features.expand((f) => geoCoordinates(f['geometry'])).toList();
    if (all.isEmpty) return;
    final minX = all.map((p) => p.dx).reduce(math.min),
        maxX = all.map((p) => p.dx).reduce(math.max);
    final minY = all.map((p) => p.dy).reduce(math.min),
        maxY = all.map((p) => p.dy).reduce(math.max);
    final midLat = (minY + maxY) / 2;
    final cosLat = math.max(.05, math.cos(midLat * math.pi / 180));
    final spanX = math.max(.002, maxX - minX),
        spanY = math.max(.002, maxY - minY);
    final scale = math.min(
      (size.width - 70) / (spanX * cosLat),
      (size.height - 70) / spanY,
    );
    Offset project(Offset p) => Offset(
      size.width / 2 + (p.dx - (minX + maxX) / 2) * cosLat * scale,
      size.height / 2 - (p.dy - (minY + maxY) / 2) * scale,
    );
    final grid = Paint()
      ..color = AppTheme.line
      ..strokeWidth = 1;
    for (var i = 1; i < 6; i++) {
      canvas.drawLine(
        Offset(size.width * i / 6, 0),
        Offset(size.width * i / 6, size.height),
        grid,
      );
      canvas.drawLine(
        Offset(0, size.height * i / 6),
        Offset(size.width, size.height * i / 6),
        grid,
      );
    }
    for (var i = 0; i < features.length; i++) {
      final geometry = features[i]['geometry'];
      final color = i == selected ? AppTheme.coffee : AppTheme.forest;
      void shape(dynamic g) {
        if (g is! Map) return;
        if (g['type'] == 'Feature') {
          shape(g['geometry']);
          return;
        }
        if (g['type'] == 'MultiPolygon') {
          for (final polygon in g['coordinates'] as List) {
            shape({'type': 'Polygon', 'coordinates': polygon});
          }
          return;
        }
        final points = geoCoordinates(g);
        if (points.isEmpty) return;
        if (g['type'] == 'Polygon') {
          final path = Path()..fillType = PathFillType.evenOdd;
          for (final ring in g['coordinates'] as List) {
            final ringPoints = geoCoordinates({
              'type': 'LineString',
              'coordinates': ring,
            });
            if (ringPoints.length < 3) continue;
            path.addPolygon(ringPoints.map(project).toList(), true);
          }
          canvas.drawPath(path, Paint()..color = color.withValues(alpha: .18));
          canvas.drawPath(
            path,
            Paint()
              ..color = color
              ..strokeWidth = 2
              ..style = PaintingStyle.stroke,
          );
        } else if (g['type'] == 'LineString') {
          final path = Path()..addPolygon(points.map(project).toList(), false);
          canvas.drawPath(
            path,
            Paint()
              ..color = color
              ..strokeWidth = 2
              ..style = PaintingStyle.stroke,
          );
        }
      }

      shape(geometry);
      final points = geoCoordinates(geometry);
      final center = project(points.first);
      canvas.drawCircle(center, 12, Paint()..color = color);
      final text = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: const TextStyle(fontSize: 11, color: Colors.white),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(canvas, center - Offset(text.width / 2, text.height / 2));
    }
  }

  @override
  bool shouldRepaint(_GeoPainter oldDelegate) => true;
}
