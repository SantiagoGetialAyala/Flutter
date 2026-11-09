import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../core/services/api_client.dart';
import 'presentation.dart';
import 'farm_form.dart';
import 'location_field.dart';

class RecordForm extends StatefulWidget {
  const RecordForm({
    super.key,
    required this.api,
    required this.module,
    this.record,
    this.initialValues = const {},
    this.lockedFields = const {},
    this.onSaved,
    this.saveLabel,
    this.intro,
    this.modules = const [],
  });
  final ApiClient api;
  final Map<String, dynamic> module;
  final Map<String, dynamic>? record;
  final Map<String, dynamic> initialValues;
  final Set<String> lockedFields;
  final ValueChanged<Map<String, dynamic>>? onSaved;
  final String? saveLabel, intro;
  final List<Map<String, dynamic>> modules;
  @override
  State<RecordForm> createState() => _RecordFormState();
}

class _RecordFormState extends State<RecordForm> {
  final _form = GlobalKey<FormState>();
  final _controllers = <String, TextEditingController>{};
  final _values = <String, dynamic>{};
  final _relations = <String, List<Map<String, dynamic>>>{};
  bool _loading = true, _saving = false;
  bool _boundaryGeometry = false;
  String? _error;
  List<Map<String, dynamic>> get fields =>
      (widget.module['fields'] as List).cast<Map<String, dynamic>>();

  @override
  void initState() {
    super.initState();
    if (widget.module['key'] != 'farms') _initialize();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      for (final field in fields) {
        if (widget.record != null && field['key'] == 'administrator_email') {
          continue;
        }
        final key = field['key'] as String;
        final initial =
            widget.record?[key] ??
            widget.initialValues[key] ??
            field['default'];
        if (field['type'] == 'bool') {
          _values[key] =
              initial ??
              (key == 'is_active' || key == 'mandatory' || key == 'enabled');
        } else if (field['type'] == 'relation' || field['type'] == 'choice') {
          _values[key] = initial?.toString();
        } else {
          _controllers[key] = TextEditingController(
            text: initial == null
                ? ''
                : field['type'] == 'json'
                ? jsonEncode(initial)
                : '$initial',
          );
        }
      }
      final endpoints = fields
          .where(
            (f) =>
                f['type'] == 'relation' &&
                !widget.lockedFields.contains(f['key']),
          )
          .map((f) => f['endpoint'] as String)
          .toSet();
      final geometry = _controllers['geometry']?.text ?? '';
      if (_controllers.containsKey('geometry')) {
        final parsed = geometry.isEmpty ? null : jsonDecode(geometry);
        _boundaryGeometry = parsed != null && parsed['type'] != 'Point';
      }
      await Future.wait(
        endpoints.map((endpoint) async {
          final exportId = widget.initialValues['export'];
          final query =
              exportId != null && ['documents', 'transports'].contains(endpoint)
              ? '?export=$exportId'
              : '';
          _relations[endpoint] = await widget.api.getAll('/$endpoint/$query');
        }),
      );
      if (widget.module['key'] == 'plots' &&
          widget.lockedFields.contains('farm') &&
          _values['farm'] != null) {
        _relations['farms'] = [
          await widget.api.getMap('/farms/${_values['farm']}/'),
        ];
      }
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final data = <String, dynamic>{};
      for (final field in fields) {
        if (widget.record != null && field['key'] == 'administrator_email') {
          continue;
        }
        final key = field['key'] as String, type = field['type'];
        if (type == 'bool') {
          data[key] = _values[key];
          continue;
        }
        if (type == 'relation' || type == 'choice') {
          final value = _values[key];
          if (value != null) {
            data[key] =
                type == 'relation' && field['endpoint'] != 'role-options'
                ? int.parse('$value')
                : value;
          } else if (widget.record != null && field['nullable'] == true) {
            data[key] = null;
          }
          continue;
        }
        final text = _controllers[key]!.text.trim();
        if (text.isEmpty) {
          if (widget.record != null && type != 'password') {
            if (field['nullable'] == true) {
              data[key] = null;
            } else if (type == 'text') {
              data[key] = '';
            }
          }
          continue;
        }
        data[key] = type == 'json'
            ? jsonDecode(text)
            : type == 'datetime'
            ? DateTime.parse(text).toUtc().toIso8601String()
            : text;
      }
      final path = '/${widget.module['key']}/';
      Map<String, dynamic> response;
      if (widget.record == null) {
        response = await widget.api.post(path, data);
      } else {
        response = await widget.api.patch(
          '$path${widget.record!['id']}/',
          data,
        );
      }
      if (mounted &&
          (response['administrator_invitation'] != null ||
              (widget.module['key'] == 'invitations' &&
                  response['token'] != null))) {
        final invitation = response['administrator_invitation'] ?? response;
        final companyCreated = response['administrator_invitation'] != null;
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(
              companyCreated
                  ? 'Tu nueva empresa está lista'
                  : 'Invitación lista para compartir',
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Indica a ${invitation['email']} que abra Crear cuenta y use ese mismo correo. La empresa y el rol que asignaste se aplican automáticamente; no necesita elegir rol ni escribir un código.',
                ),
                const SizedBox(height: 12),
                const Text('La invitación está vigente durante 7 días.'),
                ExpansionTile(
                  title: const Text('Si la persona ya tiene cuenta'),
                  children: [
                    const Text('Puede iniciar sesión y usar Aceptar invitación con este código:'),
                    SelectableText('${invitation['token']}'),
                  ],
                ),
              ],
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Entendido'),
              ),
            ],
          ),
        );
      }
      widget.onSaved?.call(response);
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

  String _label(Map<String, dynamic> item) {
    if (item['harvest_date'] != null) {
      return 'Cosecha ${item['harvest_date']} · ${item['farm_name'] ?? ''} · ${item['plot_name'] ?? ''}';
    }
    final label =
        '${item['name'] ?? item['title'] ?? item['business_name'] ?? item['code'] ?? item['reference'] ?? item['plate'] ?? item['email'] ?? (item['rate'] == null ? 'Registro #${item['id']}' : '${item['base_currency']} → ${item['target_currency']} · ${item['rate']}')}';
    return item['farm_name'] == null ? label : '$label · ${item['farm_name']}';
  }

  Future<void> _invitePerson() async {
    final invitation = widget.modules
        .where((m) => m['key'] == 'invitations')
        .firstOrNull;
    if (invitation?['can_create'] != true) return;
    await showDialog<bool>(
      context: context,
      builder: (_) => RecordForm(
        api: widget.api,
        module: invitation!,
        modules: widget.modules,
        intro:
            'Registra el correo y el rol. La persona solo debe crear su cuenta con ese correo; la empresa y el rol se asignan automáticamente.',
      ),
    );
    if (!mounted) return;
    try {
      final team = await widget.api.getAll('/team/');
      if (mounted) setState(() => _relations['team'] = team);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _createRelated(Map<String, dynamic> field) async {
    final endpoint = field['endpoint'] as String;
    final module = widget.modules
        .where((m) => m['key'] == endpoint)
        .firstOrNull;
    if (module == null || module['can_create'] != true) return;
    Map<String, dynamic>? created;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => RecordForm(
        api: widget.api,
        module: module,
        modules: widget.modules,
        initialValues:
            endpoint == 'documents' && widget.initialValues['export'] != null
            ? {'export': widget.initialValues['export']}
            : const {},
        onSaved: (row) => created = row,
      ),
    );
    if (saved != true || !mounted) return;
    try {
      final rows = await widget.api.getAll('/$endpoint/');
      if (mounted) {
        setState(() {
          _relations[endpoint] = rows;
          _values[field['key']] = '${created!['id']}';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Widget _field(Map<String, dynamic> field) {
    final key = field['key'] as String, type = field['type'];
    final label =
        '${field['label']}${field['required'] == true && widget.record == null ? ' *' : ''}';
    final required = field['required'] == true && widget.record == null;
    if (key == 'geometry' && !_boundaryGeometry) {
      final text = _controllers[key]!.text;
      final farm = (_relations['farms'] ?? [])
          .where((row) => '${row['id']}' == '${_values['farm']}')
          .firstOrNull;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LocationField(
            label: 'Ubicación de la parcela',
            geometry: text.isEmpty ? null : jsonDecode(text),
            department: farm?['department'],
            municipality: farm?['municipality'],
            center: pointFromGeometry(farm?['geometry']),
            onChanged: (geometry) =>
                _controllers[key]!.text = jsonEncode(geometry),
          ),
          TextButton(
            onPressed: () => setState(() => _boundaryGeometry = true),
            child: const Text('Registrar límites del terreno (avanzado)'),
          ),
        ],
      );
    }
    if (type == 'bool') {
      return SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        value: _values[key] == true,
        onChanged: (v) => setState(() => _values[key] = v),
      );
    }
    if (type == 'choice' || type == 'relation') {
      final items = type == 'relation'
          ? (_relations[field['endpoint']] ?? [])
                .where(
                  (item) =>
                      widget.module['key'] != 'transports' ||
                      key != 'assigned_to' ||
                      item['role'] == 'logistica',
                )
                .map(
                  (item) => DropdownMenuItem<String>(
                    value: '${item['id']}',
                    child: Text(_label(item), overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList()
          : (field['choices'] as List)
                .map(
                  (item) => DropdownMenuItem<String>(
                    value: '${item['value']}',
                    child: Text(
                      '${item['label']}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList();
      final current = _values[key] as String?;
      final roleDescription = (_relations['role-options'] ?? [])
          .where((r) => '${r['id']}' == current)
          .firstOrNull?['description'];
      if (current != null && !items.any((item) => item.value == current)) {
        items.add(
          DropdownMenuItem(
            value: current,
            child: Text(type == 'choice' ? current : 'Registro #$current'),
          ),
        );
      }
      final endpoint = '${field['endpoint']}';
      final related = widget.modules
          .where((m) => m['key'] == endpoint)
          .firstOrNull;
      final relatedLabel =
          related?['label'] ?? moduleLabel(endpoint, '${field['label']}');
      final dropdown = DropdownButtonFormField<String>(
        key: ValueKey('$key:$current:${items.length}'),
        initialValue: current,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          helperText:
              widget.module['key'] == 'transports' && key == 'assigned_to'
              ? (items.isEmpty
                    ? 'El administrador debe invitar a una persona con rol Transportador.'
                    : 'Esta persona verá la entrega en Mis envíos y recibirá una notificación.')
              : items.isEmpty
              ? 'Falta registrar: $relatedLabel.'
              : endpoint == 'role-options'
              ? roleDescription?.toString()
              : null,
          helperMaxLines: 3,
        ),
        items: [
          if (!required)
            const DropdownMenuItem<String>(
              value: '',
              child: Text('Sin asignar'),
            ),
          ...items,
        ],
        onChanged: (v) => setState(() => _values[key] = v == '' ? null : v),
        validator: (v) => required && (v == null || v.isEmpty)
            ? 'Selecciona una opción.'
            : null,
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          dropdown,
          if (type == 'relation' &&
              endpoint == 'team' &&
              widget.modules.any(
                (m) => m['key'] == 'invitations' && m['can_create'] == true,
              ))
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _saving ? null : _invitePerson,
                icon: const Icon(Icons.person_add_outlined, size: 18),
                label: const Text('Invitar persona aquí'),
              ),
            ),
          if (type == 'relation' && related?['can_create'] == true)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _saving ? null : () => _createRelated(field),
                icon: const Icon(Icons.add_circle_outline, size: 18),
                label: Text('Crear aquí: $relatedLabel'),
              ),
            )
          else if (type == 'relation' && items.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                endpoint == 'team'
                    ? 'El administrador debe invitar a esa persona desde Equipo → Invitaciones. Después debe aceptar el código con su correo.'
                    : 'Pide a ${endpoint == 'lots' || endpoint == 'producers' || endpoint == 'farms' || endpoint == 'harvests'
                          ? 'tu productor'
                          : endpoint == 'clients' || endpoint == 'exports'
                          ? 'tu administrador'
                          : 'la persona responsable'} que registre $relatedLabel.',
              ),
            ),
        ],
      );
    }
    final controller = _controllers[key]!;
    final date = type == 'date' || type == 'datetime';
    return TextFormField(
      controller: controller,
      obscureText: type == 'password',
      maxLines: type == 'json'
          ? 4
          : key == 'notes' || key == 'description' || key == 'reason'
          ? 3
          : 1,
      keyboardType: type == 'number'
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        helperText: type == 'date'
            ? 'AAAA-MM-DD'
            : type == 'datetime'
            ? 'AAAA-MM-DDTHH:MM · hora local'
            : key == 'geometry'
            ? 'Ubicación de la parcela. Punto: {"type":"Point","coordinates":[-74.081750,4.609710]}. Orden: longitud, latitud; usa tus coordenadas reales.'
            : key == 'location' && type == 'json'
            ? 'Lugar donde ocurrió el evento: {"latitude":4.609710,"longitude":-74.081750}. Usa tus coordenadas reales.'
            : null,
        helperMaxLines: 4,
        suffixIcon: date
            ? IconButton(
                icon: const Icon(Icons.calendar_month),
                onPressed: () async {
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: DateTime.tryParse(controller.text) ?? now,
                    firstDate: DateTime(1950),
                    lastDate: DateTime(2100),
                  );
                  if (picked == null || !mounted) return;
                  if (type == 'datetime') {
                    final time = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.now(),
                    );
                    if (time == null) return;
                    controller.text = DateTime(
                      picked.year,
                      picked.month,
                      picked.day,
                      time.hour,
                      time.minute,
                    ).toIso8601String();
                  } else {
                    controller.text = picked.toIso8601String().split('T').first;
                  }
                },
              )
            : key == 'geometry'
            ? IconButton(
                tooltip: 'Usar un punto con latitud y longitud',
                icon: const Icon(Icons.location_on_outlined),
                onPressed: () => setState(() => _boundaryGeometry = false),
              )
            : null,
      ),
      validator: (text) {
        final value = text?.trim() ?? '';
        if (required && value.isEmpty) return 'Este campo es obligatorio.';
        if (value.isEmpty) return null;
        if (type == 'number' && num.tryParse(value) == null) {
          return 'Ingresa un número válido con punto decimal.';
        }
        if (date && DateTime.tryParse(value) == null) {
          return 'Ingresa una fecha válida.';
        }
        if (type == 'json') {
          try {
            jsonDecode(value);
          } catch (_) {
            return 'Ingresa JSON válido.';
          }
        }
        return null;
      },
    );
  }

  bool _isVisible(Map<String, dynamic> f) =>
      !widget.lockedFields.contains(f['key']) &&
      (widget.record == null || f['key'] != 'administrator_email') &&
      !(widget.module['key'] == 'plots' &&
          ['code', 'crop', 'evidence'].contains(f['key']));
  bool _isEssential(Map<String, dynamic> f) {
    if (!_isVisible(f)) return false;
    if (![
      'exports',
      'lots',
      'farms',
      'plots',
      'producers',
      'harvests',
      'documents',
      'transports',
    ].contains(widget.module['key'])) {
      return true;
    }
    return f['required'] == true ||
        [
          'code',
          'name',
          'destination_country',
          'importer',
          'estimated_departure',
          'estimated_arrival',
          'currency',
          'title',
          'document_type',
          'export',
          'harvest',
          'unit',
        ].contains(f['key']);
  }

  @override
  Widget build(BuildContext context) => widget.module['key'] == 'farms'
      ? FarmForm(
          api: widget.api,
          modules: widget.modules,
          record: widget.record,
          initialValues: widget.initialValues,
          onSaved: widget.onSaved,
        )
      : AlertDialog(
          title: Text(
            widget.module['key'] == 'exports' && widget.record == null
                ? 'Iniciar operación'
                : '${widget.record == null ? 'Nuevo' : 'Editar'} · ${widget.module['label']}',
          ),
          content: SizedBox(
            width: 620,
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    child: Form(
                      key: _form,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Text(
                                _error!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                          if (widget.intro != null ||
                              widget.module['key'] == 'invitations' ||
                              (widget.module['key'] == 'transports' &&
                                  widget.record == null) ||
                              (widget.module['key'] == 'exports' &&
                                  widget.record == null))
                            Padding(
                              padding: const EdgeInsets.only(bottom: 18),
                              child: Text(
                                widget.intro ??
                                    (widget.module['key'] == 'invitations'
                                        ? 'El administrador invita al equipo. Productor registra mercancía; Transportador hace las entregas; Importador confirma recepción. Otro Administrador puede ayudarte a gestionar exportaciones, documentos y pagos.'
                                        : widget.module['key'] == 'transports'
                                        ? 'Elige el transportador responsable, los lugares de recogida y entrega y la fecha prevista. Al guardar, esa persona recibe una notificación y la carga aparece en Mis envíos. Solo ella registra recogida, salida y entrega.'
                                        : 'Paso 1 de 5 · Datos comerciales y destino. Guarda un borrador; los lotes, documentos y transporte se coordinan después con tu equipo.'),
                              ),
                            ),
                          for (final field in fields.where(_isEssential))
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: _field(field),
                            ),
                          if (fields.any(
                            (f) => _isVisible(f) && !_isEssential(f),
                          ))
                            ExpansionTile(
                              title: const Text('Más detalles (opcional)'),
                              subtitle: const Text(
                                'Puedes completarlos después',
                              ),
                              tilePadding: EdgeInsets.zero,
                              maintainState: true,
                              children: [
                                for (final field in fields.where(
                                  (f) => _isVisible(f) && !_isEssential(f),
                                ))
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 16),
                                    child: _field(field),
                                  ),
                              ],
                            ),
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
              child: Text(
                _saving
                    ? 'Guardando…'
                    : widget.saveLabel ??
                          (widget.module['key'] == 'exports' &&
                                  widget.record == null
                              ? 'Guardar borrador'
                              : 'Guardar'),
              ),
            ),
          ],
        );
}

Future<bool?> openTransportEventForm({
  required BuildContext context,
  required ApiClient api,
  required Map<String, dynamic> module,
  required Map<String, dynamic> transport,
  dynamic exportId,
  List<Map<String, dynamic>> modules = const [],
}) {
  final state = transport['status'];
  final permitted =
      {
        'asignado': ['recogida'],
        'recogido': ['inicio'],
        'en_transito': ['entrega'],
      }[state] ??
      <String>[];
  final fields = (module['fields'] as List)
      .cast<Map<String, dynamic>>()
      .map(
        (f) => f['key'] == 'event_type'
            ? <String, dynamic>{
                ...f,
                'choices': (f['choices'] as List)
                    .where(
                      (c) => [
                        ...permitted,
                        'seguimiento',
                        'incidencia',
                      ].contains(c['value']),
                    )
                    .toList(),
              }
            : f,
      )
      .toList();
  return showDialog<bool>(
    context: context,
    builder: (_) => RecordForm(
      api: api,
      module: {...module, 'fields': fields},
      modules: modules,
      initialValues: {
        'transport': transport['id'],
        'export': exportId ?? transport['export'],
      },
      lockedFields: {'transport'},
      intro:
          'Envío #${transport['id']}. Para recogida, salida o entrega, selecciona un documento con archivo de evidencia. Puedes prepararlo desde Documentos.',
    ),
  );
}
