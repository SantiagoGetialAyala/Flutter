import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/services/api_client.dart';
import 'location_field.dart';
import 'record_form.dart';

class FarmForm extends StatefulWidget {
  const FarmForm({
    super.key,
    required this.api,
    required this.modules,
    this.record,
    this.initialValues = const {},
    this.onSaved,
  });
  final ApiClient api;
  final List<Map<String, dynamic>> modules;
  final Map<String, dynamic>? record;
  final Map<String, dynamic> initialValues;
  final ValueChanged<Map<String, dynamic>>? onSaved;
  @override
  State<FarmForm> createState() => _FarmFormState();
}

class _ParcelDraft {
  final name = TextEditingController();
  final area = TextEditingController();
  Map<String, dynamic>? geometry;
  String? crop;
  void dispose() {
    name.dispose();
    area.dispose();
  }
}

class _FarmFormState extends State<FarmForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(
    text: '${widget.record?['name'] ?? ''}',
  );
  late final _area = TextEditingController(
    text: '${widget.record?['area'] ?? ''}',
  );
  late String _unit = '${widget.record?['area_unit'] ?? 'hectarea'}';
  String? _producer, _department, _municipality, _crop, _error;
  List<Map<String, dynamic>> _producers = [], _places = [], _existing = [];
  Map<String, dynamic>? _geometry;
  LatLng? _center;
  bool _loading = true, _saving = false, _divide = false;
  final _parcels = <_ParcelDraft>[];
  bool get _new => widget.record == null;
  double get _hectares =>
      (double.tryParse(_area.text.trim()) ?? 0) * (_unit == 'km2' ? 100 : 1);

  @override
  void initState() {
    super.initState();
    _producer = (widget.record?['producer'] ?? widget.initialValues['producer'])
        ?.toString();
    _geometry = widget.record?['geometry'] is Map
        ? Map<String, dynamic>.from(widget.record!['geometry'])
        : null;
    _existing = (widget.record?['plots'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    _crop = _existing.firstOrNull?['crop_type'];
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _area.dispose();
    for (final parcel in _parcels) {
      parcel.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final values = await Future.wait<dynamic>([
        widget.api.getAll('/producers/'),
        rootBundle.loadString('assets/data/colombia_municipalities.json'),
      ]);
      _producers = values[0] as List<Map<String, dynamic>>;
      _places = (jsonDecode(values[1] as String) as List)
          .cast<Map<String, dynamic>>();
      if (_producer == null && _producers.length == 1) {
        _producer = '${_producers.single['id']}';
      }
      final department = '${widget.record?['department'] ?? ''}';
      _department =
          _places
              .where(
                (p) =>
                    '${p['department']}'.toLowerCase() ==
                    department.toLowerCase(),
              )
              .firstOrNull?['department'] ??
          (department.isEmpty ? null : department);
      final municipality = '${widget.record?['municipality'] ?? ''}';
      _municipality =
          _places
              .where(
                (p) =>
                    p['department'] == _department &&
                    '${p['name']}'.toLowerCase() == municipality.toLowerCase(),
              )
              .firstOrNull?['name'] ??
          (municipality.isEmpty ? null : municipality);
      _updateCenter();
    } catch (e) {
      _error = 'No pudimos cargar los productores o municipios. $e';
    }
    if (mounted) setState(() => _loading = false);
  }

  void _updateCenter() {
    final place = _places
        .where(
          (p) => p['department'] == _department && p['name'] == _municipality,
        )
        .firstOrNull;
    _center = place == null
        ? null
        : LatLng(
            (place['latitude'] as num).toDouble(),
            (place['longitude'] as num).toDouble(),
          );
  }

  Future<void> _createProducer() async {
    final module = widget.modules
        .where((m) => m['key'] == 'producers' && m['can_create'] == true)
        .firstOrNull;
    if (module == null) return;
    Map<String, dynamic>? created;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => RecordForm(
        api: widget.api,
        module: module,
        modules: widget.modules,
        onSaved: (row) => created = row,
      ),
    );
    if (saved != true || !mounted) return;
    try {
      final producers = await widget.api.getAll('/producers/');
      if (mounted) {
        setState(() {
          _producers = producers;
          _producer = '${created!['id']}';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _editPlot(Map<String, dynamic> plot) async {
    final module = widget.modules
        .where((m) => m['key'] == 'plots' && m['can_update'] == true)
        .firstOrNull;
    if (module == null) return;
    try {
      final record = await widget.api.getMap('/plots/${plot['id']}/');
      if (!mounted) return;
      final saved = await showDialog<bool>(
        context: context,
        builder: (_) => RecordForm(
          api: widget.api,
          module: module,
          modules: widget.modules,
          record: record,
          initialValues: {'farm': widget.record!['id']},
          lockedFields: {'farm'},
        ),
      );
      if (saved == true) {
        final farm = await widget.api.getMap('/farms/${widget.record!['id']}/');
        if (mounted) {
          setState(
            () => _existing = (farm['plots'] as List)
                .cast<Map<String, dynamic>>(),
          );
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final plots = <Map<String, dynamic>>[];
    if (_divide) {
      for (final parcel in _parcels) {
        plots.add({
          'name': parcel.name.text.trim(),
          'area': parcel.area.text.trim(),
          'crop_type': parcel.crop ?? _crop,
          'geometry': parcel.geometry ?? _geometry,
        });
      }
    } else if (_new || _existing.isEmpty) {
      plots.add({
        'name': 'Área principal',
        'area': _hectares.toStringAsFixed(3),
        'crop_type': _crop,
        'geometry': _geometry,
      });
    }
    final existingArea = _existing.fold<double>(
      0,
      (total, p) => total + (double.tryParse('${p['area']}') ?? 0),
    );
    final newArea = plots.fold<double>(
      0,
      (total, p) => total + double.parse('${p['area']}'),
    );
    if (_divide && plots.isEmpty) {
      setState(
        () => _error = 'Agrega al menos una parcela o desactiva la división.',
      );
      return;
    }
    if (existingArea + newArea > _hectares + .0000001) {
      setState(
        () => _error =
            'Las parcelas suman más que el área de la finca. Recuerda: 1 km² = 100 ha.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final data = <String, dynamic>{
        'name': _name.text.trim(),
        'area': _area.text.trim(),
        'area_unit': _unit,
        'producer': int.parse(_producer!),
        'department': _department,
        'municipality': _municipality,
        'geometry': _geometry,
        if (plots.isNotEmpty) 'new_plots': plots,
      };
      final result = _new
          ? await widget.api.post('/farms/', data)
          : await widget.api.patch('/farms/${widget.record!['id']}/', data);
      widget.onSaved?.call(result);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '$e';
        });
      }
    }
  }

  String? _positive(String? text) {
    final value = double.tryParse(text?.trim() ?? '');
    return value == null || !value.isFinite || value <= 0
        ? 'Indica un área mayor que cero, con punto decimal.'
        : null;
  }

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 10),
    child: Text(
      text,
      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final departments = _places.map((p) => '${p['department']}').toSet();
    if (_department != null) departments.add(_department!);
    final municipalities = _places
        .where((p) => p['department'] == _department)
        .map((p) => '${p['name']}')
        .toSet();
    if (_municipality != null) municipalities.add(_municipality!);
    return AlertDialog(
      title: Text(_new ? 'Registrar finca y cultivo' : 'Finca y parcelas'),
      content: SizedBox(
        width: 650,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Registra el terreno y su área de cultivo en un solo lugar. Los códigos se generan automáticamente.',
                      ),
                      if (_error != null)
                        Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      _heading('1. Tamaño de la finca'),
                      DropdownButtonFormField<String>(
                        initialValue: _unit,
                        decoration: const InputDecoration(
                          labelText: 'Unidad de superficie',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'hectarea',
                            child: Text('Hectáreas (ha)'),
                          ),
                          DropdownMenuItem(
                            value: 'km2',
                            child: Text('Kilómetros cuadrados (km²)'),
                          ),
                        ],
                        onChanged: (value) => setState(() => _unit = value!),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _area,
                        decoration: const InputDecoration(
                          labelText: 'Área total de la finca *',
                          helperText:
                              'Tamaño de todo el terreno. 1 km² equivale a 100 hectáreas.',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        validator: _positive,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _name,
                        decoration: const InputDecoration(
                          labelText: 'Nombre de la finca *',
                          helperText: 'Por ejemplo: La Esperanza.',
                        ),
                        maxLength: 180,
                        validator: (v) => (v ?? '').trim().isEmpty
                            ? 'Escribe el nombre de la finca.'
                            : null,
                      ),
                      if (_producers.length != 1 || _producer == null)
                        DropdownButtonFormField<String>(
                          key: ValueKey('producer:$_producer'),
                          initialValue: _producer,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Productor responsable *',
                          ),
                          items: [
                            for (final producer in _producers)
                              DropdownMenuItem(
                                value: '${producer['id']}',
                                child: Text('${producer['name']}'),
                              ),
                          ],
                          onChanged: (value) => _producer = value,
                          validator: (v) => v == null
                              ? 'Registra o selecciona el productor responsable.'
                              : null,
                        )
                      else
                        Text('Productor: ${_producers.single['name']}'),
                      if (_producers.isEmpty &&
                          widget.modules.any(
                            (m) =>
                                m['key'] == 'producers' &&
                                m['can_create'] == true,
                          ))
                        TextButton.icon(
                          onPressed: _createProducer,
                          icon: const Icon(Icons.person_add_outlined),
                          label: const Text(
                            'Crear mi perfil de productor aquí',
                          ),
                        ),
                      _heading('2. Ubicación en Colombia'),
                      DropdownButtonFormField<String>(
                        initialValue: _department,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Departamento *',
                        ),
                        items: [
                          for (final department in departments.toList()..sort())
                            DropdownMenuItem(
                              value: department,
                              child: Text(department),
                            ),
                        ],
                        onChanged: (value) => setState(() {
                          _department = value;
                          _municipality = null;
                          _center = null;
                        }),
                        validator: (v) =>
                            v == null ? 'Selecciona el departamento.' : null,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        key: ValueKey(
                          'municipality:$_department:$_municipality',
                        ),
                        initialValue: _municipality,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Municipio *',
                          helperText: 'Primero selecciona el departamento.',
                        ),
                        items: [
                          for (final municipality
                              in municipalities.toList()..sort())
                            DropdownMenuItem(
                              value: municipality,
                              child: Text(municipality),
                            ),
                        ],
                        onChanged: _department == null
                            ? null
                            : (value) => setState(() {
                                _municipality = value;
                                _updateCenter();
                              }),
                        validator: (v) =>
                            v == null ? 'Selecciona el municipio.' : null,
                      ),
                      const SizedBox(height: 12),
                      LocationField(
                        label: 'Ubicación de la finca *',
                        department: _department,
                        municipality: _municipality,
                        geometry: _geometry,
                        center: _center,
                        onChanged: (value) => _geometry = value,
                      ),
                      _heading('3. Área de cultivo'),
                      const Text(
                        'Una parcela es una parte de la finca. Si no necesitas dividirla, guardaremos una sola como “Área principal”, con la misma superficie y ubicación de referencia.',
                      ),
                      if (_new || _existing.isEmpty || _divide) ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: _crop,
                          decoration: const InputDecoration(
                            labelText: '¿Qué cultivas? *',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'cafe',
                              child: Text('Café'),
                            ),
                            DropdownMenuItem(
                              value: 'cacao',
                              child: Text('Cacao'),
                            ),
                          ],
                          onChanged: (value) => _crop = value,
                          validator: (v) =>
                              v == null ? 'Selecciona café o cacao.' : null,
                        ),
                      ],
                      for (final plot in _existing)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('${plot['name'] ?? plot['code']}'),
                          subtitle: Text(
                            '${plot['area']} ha · ${plot['crop_type']}',
                          ),
                          trailing:
                              widget.modules.any(
                                (m) =>
                                    m['key'] == 'plots' &&
                                    m['can_update'] == true,
                              )
                              ? TextButton(
                                  onPressed: () => _editPlot(plot),
                                  child: const Text('Editar parcela'),
                                )
                              : null,
                        ),
                      if (_existing.isNotEmpty)
                        const Text(
                          'Para dividir un área ya registrada, edita primero su superficie y luego agrega las nuevas parcelas. La suma debe caber en la finca.',
                        ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          _existing.isEmpty
                              ? 'Dividir en varias parcelas'
                              : 'Agregar parcelas a esta finca',
                        ),
                        subtitle: const Text(
                          'Opcional. Úsalo si separas zonas de cultivo.',
                        ),
                        value: _divide,
                        onChanged: (value) => setState(() {
                          _divide = value;
                          if (value && _parcels.isEmpty) {
                            _parcels.add(_ParcelDraft());
                          }
                        }),
                      ),
                      if (_divide) ...[
                        const Text(
                          'Las áreas de parcelas se indican en hectáreas. La ubicación de la finca sirve como referencia; puedes marcar un punto distinto para cada parcela.',
                        ),
                        for (final parcel in _parcels)
                          Card(
                            key: ObjectKey(parcel),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                children: [
                                  TextFormField(
                                    controller: parcel.name,
                                    decoration: const InputDecoration(
                                      labelText: 'Nombre de la parcela *',
                                      helperText:
                                          'Ejemplo: Zona norte o Cafetal 1.',
                                    ),
                                    maxLength: 120,
                                    validator: (v) => (v ?? '').trim().isEmpty
                                        ? 'Escribe cómo identificas esta parcela.'
                                        : null,
                                  ),
                                  TextFormField(
                                    controller: parcel.area,
                                    decoration: const InputDecoration(
                                      labelText: 'Área de esta parcela (ha) *',
                                    ),
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    validator: _positive,
                                  ),
                                  DropdownButtonFormField<String>(
                                    initialValue: parcel.crop ?? _crop,
                                    decoration: const InputDecoration(
                                      labelText: 'Cultivo de esta parcela',
                                    ),
                                    items: const [
                                      DropdownMenuItem(
                                        value: 'cafe',
                                        child: Text('Café'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'cacao',
                                        child: Text('Cacao'),
                                      ),
                                    ],
                                    onChanged: (value) => parcel.crop = value,
                                  ),
                                  LocationField(
                                    department: _department,
                                    municipality: _municipality,
                                    label:
                                        'Punto propio de la parcela (opcional)',
                                    geometry: parcel.geometry,
                                    center:
                                        pointFromGeometry(_geometry) ?? _center,
                                    required: false,
                                    onChanged: (value) =>
                                        parcel.geometry = value,
                                  ),
                                  TextButton.icon(
                                    onPressed: () => setState(() {
                                      _parcels.remove(parcel);
                                      parcel.dispose();
                                    }),
                                    icon: const Icon(
                                      Icons.remove_circle_outline,
                                    ),
                                    label: const Text('Quitar parcela'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        TextButton.icon(
                          onPressed: () =>
                              setState(() => _parcels.add(_ParcelDraft())),
                          icon: const Icon(Icons.add),
                          label: const Text('Agregar otra parcela'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving || _loading ? null : _save,
          child: Text(_saving ? 'Guardando…' : 'Guardar finca y parcelas'),
        ),
      ],
    );
  }
}
