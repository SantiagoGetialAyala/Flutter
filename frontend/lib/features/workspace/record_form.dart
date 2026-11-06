import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../core/services/api_client.dart';

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
  });
  final ApiClient api;
  final Map<String, dynamic> module;
  final Map<String, dynamic>? record;
  final Map<String, dynamic> initialValues;
  final Set<String> lockedFields;
  final ValueChanged<Map<String, dynamic>>? onSaved;
  final String? saveLabel, intro;
  @override
  State<RecordForm> createState() => _RecordFormState();
}

class _RecordFormState extends State<RecordForm> {
  final _form = GlobalKey<FormState>();
  final _controllers = <String, TextEditingController>{};
  final _values = <String, dynamic>{};
  final _relations = <String, List<Map<String, dynamic>>>{};
  bool _loading = true, _saving = false;
  String? _error;
  List<Map<String, dynamic>> get fields =>
      (widget.module['fields'] as List).cast<Map<String, dynamic>>();

  @override
  void initState() {
    super.initState();
    _initialize();
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
      if (mounted && response['administrator_invitation'] != null) {
        final invitation = response['administrator_invitation'];
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Tu nueva empresa está lista'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Comparte este código con ${invitation['email']}. Será el administrador de la empresa cuando lo acepte desde su cuenta.',
                ),
                const SizedBox(height: 20),
                const Text(
                  'CÓDIGO DE INVITACIÓN',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 8),
                SelectableText(
                  '${invitation['token']}',
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Válido durante 7 días. El correo de la cuenta debe coincidir con el de la invitación.',
                  style: TextStyle(fontSize: 12),
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

  String _label(Map<String, dynamic> item) =>
      '${item['name'] ?? item['title'] ?? item['business_name'] ?? item['code'] ?? item['reference'] ?? item['plate'] ?? item['email'] ?? (item['rate'] == null ? 'Registro #${item['id']}' : '${item['base_currency']} → ${item['target_currency']} · ${item['rate']}')}';

  Widget _field(Map<String, dynamic> field) {
    final key = field['key'] as String, type = field['type'];
    final label =
        '${field['label']}${field['required'] == true && widget.record == null ? ' *' : ''}';
    final required = field['required'] == true && widget.record == null;
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
      if (current != null && !items.any((item) => item.value == current)) {
        items.add(
          DropdownMenuItem(value: current, child: Text('Registro #$current')),
        );
      }
      return DropdownButtonFormField<String>(
        initialValue: current,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          helperText: items.isEmpty
              ? 'Primero crea un registro en el módulo relacionado.'
              : null,
        ),
        items: [
          if (!required)
            const DropdownMenuItem<String>(
              value: '',
              child: Text('Sin asignar'),
            ),
          ...items,
        ],
        onChanged: (v) => _values[key] = v == '' ? null : v,
        validator: (v) => required && (v == null || v.isEmpty)
            ? 'Selecciona una opción.'
            : null,
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
            : null,
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
      (widget.record == null || f['key'] != 'administrator_email');
  bool _isEssential(Map<String, dynamic> f) {
    if (!_isVisible(f)) return false;
    if (![
      'exports',
      'lots',
      'farms',
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
        ].contains(f['key']);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
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
                        (widget.module['key'] == 'exports' &&
                            widget.record == null))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 18),
                        child: Text(
                          widget.intro ??
                              'Paso 1 de 5 · Datos comerciales y destino. Guarda un borrador; los lotes, documentos y transporte se coordinan después con tu equipo.',
                        ),
                      ),
                    for (final field in fields.where(_isEssential))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _field(field),
                      ),
                    if (fields.any((f) => _isVisible(f) && !_isEssential(f)))
                      ExpansionTile(
                        title: const Text('Más detalles (opcional)'),
                        subtitle: const Text('Puedes completarlos después'),
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
                    (widget.module['key'] == 'exports' && widget.record == null
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
