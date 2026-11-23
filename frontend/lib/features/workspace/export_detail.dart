import 'package:flutter/material.dart';
import '../../../core/services/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/brand.dart';
import 'presentation.dart';
import 'record_form.dart';
import 'operation_map.dart';
import 'workflow.dart';
import 'finance_report.dart';

class ExportDetail extends StatefulWidget {
  const ExportDetail({
    super.key,
    required this.api,
    required this.record,
    required this.canTransition,
    required this.onTransition,
    this.canViewDocuments = false,
    this.modules = const [],
    this.onResourceAction,
  });
  final ApiClient api;
  final List<Map<String, dynamic>> modules;
  final Future<void> Function(String, Map<String, dynamic>, String)?
  onResourceAction;
  final Map<String, dynamic> record;
  final bool canTransition, canViewDocuments;
  final Future<void> Function(Map<String, dynamic>) onTransition;
  @override
  State<ExportDetail> createState() => _ExportDetailState();
}

class _ExportDetailState extends State<ExportDetail> {
  late Map<String, dynamic> _record = widget.record;
  List<Map<String, dynamic>> _history = [];
  bool _loading = true;
  bool _savingProgress = false;
  String? _error;
  String? _savedMessage;
  int _tab = 0;
  late int _focusStage = lifecycleStage('${_record["status"]}');
  int _revision = 0;
  final _resources = <String, List<Map<String, dynamic>>>{};
  final _resourceErrors = <String, String>{};
  Map<String, dynamic>? _module(String key) =>
      widget.modules.where((m) => m['key'] == key).firstOrNull;
  bool _canCreate(String key) => _module(key)?['can_create'] == true;
  bool get _terminal =>
      ['cerrada', 'cancelada', 'rechazada'].contains(_record['status']);

  double _inKilograms(dynamic quantity, dynamic unit) {
    final value = double.tryParse('$quantity') ?? 0;
    return unit == 'tonelada' ? value * 1000 : value;
  }

  double get _allocatedKilograms =>
      (_resources['export-allocations'] ?? []).fold<double>(
        0,
        (total, row) => total + _inKilograms(row['quantity'], row['unit']),
      );

  Map<String, dynamic>? get _importRequest =>
      (_resources['orders'] ?? []).firstOrNull;

  bool get _allocationComplete {
    final request = _importRequest;
    if (request == null)
      return (_resources['export-allocations'] ?? []).isNotEmpty;
    return _allocatedKilograms + .000001 >=
        _inKilograms(request['quantity'], request['unit']);
  }

  String get _allocationProgressLabel {
    final request = _importRequest;
    if (request == null) {
      return (_resources['export-allocations'] ?? []).isEmpty
          ? 'Reserva al menos un lote para continuar.'
          : 'Lotes guardados. Ya puedes seguir con la importación.';
    }
    final allocated = number(_allocatedKilograms);
    final requested = number(
      _inKilograms(request['quantity'], request['unit']),
    );
    return _allocationComplete
        ? '$allocated de $requested kg reservados. Todo listo para continuar.'
        : 'Hay $allocated de $requested kg reservados. Completa la cantidad solicitada.';
  }

  List<Map<String, dynamic>> get _completionGaps {
    if (_record['status'] == 'cerrada') return const [];
    final gaps = <Map<String, dynamic>>[];
    void add(String title, String owner, String key, int stage) {
      gaps.add({'title': title, 'owner': owner, 'key': key, 'stage': stage});
    }

    final order = _importRequest;
    if (order == null) {
      if (_module('orders') != null) {
        add(
          'Registrar y vincular el pedido del importador',
          'Importador y administrador',
          'orders',
          1,
        );
      }
    } else {
      if (_module('export-allocations') != null && !_allocationComplete) {
        add(
          'Reservar los lotes hasta completar ${number(_inKilograms(order['quantity'], order['unit']))} kg',
          'Administrador / equipo exportador',
          'export-allocations',
          1,
        );
      }
      final docs = _resources['documents'] ?? [];
      for (final name
          in _module('documents') == null
              ? const <dynamic>[]
              : (order['requested_documents'] as List? ?? const [])) {
        final expected = _normalizeDocument('$name');
        final found = docs.any((doc) {
          final type = _normalizeDocument('${doc['document_type'] ?? ''}');
          final title = _normalizeDocument('${doc['title'] ?? ''}');
          return (type == expected ||
                  title == expected ||
                  (type.isNotEmpty && expected.contains(type))) &&
              doc['status'] == 'aprobado' &&
              (doc['versions'] as List? ?? const []).isNotEmpty;
        });
        if (!found)
          add(
            'Cargar y aprobar el documento solicitado: $name',
            'Empresa / responsable documental',
            'documents',
            2,
          );
      }
    }

    if (_module('requirements') != null) {
      final requirements = _resources['requirements'] ?? [];
      if (requirements.isEmpty) {
        add(
          'Configurar al menos un requisito obligatorio del destino',
          'Administrador / responsable documental',
          'requirements',
          2,
        );
      }
      for (final requirement in requirements.where(
        (row) => row['mandatory'] != false,
      )) {
        final type = _normalizeDocument(
          '${requirement['document_type'] ?? ''}',
        );
        final documentReady = (_resources['documents'] ?? []).any(
          (doc) =>
              _normalizeDocument('${doc['document_type'] ?? ''}') == type &&
              doc['status'] == 'aprobado' &&
              (doc['versions'] as List? ?? const []).isNotEmpty,
        );
        final checked = (_resources['checklist'] ?? []).any(
          (item) =>
              '${item['requirement']}' == '${requirement['id']}' &&
              item['passed'] == true,
        );
        if (!documentReady || !checked) {
          add(
            'Cumplir el requisito: ${requirement['name']}',
            'Empresa / responsable documental',
            'requirements',
            2,
          );
        }
      }
      final compliant = (_resources['compliance'] ?? []).any(
        (row) => row['result'] == 'conforme',
      );
      if (!compliant)
        add(
          'Registrar una evaluación de cumplimiento conforme',
          'Responsable documental',
          'compliance',
          2,
        );
    }

    if (_module('transports') != null &&
        (!['entregada', 'cerrada'].contains(_record['status']) ||
            !(_resources['transports'] ?? []).any(
              (row) => row['status'] == 'entregado',
            ))) {
      add(
        'Finalizar el transporte y registrar la entrega',
        'Transportador y empresa',
        'transports',
        3,
      );
    }
    if (_module('orders') != null &&
        order != null &&
        order['received_at'] == null) {
      add('Confirmar la recepción de la mercancía', 'Importador', 'orders', 1);
    }
    return gaps;
  }

  String _normalizeDocument(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  Widget _completionPanel() {
    final gaps = _completionGaps;
    return Card(
      color: gaps.isEmpty ? const Color(0xFFEAF3E9) : const Color(0xFFFFF7E6),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              gaps.isEmpty
                  ? 'Todo listo para cerrar'
                  : 'Falta completar ${gaps.length} paso(s)',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 5),
            Text(
              gaps.isEmpty
                  ? 'La operación cumple los pasos requeridos.'
                  : 'Abre un pendiente para ir a la sección y ver quién debe resolverlo.',
            ),
            if (gaps.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final gap in gaps)
                TextButton.icon(
                  style: TextButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(vertical: 5),
                  ),
                  onPressed: () => setState(() {
                    _tab = 1;
                    _focusStage = gap['stage'] as int;
                  }),
                  icon: const Icon(Icons.error_outline, size: 18),
                  label: Text('${gap['title']} · ${gap['owner']}'),
                ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _resourceErrors.clear();
    });
    final revision = ++_revision;
    final keys = [
      'documents',
      'requirements',
      'export-allocations',
      'traceability-events',
      'checklist',
      'compliance',
      'transports',
      'finance',
      'quotes',
      'activities',
      'incidents',
      'approvals',
      'orders',
    ];
    await Future.wait([
      () async {
        try {
          final record = await widget.api.getMap('/exports/${_record['id']}/');
          if (mounted && revision == _revision) _record = record;
        } catch (e) {
          if (mounted && revision == _revision) {
            _error = 'No pudimos actualizar el expediente. $e';
          }
        }
      }(),
      () async {
        try {
          final history = await widget.api.getAll(
            '/exports/${_record['id']}/history/',
          );
          if (mounted && revision == _revision) _history = history;
        } catch (e) {
          if (mounted && revision == _revision) {
            _error = 'No pudimos cargar el historial. $e';
          }
        }
      }(),
      for (final key in keys)
        if (_module(key) != null ||
            (key == 'documents' && widget.canViewDocuments))
          () async {
            try {
              final rows = await widget.api.getAll(
                '/$key/?export=${_record['id']}',
              );
              if (mounted && revision == _revision) {
                _resources[key] = key == 'requirements'
                    ? rows
                          .where(
                            (r) =>
                                r['is_active'] != false &&
                                ('${r['destination_country'] ?? ''}'.isEmpty ||
                                    '${r['destination_country']}'
                                            .toLowerCase() ==
                                        '${_record['destination_country']}'
                                            .toLowerCase()),
                          )
                          .toList()
                    : rows;
              }
            } catch (e) {
              if (mounted && revision == _revision) {
                _resourceErrors[key] = 'No pudimos cargar esta sección. $e';
              }
            }
          }(),
    ]);
    if (mounted && revision == _revision) setState(() => _loading = false);
  }

  Future<void> _form(String key, {Map<String, dynamic>? row}) async {
    final module = _module(key);
    if (module == null ||
        (row == null
            ? module['can_create'] != true
            : module['can_update'] != true)) {
      return;
    }
    final fields = (module['fields'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    final hasExport = fields.any((f) => f['key'] == 'export');
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => RecordForm(
        api: widget.api,
        module: module,
        modules: widget.modules,
        record: row,
        initialValues: {
          if (hasExport) 'export': _record['id'],
          if (key == 'requirements')
            'destination_country': _record['destination_country'],
        },
        lockedFields: hasExport ? {'export'} : {},
        intro: key == 'requirements'
            ? 'Este requisito se aplicará a las exportaciones con destino a ${_record['destination_country']}. Después carga el documento y verifica el requisito en este expediente.'
            : 'Este registro pertenece a la operación ${_record['code']}.',
      ),
    );
    if (saved == true) {
      try {
        final record = await widget.api.getMap('/exports/${_record['id']}/');
        if (mounted) setState(() => _record = record);
      } catch (e) {
        if (mounted) setState(() => _error = '$e');
      }
      if (mounted) await _load();
    }
  }

  Future<void> _transition() async {
    try {
      await widget.onTransition(_record);
      final record = await widget.api.getMap('/exports/${_record['id']}/');
      if (mounted) setState(() => _record = record);
      if (mounted) await _load();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _continueImportation() async {
    if (_savingProgress || !_allocationComplete) return;
    setState(() {
      _savingProgress = true;
      _error = null;
    });
    try {
      await widget.api.post('/exports/${_record['id']}/transition/', {
        'status': 'pendiente_documentacion',
        'notes':
            'Lotes reservados. Continuar con los documentos de importación.',
      });
      final record = await widget.api.getMap('/exports/${_record['id']}/');
      if (!mounted) return;
      setState(() {
        _record = record;
        _focusStage = 2;
        _tab = 1;
      });
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _savingProgress = false);
    }
  }

  Future<void> _saveProgress() async {
    if (_savingProgress || _terminal) return;
    setState(() {
      _savingProgress = true;
      _error = null;
      _savedMessage = null;
    });
    try {
      await widget.api.post('/exports/${_record['id']}/checkpoint/', {});
      await _load();
      if (mounted) {
        setState(
          () => _savedMessage = 'Avance guardado y expediente actualizado.',
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _savingProgress = false);
    }
  }

  Future<void> _map() async {
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog.fullscreen(
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Volver al expediente'),
                ),
              ),
              Expanded(
                child: OperationMap(
                  api: widget.api,
                  modules: widget.modules.map((m) => '${m['key']}').toSet(),
                  exportId: _record['id'] as int,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final mobile = size.width < 650;
    const tabs = ['Resumen', 'Expediente', 'Seguimiento'];
    return Dialog(
      insetPadding: EdgeInsets.all(mobile ? 0 : 32),
      backgroundColor: AppTheme.background,
      child: SizedBox(
        width: 760,
        height: mobile ? size.height : size.height * .9,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 17, 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                    ),
                    Expanded(
                      child: Text(
                        '${_record['code']}',
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -.5,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _load,
                      tooltip: 'Actualizar expediente',
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    for (var i = 0; i < tabs.length; i++)
                      Expanded(
                        child: InkWell(
                          onTap: () => setState(() => _tab = i),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  width: _tab == i ? 2 : 1,
                                  color: _tab == i
                                      ? AppTheme.forest
                                      : AppTheme.line,
                                ),
                              ),
                            ),
                            child: Text(
                              tabs[i],
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: _tab == i
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                                color: _tab == i
                                    ? AppTheme.forest
                                    : AppTheme.muted,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(15),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              if (_loading) const LinearProgressIndicator(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: switch (_tab) {
                    0 => _summary(),
                    1 => _dossier(),
                    _ => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _map,
                          icon: const Icon(Icons.map_outlined),
                          label: const Text('Mapa y puntos logísticos'),
                        ),
                        const SizedBox(height: 16),
                        _timeline(),
                        _resourceSection(
                          'traceability-events',
                          'Eventos de trazabilidad',
                        ),
                      ],
                    ),
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summary() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _nextAction(),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: const Color(0xFFF0EFE9),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            const OriginImage(
              width: 68,
              height: 80,
              alignment: Alignment(0, .85),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_record['code']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${(_record['allocations'] as List? ?? []).length} lotes de origen',
                    style: const TextStyle(fontSize: 11, color: AppTheme.muted),
                  ),
                  const SizedBox(height: 9),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${_record['destination_country']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                      const SizedBox(width: 5),
                      StatusPill(_record['status']),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
          child: Column(
            children: [
              _row(
                Icons.people_outline,
                'Cliente / importador',
                '${_record['importer_name'] ?? 'Por definir'}',
              ),
              _row(
                Icons.local_shipping_outlined,
                'Transportador',
                '${_record['transporter_name'] ?? 'Por asignar'}',
              ),
              _row(
                Icons.receipt_long_outlined,
                'Incoterm',
                _record['incoterm'] == ''
                    ? 'Por definir'
                    : '${_record['incoterm'] ?? 'Por definir'}',
              ),
              if (_record['net_weight'] != null)
                _row(
                  Icons.scale_outlined,
                  'Peso neto',
                  '${number(_record['net_weight'])} kg',
                ),
              if (_record['commercial_value'] != null)
                _row(
                  Icons.payments_outlined,
                  'Valor comercial',
                  '${_record['currency']} ${number(_record['commercial_value'])}',
                ),
              _row(
                Icons.event_outlined,
                'Salida estimada',
                dateText(_record['estimated_departure']),
              ),
              _row(
                Icons.schedule_outlined,
                'Llegada estimada',
                dateText(_record['estimated_arrival']),
                last: true,
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Progreso de la operación',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: exportProgress(_record['status']),
                  color: const Color(0xFF438558),
                  backgroundColor: AppTheme.line,
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(
                    Icons.location_on_outlined,
                    size: 16,
                    color: AppTheme.forest,
                  ),
                  Expanded(
                    child: Text(
                      ' ${_record['origin_country'] ?? 'Colombia'}',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    size: 15,
                    color: AppTheme.muted,
                  ),
                  Expanded(
                    child: Text(
                      '${_record['destination_country']}',
                      textAlign: TextAlign.end,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Text(
                friendly(_record['status']),
                style: const TextStyle(fontSize: 11, color: AppTheme.muted),
              ),
            ],
          ),
        ),
      ),
      if (_record['commercial_terms'] != null &&
          _record['commercial_terms'] != '') ...[
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Condiciones comerciales',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text('${_record['commercial_terms']}'),
              ],
            ),
          ),
        ),
      ],
    ],
  );

  Widget _nextAction() {
    return Card(
      color: AppTheme.ivory,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                StatusPill(_record['status']),
                Text(
                  _terminal
                      ? 'Expediente conservado'
                      : 'Etapa ${lifecycleStage('${_record['status']}') + 1} de 5',
                  style: const TextStyle(color: AppTheme.coffee),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              nextStep('${_record['status']}'),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            _completionPanel(),
            const SizedBox(height: 12),
            if (!_terminal)
              FilledButton.icon(
                onPressed: () => setState(() {
                  _focusStage = _record['status'] == 'borrador'
                      ? 1
                      : lifecycleStage('${_record['status']}');
                  _tab = 1;
                }),
                icon: const Icon(Icons.folder_open_outlined),
                label: Text(
                  _record['status'] == 'borrador'
                      ? 'Preparar productos y lotes'
                      : 'Ver mi trabajo en el expediente',
                ),
              ),
            if (_record['status'] == 'borrador' &&
                widget.canTransition &&
                (_record['allowed_transitions'] as List? ?? []).contains(
                  'pendiente_documentacion',
                )) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _savingProgress || _loading ? null : _saveProgress,
                icon: _savingProgress
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync),
                label: Text(
                  _savingProgress ? 'Guardando…' : 'Guardar y actualizar',
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _savingProgress || _loading || !_allocationComplete
                    ? null
                    : _continueImportation,
                icon: const Icon(Icons.arrow_forward),
                label: const Text('Continuar a documentos'),
              ),
              const SizedBox(height: 6),
              Text(
                _allocationProgressLabel,
                style: TextStyle(
                  fontSize: 11,
                  color: _allocationComplete ? AppTheme.forest : AppTheme.muted,
                ),
              ),
            ],
            if (_savedMessage != null) ...[
              const SizedBox(height: 6),
              Text(
                _savedMessage!,
                style: const TextStyle(color: AppTheme.forest, fontSize: 12),
              ),
            ],
            const SizedBox(height: 8),
            const Text(
              'Puedes salir y continuar después. Cada etapa se completa con el equipo responsable.',
              style: TextStyle(fontSize: 11, color: AppTheme.muted),
            ),
            const SizedBox(height: 12),
            ExpansionTile(
              title: const Text(
                'Plan de trabajo · 5 etapas',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              tilePadding: EdgeInsets.zero,
              children: [
                for (var i = 0; i < lifecycleStages.length; i++)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      radius: 14,
                      backgroundColor:
                          i == lifecycleStage('${_record['status']}')
                          ? AppTheme.forest
                          : AppTheme.background,
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(
                          fontSize: 12,
                          color: i == lifecycleStage('${_record['status']}')
                              ? Colors.white
                              : AppTheme.muted,
                        ),
                      ),
                    ),
                    title: Text(
                      lifecycleStages[i],
                      style: const TextStyle(fontSize: 12),
                    ),
                    subtitle: Text(lifecycleGuides[i]),
                    trailing: const Icon(Icons.chevron_right, size: 18),
                    onTap: () {
                      if (i == 0 &&
                          _module('exports')?['can_update'] == true &&
                          !_terminal) {
                        _form('exports', row: _record);
                        return;
                      }
                      setState(() {
                        _focusStage = i;
                        _tab = i == 4 ? 2 : 1;
                      });
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _dossier() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Completa esta exportación',
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 6),
      const Text(
        'Pedido → documentos → transporte → cierre. Cada sección indica quién la completa.',
        style: TextStyle(color: AppTheme.muted),
      ),
      if (_module('exports')?['can_update'] == true && !_terminal) ...[
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _savingProgress || _loading ? null : _saveProgress,
          icon: _savingProgress
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.sync),
          label: Text(
            _savingProgress ? 'Actualizando…' : 'Guardar y actualizar',
          ),
        ),
        if (_savedMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _savedMessage!,
              style: const TextStyle(color: AppTheme.forest, fontSize: 12),
            ),
          ),
      ],
      const SizedBox(height: 14),
      if (widget.canTransition &&
          (_record['allowed_transitions'] as List? ?? []).isNotEmpty)
        FilledButton.icon(
          onPressed:
              (_record['allowed_transitions'] as List? ?? []).contains(
                    'cerrada',
                  ) &&
                  _completionGaps.isNotEmpty
              ? null
              : _transition,
          icon: const Icon(Icons.arrow_forward),
          label: Text(
            (_record['allowed_transitions'] as List? ?? []).contains(
                      'cerrada',
                    ) &&
                    _completionGaps.isNotEmpty
                ? 'Completa los pendientes para cerrar'
                : 'Actualizar estado de la operación',
          ),
        ),
      if (_module('exports')?['can_update'] == true && !_terminal)
        OutlinedButton.icon(
          onPressed: () => _form('exports', row: _record),
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Editar datos comerciales'),
        ),
      _stepHeading('1. Pedido y mercancía', ['export-allocations', 'orders']),
      if (_module('export-allocations') != null)
        _resourceSection('export-allocations', 'Productos y lotes reservados')
      else
        ExpansionTile(
          title: const Text('Productos y lotes'),
          children: [_lots()],
        ),
      _resourceSection('orders', 'Pedido del comprador y recepción'),
      _stepHeading('2. Documentos y aprobación', ['documents', 'requirements']),
      _resourceSection('requirements', 'Requisitos del destino'),
      _resourceSection('documents', 'Documentos y versiones'),
      _stepHeading('3. Transporte y entrega', ['transports']),
      _resourceSection('transports', 'Transporte y responsables'),
      _stepHeading('4. Pagos y cierre', ['finance']),
      if (_module('finance')?['can_report'] == true)
        FinanceReport(
          api: widget.api,
          revision: _revision,
          exportId: _record['id'] as int,
        ),
      _resourceSection('finance', 'Costos y pagos autorizados'),
      if ([
            'checklist',
            'compliance',
            'quotes',
            'activities',
            'approvals',
            'incidents',
          ].any((key) => _module(key) != null) ||
          (_module('exports')?['permissions'] as List? ?? []).contains(
            'assign',
          ))
        ExpansionTile(
          title: const Text('Opciones adicionales'),
          subtitle: const Text(
            'Úsalas si necesitas cotizar, delegar o reportar un problema.',
          ),
          children: [
            if ((_module('exports')?['permissions'] as List? ?? []).contains(
                  'assign',
                ) &&
                !_terminal)
              TextButton.icon(
                onPressed: _assignCoordinator,
                icon: const Icon(Icons.person_add_alt),
                label: const Text('Cambiar administrador'),
              ),
            _resourceSection('checklist', 'Verificación de requisitos'),
            _resourceSection('compliance', 'Resultado de cumplimiento'),
            _resourceSection('quotes', 'Cotizaciones'),
            _resourceSection('activities', 'Tareas y solicitudes al equipo'),
            _resourceSection('approvals', 'Solicitudes de aprobación'),
            _resourceSection('incidents', 'Problemas e incidencias'),
          ],
        ),
    ],
  );

  Widget _stepHeading(String label, List<String> keys) =>
      keys.any((key) => _module(key) != null)
      ? Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 4),
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        )
      : const SizedBox.shrink();

  Future<void> _assignCoordinator() async {
    try {
      final team = await widget.api.getAll('/team/');
      if (!mounted) return;
      final id = await showDialog<int>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Asignar administrador'),
          children: [
            for (final person in team.where(
              (p) => ['administrador'].contains(p['role']),
            ))
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, person['id']),
                child: Text('${person['name']} · ${friendly(person['role'])}'),
              ),
          ],
        ),
      );
      if (id == null) return;
      await widget.api.post('/exports/${_record['id']}/assign/', {'user': id});
      if (mounted) await _load();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Widget _resourceSection(String key, String title) {
    final module = _module(key);
    if (module == null) return const SizedBox.shrink();
    final rows = _resources[key] ?? [];
    final canCreate =
        !_terminal &&
        _canCreate(key) &&
        (key != 'export-allocations' ||
            [
              'borrador',
              'pendiente_documentacion',
              'requiere_correcciones',
            ].contains(_record['status']));
    return Card(
      margin: const EdgeInsets.only(top: 10),
      child: ExpansionTile(
        key: PageStorageKey('export-${_record['id']}-$key-$_focusStage'),
        initiallyExpanded:
            (_focusStage == 1 && key == 'orders') ||
            {
                  1: 'export-allocations',
                  2: 'documents',
                  3: 'transports',
                }[_focusStage] ==
                key,
        leading: Icon(moduleIcon(key), color: AppTheme.forest),
        title: Text(
          title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${rows.length} registro(s) · ${resourceOwner(key)}',
          style: const TextStyle(fontSize: 11),
        ),
        childrenPadding: const EdgeInsets.all(14),
        children: [
          Text(moduleHelp(key), style: const TextStyle(color: AppTheme.muted)),
          if (_resourceErrors[key] != null) ...[
            Text(_resourceErrors[key]!),
            TextButton(onPressed: _load, child: const Text('Reintentar')),
          ] else if (rows.isEmpty && !_loading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Todavía no hay registros en esta sección.'),
            ),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                children: [
                  RecordCard(
                    module: key,
                    record: row,
                    onTap: () => _resourceDetail(key, row),
                  ),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      if (module['can_update'] == true &&
                          !_terminal &&
                          !['export-allocations', 'requirements'].contains(key))
                        TextButton(
                          onPressed: () => _form(key, row: row),
                          child: const Text('Editar'),
                        ),
                      for (final action in _rowActions(key, row))
                        TextButton(
                          onPressed: () async {
                            try {
                              await widget.onResourceAction?.call(
                                key,
                                row,
                                '${action['key']}',
                              );
                              if (mounted) await _load();
                            } catch (e) {
                              if (mounted) setState(() => _error = '$e');
                            }
                          },
                          child: Text('${action['label']}'),
                        ),
                      if (key == 'transports' &&
                          _canCreate('transport-events') &&
                          !_terminal)
                        TextButton(
                          onPressed: () => _transportEvent(row),
                          child: const Text('Registrar avance'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          if (canCreate)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: OutlinedButton.icon(
                onPressed: () => _form(key),
                icon: const Icon(Icons.add),
                label: Text(moduleCreateLabel(key)),
              ),
            ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _rowActions(String key, Map<String, dynamic> row) {
    final module = _module(key);
    if (widget.onResourceAction == null || module == null) return [];
    return visibleRecordActions(module, row).where((action) {
      return !_terminal ||
          ['download', 'history', 'traceability'].contains(action['key']);
    }).toList();
  }

  Future<void> _transportEvent(Map<String, dynamic> transport) async {
    final module = _module('transport-events');
    if (module == null || module['can_create'] != true) return;
    final saved = await openTransportEventForm(
      modules: widget.modules,
      context: context,
      api: widget.api,
      module: module,
      transport: transport,
      exportId: _record['id'],
    );
    if (saved == true && mounted) await _load();
  }

  Future<void> _resourceDetail(String key, Map<String, dynamic> row) async {
    final fields = (_module(key)?['fields'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(moduleLabel(key, key)),
        content: SizedBox(
          width: 550,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (row['status'] != null) StatusPill(row['status']),
                for (final field in fields)
                  if (row[field['key']] != null &&
                      '${row[field['key']]}'.isNotEmpty &&
                      field['type'] != 'json' &&
                      field['key'] != 'export')
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        '${field['label']}: ${friendly(row[field['key']])}',
                      ),
                    ),
                if (row['review_notes'] != null)
                  Text('Observaciones: ${row['review_notes']}'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Widget _row(IconData icon, String label, String value, {bool last = false}) =>
      Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: last
              ? null
              : const Border(bottom: BorderSide(color: AppTheme.line)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 17, color: AppTheme.muted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 11, color: AppTheme.muted),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _timeline() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_history.isEmpty) {
      return const Text('Aún no hay eventos de seguimiento.');
    }
    return Column(
      children: [
        for (var i = 0; i < _history.length; i++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 34,
                  child: Column(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: i == _history.length - 1
                              ? AppTheme.forest
                              : const Color(0xFF5B9955),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          i == _history.length - 1
                              ? Icons.local_shipping_outlined
                              : Icons.check,
                          color: Colors.white,
                          size: 14,
                        ),
                      ),
                      if (i < _history.length - 1)
                        Expanded(
                          child: Container(
                            width: 2,
                            color: const Color(0xFFCBDDC3),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 27, top: 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          friendly(_history[i]['new_status']),
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          dateText(_history[i]['created_at'], time: true),
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: const Color(0xFFEDF2E7),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Estado actual',
                style: TextStyle(fontSize: 10, color: AppTheme.muted),
              ),
              const SizedBox(height: 5),
              Text(
                friendly(_record['status']),
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppTheme.forest,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _lots() {
    final lots = _record['allocations'] as List? ?? [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${lots.length} lotes asociados',
          style: const TextStyle(fontSize: 12, color: AppTheme.muted),
        ),
        const SizedBox(height: 14),
        if (lots.isEmpty)
          const Text('La operación todavía no tiene lotes asociados.'),
        for (final lot in lots)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(15),
                child: Row(
                  children: [
                    const OriginImage(
                      width: 55,
                      height: 60,
                      alignment: Alignment(0, .85),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${lot['lot_code']}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            '${number(lot['quantity'])} ${lot['unit']}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.inventory_2_outlined,
                      color: AppTheme.forest,
                      size: 22,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
