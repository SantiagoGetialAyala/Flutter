import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

LatLng? pointFromGeometry(dynamic geometry) {
  if (geometry is! Map || geometry['type'] != 'Point') return null;
  final coordinates = geometry['coordinates'];
  if (coordinates is! List || coordinates.length < 2) return null;
  final lon = num.tryParse('${coordinates[0]}');
  final lat = num.tryParse('${coordinates[1]}');
  if (lon == null ||
      lat == null ||
      !lon.isFinite ||
      !lat.isFinite ||
      lon.abs() > 180 ||
      lat.abs() > 90) {
    return null;
  }
  return LatLng(lat.toDouble(), lon.toDouble());
}

Map<String, dynamic> pointGeometry(LatLng point) => {
  'type': 'Point',
  'coordinates': [point.longitude, point.latitude],
};

class LocationField extends StatefulWidget {
  const LocationField({
    super.key,
    required this.label,
    required this.onChanged,
    this.geometry,
    this.center,
    this.department,
    this.municipality,
    this.required = true,
    this.tileProvider,
  });
  final String label;
  final dynamic geometry;
  final LatLng? center;
  final String? department, municipality;
  final bool required;
  final TileProvider? tileProvider;
  final ValueChanged<Map<String, dynamic>> onChanged;
  @override
  State<LocationField> createState() => _LocationFieldState();
}

class _LocationFieldState extends State<LocationField> {
  final _fieldKey = GlobalKey<FormFieldState<LatLng>>();
  late LatLng? _point = pointFromGeometry(widget.geometry);
  late final _latitude = TextEditingController(
    text: _point == null ? '' : '${_point!.latitude}',
  );
  late final _longitude = TextEditingController(
    text: _point == null ? '' : '${_point!.longitude}',
  );

  @override
  void dispose() {
    _latitude.dispose();
    _longitude.dispose();
    super.dispose();
  }

  void _select(LatLng point) {
    setState(() => _point = point);
    _latitude.text = point.latitude.toStringAsFixed(6);
    _longitude.text = point.longitude.toStringAsFixed(6);
    _fieldKey.currentState?.didChange(point);
    widget.onChanged(pointGeometry(point));
  }

  void _manual(String _) {
    final lat = double.tryParse(_latitude.text.trim());
    final lon = double.tryParse(_longitude.text.trim());
    if (lat == null ||
        lon == null ||
        !lat.isFinite ||
        !lon.isFinite ||
        lat.abs() > 90 ||
        lon.abs() > 180) {
      return;
    }
    final point = LatLng(lat, lon);
    setState(() => _point = point);
    _fieldKey.currentState?.didChange(point);
    widget.onChanged(pointGeometry(point));
  }

  Future<void> _openMap() async {
    final point = await showDialog<LatLng>(
      context: context,
      builder: (_) => _MapPicker(
        initial: _point,
        center: widget.center,
        department: widget.department,
        municipality: widget.municipality,
        label: widget.label,
        tileProvider: widget.tileProvider,
      ),
    );
    if (point != null && mounted) _select(point);
  }

  @override
  Widget build(BuildContext context) => FormField<LatLng>(
    key: _fieldKey,
    initialValue: _point,
    validator: (_) => widget.required && _point == null
        ? 'Marca la ubicación en el mapa o ingresa sus coordenadas.'
        : null,
    builder: (state) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        const Text(
          'Elige departamento y municipio dentro del mapa para encontrar el terreno sin escribir coordenadas. También puedes ingresarlas manualmente abajo.',
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _openMap,
          icon: const Icon(Icons.map_outlined),
          label: Text(
            _point == null
                ? 'Elegir ubicación en OpenStreetMap'
                : 'Cambiar ubicación en el mapa',
          ),
        ),
        if (_point != null)
          Text(
            'Ubicación guardada en el formulario · Latitud ${_point!.latitude.toStringAsFixed(6)} · Longitud ${_point!.longitude.toStringAsFixed(6)}',
          ),
        if (state.hasError)
          Text(
            state.errorText!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('Ingresar coordenadas manualmente'),
          subtitle: const Text('Opcional: si ya tienes la ubicación del GPS'),
          maintainState: true,
          children: [
            for (final isLatitude in [true, false])
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextFormField(
                  controller: isLatitude ? _latitude : _longitude,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: InputDecoration(
                    labelText: isLatitude ? 'Latitud' : 'Longitud',
                    helperText: isLatitude
                        ? 'Posición norte/sur. De −90 a 90. Ejemplo: 4.60.'
                        : 'Posición este/oeste. De −180 a 180. Ejemplo: -74.08.',
                  ),
                  onChanged: _manual,
                  validator: (text) {
                    if ((text ?? '').isEmpty &&
                        _latitude.text.isEmpty &&
                        _longitude.text.isEmpty) {
                      return null;
                    }
                    final value = double.tryParse(text?.trim() ?? '');
                    final limit = isLatitude ? 90 : 180;
                    return value == null ||
                            !value.isFinite ||
                            value.abs() > limit
                        ? 'Ingresa una coordenada entre −$limit y $limit.'
                        : null;
                  },
                ),
              ),
            const Text(
              'Usa grados decimales WGS84 y punto decimal. El punto es una referencia de ubicación, no los límites de la finca.',
            ),
          ],
        ),
      ],
    ),
  );
}

class _MapPicker extends StatefulWidget {
  const _MapPicker({
    required this.label,
    this.initial,
    this.center,
    this.department,
    this.municipality,
    this.tileProvider,
  });
  final String label;
  final LatLng? initial, center;
  final String? department, municipality;
  final TileProvider? tileProvider;
  @override
  State<_MapPicker> createState() => _MapPickerState();
}

class _MapPickerState extends State<_MapPicker> {
  final _controller = MapController();
  late LatLng? _point = widget.initial;
  String? _department, _municipality;
  List<Map<String, dynamic>> _places = [];
  bool _loadingPlaces = true;
  String? _placesError;
  bool _tileError = false;
  bool _placesRequested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_placesRequested) {
      _placesRequested = true;
      _loadPlaces();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadPlaces() async {
    try {
      final data = await DefaultAssetBundle.of(
        context,
      ).loadString('assets/data/colombia_municipalities.json');
      if (!mounted) {
        return;
      }
      setState(() {
        _places = (jsonDecode(data) as List).cast<Map<String, dynamic>>();
        _department = _places
            .where((p) => p['department'] == widget.department)
            .firstOrNull?['department'];
        _municipality = _places
            .where(
              (p) =>
                  p['department'] == _department &&
                  p['name'] == widget.municipality,
            )
            .firstOrNull?['name'];
        _loadingPlaces = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingPlaces = false;
          _placesError =
              'No pudimos cargar los municipios. Puedes mover el mapa o ingresar coordenadas al volver.';
        });
      }
    }
  }

  void _chooseMunicipality(String? name) {
    final place = _places
        .where((p) => p['department'] == _department && p['name'] == name)
        .firstOrNull;
    setState(() {
      _municipality = name;
      _point = null;
    });
    if (place == null) return;
    _controller.move(
      LatLng(
        (place['latitude'] as num).toDouble(),
        (place['longitude'] as num).toDouble(),
      ),
      12,
    );
  }

  Widget _placeSelectors() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        '1. Acércate a tu municipio',
        style: TextStyle(fontWeight: FontWeight.w600),
      ),
      if (_loadingPlaces) const LinearProgressIndicator(),
      if (_placesError != null) Text(_placesError!),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
        initialValue: _department,
        key: ValueKey('map-department:$_department'),
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Departamento de Colombia',
        ),
        items: [
          for (final department
              in (_places.map((p) => '${p['department']}').toSet().toList()
                ..sort()))
            DropdownMenuItem(value: department, child: Text(department)),
        ],
        onChanged: _loadingPlaces
            ? null
            : (value) => setState(() {
                _department = value;
                _municipality = null;
                _point = null;
              }),
      ),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
        initialValue: _municipality,
        key: ValueKey('map-municipality:$_department:$_municipality'),
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Municipio',
          hintText: 'Primero elige el departamento',
        ),
        items: [
          for (final name
              in (_places
                  .where((p) => p['department'] == _department)
                  .map((p) => '${p['name']}')
                  .toSet()
                  .toList()
                ..sort()))
            DropdownMenuItem(value: name, child: Text(name)),
        ],
        onChanged: _department == null ? null : _chooseMunicipality,
      ),
    ],
  );
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.label),
    content: SizedBox(
      width: 680,
      height: MediaQuery.sizeOf(context).height * .72,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _placeSelectors(),
            const SizedBox(height: 12),
            const Text(
              '2. Toca el terreno y confirma la ubicación',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const Text(
              'El municipio acerca el mapa. Toca el lugar real de tu finca o parcela para marcar el punto.',
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: (MediaQuery.sizeOf(context).height * .32).clamp(
                180.0,
                360.0,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: FlutterMap(
                  mapController: _controller,
                  options: MapOptions(
                    initialCenter:
                        widget.initial ??
                        widget.center ??
                        const LatLng(4.57, -74.30),
                    initialZoom: widget.initial == null && widget.center == null
                        ? 5
                        : 12,
                    maxZoom: 19,
                    onTap: (_, point) => setState(() => _point = point),
                  ),
                  children: [
                    TileLayer(
                      tileProvider: widget.tileProvider,
                      urlTemplate: const String.fromEnvironment(
                        'OSM_TILE_URL',
                        defaultValue:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      ),
                      userAgentPackageName: 'com.agropremium.frontend',
                      errorTileCallback: (_, _, _) {
                        if (!_tileError && mounted) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) setState(() => _tileError = true);
                          });
                        }
                      },
                    ),
                    if (_point != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _point!,
                            width: 44,
                            height: 44,
                            alignment: Alignment.topCenter,
                            child: const Icon(
                              Icons.location_pin,
                              color: Colors.red,
                              size: 44,
                            ),
                          ),
                        ],
                      ),
                    Align(
                      alignment: Alignment.bottomRight,
                      child: Material(
                        color: Colors.white,
                        child: InkWell(
                          onTap: () => launchUrl(
                            Uri.parse(
                              'https://www.openstreetmap.org/copyright',
                            ),
                          ),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Text(
                              '© OpenStreetMap contributors',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_tileError)
              const Text(
                'No se pudo cargar parte del mapa. Revisa tu conexión o vuelve e ingresa coordenadas manualmente.',
              ),
            Text(
              _point == null
                  ? 'Todavía no has marcado un punto.'
                  : 'Latitud ${_point!.latitude.toStringAsFixed(6)} · Longitud ${_point!.longitude.toStringAsFixed(6)}',
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: _point == null ? null : () => Navigator.pop(context, _point),
        child: const Text('Usar esta ubicación'),
      ),
    ],
  );
}
