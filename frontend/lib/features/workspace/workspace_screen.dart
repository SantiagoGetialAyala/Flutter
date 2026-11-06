import 'dart:convert';
import 'dart:async';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../../core/services/api_client.dart';
import '../auth/models/auth_user.dart';
import 'record_form.dart';
import 'presentation.dart';
import 'export_detail.dart';
import 'finance_report.dart';
import 'workflow.dart';
import 'task_inbox.dart';
import 'operation_map.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/brand.dart';

String recordTitle(Map<String, dynamic> row) =>
    '${row['title'] ?? row['name'] ?? row['business_name'] ?? row['code'] ?? row['reference'] ?? row['email'] ?? row['description'] ?? row['plate'] ?? row['key'] ?? 'Registro #${row['id']}'}';

class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({
    super.key,
    required this.api,
    required this.user,
    this.onLogout,
  });
  final ApiClient api;
  final AuthUser user;
  final Future<void> Function()? onLogout;
  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  Map<String, dynamic>? _workspace;
  List<Map<String, dynamic>> _organizations = [];
  List<Map<String, dynamic>> _records = [];
  String? _org, _module, _error;
  String? _expandedSection;
  int _destination = 0;
  final _savedFilters = <String, Map<String, dynamic>>{};
  String get _role => '${_workspace?['role'] ?? widget.user.role ?? ''}';
  bool get _platform => widget.user.isPlatform && _org == null;
  List<String> get _destinations => [
    'Inicio',
    workLabel(_role),
    _platform ? 'Estado' : 'Mapa',
    'Tareas',
    'Perfil',
  ];
  List<Map<String, dynamic>> get _tasks =>
      (_workspace?['pending_tasks'] as List? ?? [])
          .cast<Map<String, dynamic>>();
  String get _workModule => workModules(_role).firstWhere(
    (key) => modules.any((m) => m['key'] == key),
    orElse: () => modules.isEmpty ? '' : '${modules.first['key']}',
  );

  Future<void> _go(int destination) async {
    if (destination == 1 && _workModule.isNotEmpty) {
      await _selectModule(_workModule);
    } else {
      if (_module != null) _rememberFilters();
      setState(() {
        _destination = destination;
        _module = null;
      });
      if (destination == 3) await _refreshTasks();
    }
  }

  void _rememberFilters() {
    if (_module != null) {
      _savedFilters[_module!] = {
        'search': _search,
        'status': _status,
        'page': _page,
      };
    }
  }

  Future<void> _refreshTasks() async {
    final organization = _org;
    try {
      final data = await api.getMap('/workspace/');
      if (mounted && _org == organization) setState(() => _workspace = data);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'No pudimos actualizar tus tareas. $e');
      }
    }
  }

  Future<void> _openTask(Map<String, dynamic> task) async {
    final key = '${task['module']}';
    if (!modules.any((m) => m['key'] == key)) return;
    await _selectModule(key);
    try {
      if (mounted) await _detail({'id': task['record_id']});
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  bool _loading = true, _loadingRecords = false;
  int _page = 1, _count = 0;
  String _search = '';
  String _status = '';
  Timer? _searchDebounce;
  int _recordRequest = 0;
  final _searchController = TextEditingController();
  ApiClient get api => widget.api;
  List<Map<String, dynamic>> get modules =>
      (_workspace?['modules'] as List? ?? [])
          .cast<Map<String, dynamic>>()
          .map(
            (m) => <String, dynamic>{
              ...m,
              'label': moduleLabel('${m['key']}', '${m['label']}'),
            },
          )
          .toList();
  Map<String, dynamic>? get selected =>
      modules.where((m) => m['key'] == _module).firstOrNull;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      final organizations = await api.getAll('/organizations/');
      final stored = await api.activeOrganizationId;
      _org = widget.user.isPlatform && api.exceptionalAccessReason == null
          ? null
          : organizations.any((o) => '${o['id']}' == stored)
          ? stored
          : widget.user.isPlatform
          ? null
          : organizations.isNotEmpty
          ? '${organizations.first['id']}'
          : null;
      await api.setActiveOrganization(_org);
      if (!mounted) return;
      setState(() => _organizations = organizations);
      await _loadWorkspace();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadWorkspace() async {
    _recordRequest++;
    setState(() {
      _loading = true;
      _error = null;
      _workspace = null;
      _records = [];
    });
    try {
      final data = await api.getMap('/workspace/');
      if (!mounted) return;
      setState(() {
        _workspace = data;
        _loading = false;
        if (!modules.any((m) => m['key'] == _module)) _module = null;
      });
      if (_module != null) await _loadRecords();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadRecords() async {
    if (_module == null) return;
    final requested = _module;
    final requestId = ++_recordRequest;
    setState(() {
      _loadingRecords = true;
      _error = null;
    });
    try {
      final data = await api.getMap(
        '/$_module/?page=$_page&search=${Uri.encodeQueryComponent(_search)}&status=${Uri.encodeQueryComponent(_status)}',
      );
      if (!mounted || requested != _module || requestId != _recordRequest) {
        return;
      }
      setState(() {
        _records = (data['results'] as List? ?? [])
            .cast<Map<String, dynamic>>();
        _count = data['count'] as int? ?? _records.length;
        _loadingRecords = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loadingRecords = false;
        });
      }
    }
  }

  Future<String?> _prompt(
    String title, {
    String label = 'Observaciones o justificación',
  }) async {
    var value = '';
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          onChanged: (text) => value = text,
          autofocus: true,
          maxLines: 3,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, value.trim()),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
    return result;
  }

  Future<void> _inviteAccept() async {
    final token = await _prompt(
      'Aceptar invitación',
      label: 'Código de invitación',
    );
    if (token == null || token.isEmpty) return;
    await _run(() async {
      await api.post('/invitations/accept/', {'token': token});
      await _initialize();
    });
  }

  Future<void> _createOrganization() async {
    if (widget.user.isPlatform) {
      if (_org != null) {
        await _switchOrganization(null);
      }
      if (!mounted) return;
      await _selectModule('platform-organizations');
      await _form();
      return;
    }
    final name = await _prompt(
      'Crear organización',
      label: 'Nombre de la empresa',
    );
    if (name == null || name.isEmpty) return;
    await _run(() async {
      final org = await api.post('/organizations/', {'name': name});
      await api.setActiveOrganization('${org['id']}');
      await _initialize();
    });
  }

  Future<void> _run(
    Future<void> Function() task, {
    bool propagate = false,
  }) async {
    try {
      await task();
    } catch (e) {
      if (propagate) rethrow;
      if (mounted) {
        setState(() => _error = '$e');
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _form([Map<String, dynamic>? record]) async {
    final module = selected;
    if (module == null) return;
    Map<String, dynamic>? created;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => RecordForm(
        api: api,
        module: module,
        record: record,
        onSaved: (r) => created = r,
      ),
    );
    if (saved == true) {
      await _loadRecords();
      if (record == null &&
          module['key'] == 'exports' &&
          created != null &&
          mounted) {
        await _detail(created!);
      }
      if (_module == 'platform-organizations' || _module == 'organizations') {
        final organizations = await api.getAll('/organizations/');
        if (mounted) setState(() => _organizations = organizations);
      }
    }
  }

  Future<void> _saveFile(String filename, Uint8List data) async {
    final file = XFile.fromData(
      data,
      name: filename,
      mimeType: filename.endsWith('.json')
          ? 'application/json'
          : 'application/octet-stream',
    );
    if (kIsWeb) {
      await file.saveTo(filename);
      return;
    }
    final location = await getSaveLocation(suggestedName: filename);
    if (location != null) await file.saveTo(location.path);
  }

  Future<void> _action(
    Map<String, dynamic> row,
    String action, {
    String? moduleKey,
  }) async {
    final actionModule = moduleKey ?? _module;
    await _run(() async {
      final path = '/$actionModule/${row['id']}/$action/';
      if (action == 'upload') {
        final file = await openFile(
          acceptedTypeGroups: [
            const XTypeGroup(
              label: 'Documentos y fotografías',
              extensions: [
                'pdf',
                'png',
                'jpg',
                'jpeg',
                'webp',
                'txt',
                'csv',
                'docx',
                'xlsx',
              ],
            ),
          ],
        );
        if (file == null) return;
        if (await file.length() > 10 * 1024 * 1024) {
          throw const ApiException('El archivo supera los 10 MB.');
        }
        await api.post(path, {
          'filename': file.name,
          'content': base64Encode(await file.readAsBytes()),
        });
      } else if (action == 'download') {
        final file = await api.getMap(path);
        await _saveFile(
          '${file['filename']}',
          base64Decode(file['content'] as String),
        );
      } else if (action == 'history' || action == 'traceability') {
        final data = action == 'history'
            ? await api.getAll(path)
            : await api.getMap(path);
        if (!mounted) return;
        await _showData(
          action == 'history'
              ? 'Historial de la operación'
              : 'Trazabilidad del lote',
          data,
        );
        return;
      } else {
        final notes = await _prompt(switch (action) {
          'submit' => 'Enviar documento a revisión',
          'approve' => 'Aprobar',
          'reject' => 'Rechazar o solicitar correcciones',
          'confirm' => 'Confirmar recepción',
          _ => action,
        });
        if (notes == null) return;
        await api.post(path, {
          'notes': notes,
          if (action == 'reject' && actionModule == 'documents')
            'corrections': true,
        });
      }
      await _loadRecords();
    }, propagate: moduleKey != null);
  }

  Future<void> _showData(String title, dynamic value) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 700,
          child: SingleChildScrollView(child: _DataView(value: value)),
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

  Future<void> _transition(
    Map<String, dynamic> row, {
    bool propagate = false,
  }) async {
    const transitions = <String, List<String>>{
      'borrador': ['pendiente_documentacion', 'cancelada'],
      'pendiente_documentacion': ['en_revision', 'cancelada'],
      'en_revision': [
        'requiere_correcciones',
        'aprobada_despacho',
        'rechazada',
      ],
      'requiere_correcciones': ['pendiente_documentacion', 'cancelada'],
      'aprobada_despacho': ['preparacion_logistica', 'bloqueada'],
      'preparacion_logistica': [
        'transporte_terrestre',
        'embarcada',
        'bloqueada',
      ],
      'transporte_terrestre': ['embarcada', 'bloqueada'],
      'embarcada': ['transito_internacional', 'bloqueada'],
      'transito_internacional': ['arribada', 'bloqueada'],
      'arribada': ['entregada', 'bloqueada'],
      'entregada': ['cerrada'],
      'bloqueada': ['pendiente_documentacion', 'cancelada'],
    };
    final permissions = (selected?['permissions'] as List? ?? []);
    final options =
        ((row['allowed_transitions'] as List?)?.cast<String>() ??
                transitions[row['status']] ??
                [])
            .where(
              (s) => permissions.contains(
                s == 'aprobada_despacho'
                    ? 'approve'
                    : [
                        'requiere_correcciones',
                        'rechazada',
                        'bloqueada',
                      ].contains(s)
                    ? 'reject'
                    : 'submit',
              ),
            )
            .toList();
    final next = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Actualizar estado'),
        children: [
          if (options.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('No tienes transiciones disponibles en este estado.'),
            ),
          for (final option in options)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, option),
              child: Text(friendly(option)),
            ),
        ],
      ),
    );
    if (next == null) return;
    final notes = await _prompt('Justificación del cambio de estado');
    if (notes == null) return;
    await _run(() async {
      await api.post('/exports/${row['id']}/transition/', {
        'status': next,
        'notes': notes,
      });
      await _loadRecords();
    }, propagate: propagate);
  }

  bool _canRecordTransport(
    Map<String, dynamic> module,
    Map<String, dynamic> row,
  ) =>
      module['key'] == 'transports' &&
      ['asignado', 'recogido', 'en_transito'].contains(row['status']) &&
      modules.any(
        (m) => m['key'] == 'transport-events' && m['can_create'] == true,
      );

  Future<void> _transportEvent(Map<String, dynamic> row) async {
    final module = modules
        .where((m) => m['key'] == 'transport-events')
        .firstOrNull;
    if (module == null || module['can_create'] != true) return;
    final saved = await openTransportEventForm(
      context: context,
      api: api,
      module: module,
      transport: row,
    );
    if (saved == true) {
      await _loadRecords();
      await _refreshTasks();
    }
  }

  Future<void> _detail(Map<String, dynamic> record) async {
    if (_module != null && record['id'] != null) {
      try {
        record = await api.getMap('/$_module/${record['id']}/');
        if (!mounted) return;
      } catch (e) {
        if (mounted) setState(() => _error = '$e');
        return;
      }
    }
    if (_module == 'exports') {
      await showDialog<void>(
        context: context,
        builder: (_) => ExportDetail(
          api: api,
          record: record,
          modules: modules,
          onResourceAction: (key, row, action) =>
              _action(row, action, moduleKey: key),
          canViewDocuments: modules.any((m) => m['key'] == 'documents'),
          canTransition: (selected?['permissions'] as List? ?? []).any(
            (p) => ['submit', 'approve', 'reject'].contains(p),
          ),
          onTransition: (row) => _transition(row, propagate: true),
        ),
      );
      return;
    }
    final module = selected!;
    final labels = {
      'status': 'Estado',
      'quantity_available': 'Cantidad disponible',
      'review_notes': 'Observaciones de revisión',
      'versions': 'Versiones del documento',
      'administrator_invitation': 'Invitación del administrador',
      'payment_status': 'Estado del pago',
      'base_amount': 'Importe convertido',
      'account_status': 'Estado de la cuenta',
      for (final f in (module['fields'] as List)) f['key']: f['label'],
    };
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(recordTitle(record)),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final item in record.entries)
                  if (item.value != null &&
                      item.value != '' &&
                      ![
                        'id',
                        'public_id',
                        'can_confirm',
                        'can_review',
                        'can_approve',
                        'can_submit',
                        'created_at',
                        'updated_at',
                        'actor',
                        'owner',
                        'reviewer',
                        'reviewed_at',
                        'organization',
                        'responsible',
                        'evaluated_by',
                        'evaluator',
                        'requested_by',
                        'decided_by',
                        'reported_by',
                        'received_by',
                      ].contains(item.key))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${labels[item.key] ?? item.key.replaceAll('_', ' ')}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          if (item.key == 'status' ||
                              item.key == 'payment_status' ||
                              item.key == 'account_status')
                            StatusPill(item.value)
                          else
                            _DataView(value: item.value),
                        ],
                      ),
                    ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
          if (_canRecordTransport(module, record))
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                _transportEvent(record);
              },
              child: const Text('Registrar avance'),
            ),
          if (module['can_update'] == true &&
              _canRecordTransport(module, record))
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _form(record);
              },
              child: const Text('Editar asignación'),
            ),
          if (module['can_update'] == true &&
              !_canRecordTransport(module, record))
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                _form(record);
              },
              child: const Text('Editar'),
            ),
          for (final action in visibleRecordActions(module, record).take(2))
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _action(record, '${action['key']}');
              },
              child: Text('${action['label']}'),
            ),
        ],
      ),
    );
  }

  Future<void> _selectModule(String? value) async {
    if (value != null && !modules.any((m) => m['key'] == value)) return;
    _searchDebounce?.cancel();
    _rememberFilters();
    final filters = _savedFilters[value];
    setState(() {
      _module = value;
      _destination = value == null ? 0 : 1;
      if (value != null) _expandedSection = sectionFor(value);
      _page = filters?['page'] as int? ?? 1;
      _search = filters?['search'] as String? ?? '';
      _status = filters?['status'] as String? ?? '';
      _searchController.text = _search;
    });
    if (value != null) await _loadRecords();
  }

  Future<void> _switchOrganization(String? id) async {
    if (widget.user.isPlatform && id != null) {
      final reason = await _prompt(
        'Acceso excepcional a una empresa',
        label: 'Motivo del acceso (mínimo 15 caracteres)',
      );
      if (reason == null || reason.length < 15) return;
      api.exceptionalAccessReason = reason;
    } else {
      api.exceptionalAccessReason = null;
    }
    await api.setActiveOrganization(id);
    if (!mounted) return;
    setState(() {
      _org = id;
      _module = null;
      _destination = 0;
      _savedFilters.clear();
      _status = '';
    });
    await _loadWorkspace();
  }

  Future<void> _organizationPicker() async {
    final chosen = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Tus organizaciones'),
        content: SizedBox(
          width: 430,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.user.isPlatform
                      ? 'Administra la plataforma o accede a una empresa con una justificación.'
                      : 'Tu acceso y tu rol pueden cambiar en cada empresa.',
                  style: const TextStyle(color: AppTheme.muted),
                ),
                const SizedBox(height: 16),
                if (widget.user.isPlatform)
                  ListTile(
                    leading: const Icon(Icons.admin_panel_settings_outlined),
                    title: const Text('Administración de plataforma'),
                    trailing: _org == null
                        ? const Icon(Icons.check_circle, color: AppTheme.forest)
                        : null,
                    onTap: () => Navigator.pop(dialogContext, 'platform'),
                  ),
                for (final org in _organizations)
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFFEEF3E8),
                      child: Icon(
                        Icons.business_outlined,
                        color: AppTheme.forest,
                      ),
                    ),
                    title: Text('${org['name']}'),
                    subtitle: Text(_contextRole('${org['id']}')),
                    trailing: _org == '${org['id']}'
                        ? const Icon(Icons.check_circle, color: AppTheme.forest)
                        : null,
                    onTap: () => Navigator.pop(dialogContext, '${org['id']}'),
                  ),
                if (_organizations.length == 1 && !widget.user.isPlatform)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Tu cuenta pertenece a una empresa. Para acceder a otra, acepta una invitación de su administrador.',
                      style: TextStyle(fontSize: 12, color: AppTheme.muted),
                    ),
                  ),
                if (_organizations.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('Todavía no tienes empresas vinculadas.'),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cerrar'),
          ),
          if (!widget.user.isPlatform)
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'invite'),
              child: const Text('Aceptar invitación'),
            ),
        ],
      ),
    );
    if (chosen == null) return;
    if (chosen == 'invite') {
      await _inviteAccept();
      return;
    }
    await _switchOrganization(chosen == 'platform' ? null : chosen);
  }

  Future<void> _profile() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: const Color(0xFFE8F0E2),
                    child: Text(
                      _initials,
                      style: const TextStyle(
                        color: AppTheme.forest,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.user.fullName,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text(
                          widget.user.email,
                          style: const TextStyle(
                            color: AppTheme.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.business_outlined),
                title: const Text('Cambiar organización'),
                subtitle: Text(_organizationName),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _organizationPicker();
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.mail_outline),
                title: const Text('Aceptar invitación'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _inviteAccept();
                },
              ),
              if (widget.user.isPlatform ||
                  ['administrador', 'comercial'].contains(widget.user.role))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.add_business_outlined),
                  title: const Text('Crear empresa'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _createOrganization();
                  },
                ),
              if (widget.onLogout != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.logout, color: Color(0xFFB65746)),
                  title: const Text(
                    'Cerrar sesión',
                    style: TextStyle(color: Color(0xFFB65746)),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    widget.onLogout!();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  String get _initials => widget.user.fullName
      .split(' ')
      .where((w) => w.isNotEmpty)
      .take(2)
      .map((w) => w[0])
      .join()
      .toUpperCase();
  String get _organizationName =>
      '${_workspace?['organization'] ?? _organizations.where((o) => '${o['id']}' == _org).firstOrNull?['name'] ?? 'Tu espacio de trabajo'}';

  Future<void> _allModules() async {
    var query = '';
    final value = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, updateMenu) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .75,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [
                Text(
                  'Gestión',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 5),
                const Text(
                  'Herramientas y catálogos disponibles para tu rol',
                  style: TextStyle(color: AppTheme.muted),
                ),
                const SizedBox(height: 14),
                TextField(
                  autofocus: false,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Buscar documentos, fincas, equipo…',
                  ),
                  onChanged: (v) => updateMenu(() => query = v),
                ),
                if (query.isNotEmpty &&
                    !modules.any(
                      (m) => '${m['label']} ${moduleHelp(m['key'] as String)}'
                          .toLowerCase()
                          .contains(query.toLowerCase()),
                    ))
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      'No encontramos herramientas con ese nombre. Prueba otra palabra.',
                    ),
                  ),
                ..._menuItems(
                  (key) => Navigator.pop(context, key),
                  query: query,
                  onMenuChanged: () => updateMenu(() {}),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (value != null) await _selectModule(value == 'home' ? null : value);
  }

  List<Widget> _menuItems(
    ValueChanged<String> onSelected, {
    VoidCallback? onMenuChanged,
    String query = '',
  }) {
    final result = <Widget>[];
    for (final group in [...navigationSections.keys, 'Otras herramientas']) {
      final items = modules
          .where(
            (m) =>
                sectionFor(m['key'] as String) == group &&
                '${m['label']} ${moduleHelp(m['key'] as String)}'
                    .toLowerCase()
                    .contains(query.toLowerCase()),
          )
          .toList();
      if (items.isEmpty) continue;
      final expanded = query.isNotEmpty || _expandedSection == group;
      final active = items.any((m) => m['key'] == _module);
      result.add(
        Column(
          children: [
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 10),
              leading: Icon(moduleIcon(items.first['key'] as String), size: 21),
              title: Text(
                group,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: active ? AppTheme.forest : null,
                ),
              ),
              subtitle: Text(
                '${items.length} ${items.length == 1 ? 'herramienta' : 'herramientas'}',
                style: const TextStyle(fontSize: 11, color: AppTheme.muted),
              ),
              trailing: Icon(
                expanded ? Icons.expand_less : Icons.expand_more,
                size: 20,
              ),
              onTap: () {
                setState(() => _expandedSection = expanded ? null : group);
                // Refresh the mobile tools sheet as well as the desktop menu.
                onMenuChanged?.call();
              },
            ),
            if (expanded)
              for (final m in items)
                Padding(
                  padding: const EdgeInsets.only(left: 12, bottom: 2),
                  child: Tooltip(
                    message: moduleHelp(m['key'] as String),
                    child: ListTile(
                      dense: true,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      selected: _module == m['key'],
                      selectedTileColor: const Color(0xFFE7EFE4),
                      selectedColor: AppTheme.forest,
                      title: Text(
                        '${m['label']}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      onTap: () => onSelected(m['key'] as String),
                    ),
                  ),
                ),
          ],
        ),
      );
    }
    return result;
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: LayoutBuilder(
      builder: (context, bounds) {
        final wide = bounds.maxWidth >= 1000;
        return Row(
          children: [
            if (wide)
              Container(
                width: 238,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(right: BorderSide(color: AppTheme.line)),
                ),
                child: Column(
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(24, 29, 24, 28),
                      child: Brand(compact: true),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        children: [
                          for (var i = 0; i < _destinations.length; i++)
                            ListTile(
                              selected: _destination == i,
                              selectedTileColor: const Color(0xFFE7EFE4),
                              selectedColor: AppTheme.forest,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              leading: Icon(
                                _platform && i == 2
                                    ? Icons.monitor_heart_outlined
                                    : primaryIcons[i],
                              ),
                              title: Text(
                                _destinations[i],
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              onTap: () => _go(i),
                            ),
                          const Divider(),
                          ListTile(
                            leading: const Icon(Icons.search),
                            title: const Text('Buscar en gestión'),
                            subtitle: const Text('Catálogos y herramientas'),
                            onTap: _allModules,
                          ),
                        ],
                      ),
                    ),
                    const Divider(indent: 20, endIndent: 20),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                        ),
                        leading: CircleAvatar(
                          radius: 18,
                          backgroundColor: const Color(0xFFEAF0E4),
                          child: Text(
                            _initials,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.forest,
                            ),
                          ),
                        ),
                        title: Text(
                          widget.user.fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: const Text(
                          'Mi cuenta',
                          style: TextStyle(fontSize: 10),
                        ),
                        trailing: const Icon(Icons.more_horiz, size: 18),
                        onTap: () => _go(4),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: Column(
                children: [
                  _header(wide),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(14, 7, 4, 7),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFEEE7),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.info_outline,
                              color: Color(0xFFAD5C32),
                              size: 19,
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                _error!,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF914F33),
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => setState(() => _error = null),
                              icon: const Icon(Icons.close, size: 17),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Expanded(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : _workspace == null
                        ? _emptyWorkspace()
                        : Align(
                            alignment: Alignment.topCenter,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 1220),
                              child: _mainContent(),
                            ),
                          ),
                  ),
                  if (!wide && _workspace != null)
                    Container(
                      decoration: const BoxDecoration(
                        border: Border(top: BorderSide(color: AppTheme.line)),
                      ),
                      child: NavigationBar(
                        selectedIndex: _destination,
                        onDestinationSelected: _go,
                        destinations: [
                          for (var i = 0; i < _destinations.length; i++)
                            NavigationDestination(
                              icon: Icon(
                                _platform && i == 2
                                    ? Icons.monitor_heart_outlined
                                    : primaryIcons[i],
                              ),
                              label: _destinations[i],
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );

  String _contextRole(String orgId) {
    final contexts = (_workspace?['contexts'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    final entry = contexts
        .where((c) => '${c['organization_id']}' == orgId)
        .firstOrNull;
    return entry == null
        ? 'Acceso según tu membresía'
        : friendly(entry['role__name']);
  }

  String _metricModule(Map<String, dynamic> metric) {
    final key = metric['module'];
    if (modules.any((m) => m['key'] == key)) return '$key';
    final text = '${metric['label']}'.toLowerCase();
    final candidates = text.contains('document')
        ? ['documents']
        : text.contains('lote')
        ? ['lots']
        : text.contains('pedido')
        ? ['orders']
        : text.contains('entrega') || text.contains('tránsito')
        ? ['transports']
        : [_workModule];
    return candidates.firstWhere(
      (key) => modules.any((m) => m['key'] == key),
      orElse: () => _workModule,
    );
  }

  Widget _mainContent() {
    if (_module != null) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final key in workModules(_role))
                          if (modules.any((m) => m['key'] == key))
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ChoiceChip(
                                label: Text(moduleLabel(key, _shortLabel(key))),
                                selected: key == _module,
                                onSelected: (_) => _selectModule(key),
                              ),
                            ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Gestión y catálogos',
                  onPressed: _allModules,
                  icon: const Icon(Icons.tune),
                ),
              ],
            ),
          ),
          Expanded(child: _modulePage()),
        ],
      );
    }
    return switch (_destination) {
      2 =>
        _platform
            ? _servicePage()
            : OperationMap(
                key: ValueKey('map-$_org'),
                api: api,
                modules: modules.map((m) => '${m['key']}').toSet(),
              ),
      3 => TaskInbox(
        tasks: _tasks,
        onOpen: _openTask,
        onRefresh: _refreshTasks,
      ),
      4 => _profilePage(),
      _ => _dashboard(),
    };
  }

  Widget _profilePage() => ListView(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
    children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.user.fullName,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(widget.user.email),
              const SizedBox(height: 14),
              Text('Contexto de trabajo: $_organizationName'),
              Text(
                'Rol activo: ${_workspace?['role_label'] ?? widget.user.roleDisplay}',
                style: const TextStyle(
                  color: AppTheme.forest,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: _organizationPicker,
        icon: const Icon(Icons.swap_horiz),
        label: const Text('Cambiar contexto de trabajo'),
      ),
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'Cada empresa determina tu rol y sus permisos. Al cambiar de empresa se vuelve a cargar tu acceso.',
          style: TextStyle(color: AppTheme.muted),
        ),
      ),
      Card(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.grid_view_rounded),
              title: const Text('Gestión y catálogos'),
              subtitle: const Text('Encuentra las herramientas de tu rol'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _allModules,
            ),
            ListTile(
              leading: const Icon(Icons.mail_outline),
              title: const Text('Aceptar invitación'),
              onTap: _inviteAccept,
            ),
            ListTile(
              leading: const Icon(Icons.manage_accounts_outlined),
              title: const Text('Opciones de cuenta'),
              onTap: _profile,
            ),
            if (widget.onLogout != null)
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Cerrar sesión'),
                onTap: widget.onLogout,
              ),
          ],
        ),
      ),
    ],
  );

  Widget _servicePage() => FutureBuilder<Map<String, dynamic>>(
    future: api.getMap('/service-status/'),
    builder: (context, snapshot) => ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Estado de la plataforma',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        if (snapshot.connectionState != ConnectionState.done)
          const LinearProgressIndicator(),
        if (snapshot.hasError)
          Text('No pudimos consultar los servicios. ${snapshot.error}'),
        if (snapshot.hasData) ...[
          for (final key in ['api', 'database'])
            Card(
              child: ListTile(
                leading: const Icon(Icons.monitor_heart_outlined),
                title: Text(key == 'api' ? 'API' : 'Base de datos'),
                subtitle: Text('${snapshot.data![key] ?? 'Sin información'}'),
              ),
            ),
          Text(
            'Última comprobación: ${dateText(snapshot.data!['checked_at'], time: true)}',
          ),
        ],
        TextButton(
          onPressed: () => setState(() {}),
          child: const Text('Actualizar'),
        ),
      ],
    ),
  );

  String _shortLabel(String key) =>
      const {
        'exports': 'Exportaciones',
        'lots': 'Lotes',
        'documents': 'Documentos',
        'transports': 'Transporte',
        'orders': 'Pedidos',
        'finance': 'Finanzas',
        'producers': 'Origen',
        'platform-organizations': 'Empresas',
        'platform-users': 'Cuentas',
        'audit': 'Auditoría',
      }[key] ??
      '${modules.where((m) => m['key'] == key).firstOrNull?['label'] ?? 'Gestión'}';

  Widget _header(bool wide) => Container(
    padding: EdgeInsets.fromLTRB(
      wide ? 32 : 20,
      wide ? 24 : 16,
      wide ? 32 : 16,
      18,
    ),
    child: Row(
      children: [
        if (_module != null && !wide)
          IconButton(
            onPressed: () => _selectModule(null),
            icon: const Icon(Icons.arrow_back_ios_new, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 36),
          ),
        if (!wide && _module == null) ...[
          CircleAvatar(
            radius: 22,
            backgroundColor: const Color(0xFFE5EDDD),
            child: Text(
              _initials,
              style: const TextStyle(
                color: AppTheme.forest,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _module == null
                    ? _destination == 0
                          ? 'Hola, ${widget.user.fullName.split(' ').first}'
                          : _destinations[_destination]
                    : '${selected?['label'] ?? 'Tu espacio'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: wide ? 23 : 19,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.6,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                _module == null
                    ? '${_workspace?['role_label'] ?? widget.user.roleDisplay}'
                    : _organizationName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: AppTheme.muted),
              ),
            ],
          ),
        ),
        if (wide) ...[
          OutlinedButton.icon(
            onPressed: _organizationPicker,
            icon: const Icon(Icons.business_outlined, size: 17),
            label: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 215),
              child: Text(
                _organizationName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(width: 10),
        ] else
          IconButton(
            onPressed: _organizationPicker,
            tooltip: 'Cambiar organización',
            icon: const Icon(Icons.business_outlined, size: 22),
          ),
        if (modules.any((m) => m['key'] == 'notifications'))
          IconButton(
            onPressed: () => _selectModule('notifications'),
            tooltip: 'Notificaciones',
            icon: const Icon(Icons.notifications_none_rounded, size: 23),
          ),
        IconButton(
          onPressed: _allModules,
          tooltip: 'Buscar en gestión',
          icon: const Icon(Icons.search),
        ),
      ],
    ),
  );

  Widget _emptyWorkspace() => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          children: [
            const Icon(
              Icons.business_outlined,
              size: 54,
              color: AppTheme.forest,
            ),
            const SizedBox(height: 20),
            Text(
              'Un lugar para tu equipo',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 10),
            const Text(
              'Acepta la invitación de tu empresa para empezar a trabajar. Cada organización tiene su propio equipo, datos y permisos.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.muted),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _inviteAccept,
              icon: const Icon(Icons.mail_outline),
              label: const Text('Aceptar invitación'),
            ),
            if (['administrador', 'comercial'].contains(widget.user.role))
              TextButton(
                onPressed: _createOrganization,
                child: const Text('Registrar mi empresa'),
              ),
          ],
        ),
      ),
    ),
  );

  Widget _dashboard() {
    final metrics = (_workspace!['metrics'] as List? ?? [])
        .cast<Map<String, dynamic>>()
        .take(5)
        .toList();
    final primaryMetric = metrics.isEmpty ? null : metrics.first;
    final quick = [
      for (final key in [...workModules(_role), 'invitations'])
        if (modules.any((m) => m['key'] == key))
          modules.firstWhere((m) => m['key'] == key),
    ].take(4).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        InkWell(
          onTap: _organizationPicker,
          borderRadius: BorderRadius.circular(30),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.business_outlined,
                  size: 13,
                  color: AppTheme.muted,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    _organizationName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: AppTheme.muted),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.keyboard_arrow_down,
                  size: 16,
                  color: AppTheme.muted,
                ),
              ],
            ),
          ),
        ),
        if (primaryMetric != null)
          InkWell(
            onTap: () => _selectModule(_metricModule(primaryMetric)),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              height: 155,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF377E58), Color(0xFF0F4937)],
                ),
              ),
              child: Stack(
                children: [
                  Positioned(
                    right: -16,
                    bottom: -35,
                    child: Icon(
                      widget.user.isPlatform && _org == null
                          ? Icons.public_rounded
                          : Icons.local_shipping_rounded,
                      size: 176,
                      color: Colors.white.withValues(alpha: .075),
                    ),
                  ),
                  Positioned(
                    right: 22,
                    top: 24,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .1),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        widget.user.isPlatform && _org == null
                            ? Icons.public
                            : Icons.sailing_outlined,
                        color: const Color(0xFFD9E9CF),
                        size: 31,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${primaryMetric['label']}',
                          style: const TextStyle(
                            color: Color(0xFFE2EEE2),
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          number(primaryMetric['value']),
                          style: const TextStyle(
                            fontSize: 39,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: -1.3,
                            height: 1.15,
                          ),
                        ),
                        const Spacer(),
                        Row(
                          children: [
                            const Icon(
                              Icons.check_circle_outline,
                              color: Color(0xFFC7DEBF),
                              size: 13,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                widget.user.isPlatform && _org == null
                                    ? 'Vista general de la plataforma'
                                    : 'Tu operación, conectada desde el origen',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFFD0E2CE),
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 13),
        LayoutBuilder(
          builder: (context, box) {
            final columns = box.maxWidth > 750 ? 4 : 2;
            final width = (box.maxWidth - (columns - 1) * 11) / columns;
            return Wrap(
              spacing: 11,
              runSpacing: 11,
              children: [
                for (var i = 1; i < metrics.length; i++)
                  SizedBox(
                    width: width,
                    child: InkWell(
                      onTap: () => _selectModule(_metricModule(metrics[i])),
                      borderRadius: BorderRadius.circular(15),
                      child: _metricTile(metrics[i], i),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 26),
        _sectionTitle('Pendientes que atender', onView: () => _go(3)),
        const SizedBox(height: 12),
        TaskInbox(
          tasks: _tasks,
          onOpen: _openTask,
          onRefresh: _refreshTasks,
          compact: true,
        ),
        if (_tasks.any((t) => t['overdue'] == true))
          _helper(
            'Hay tareas vencidas',
            'Abre Tareas para revisar las fechas y coordinar el siguiente paso.',
          ),
        const SizedBox(height: 24),
        _sectionTitle(
          'Accesos rápidos',
          subtitle: 'Lo que necesitas para avanzar',
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, box) {
            final columns = box.maxWidth > 750 ? 4 : 2;
            final width = (box.maxWidth - (columns - 1) * 10) / columns;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final m in quick)
                  SizedBox(
                    width: width,
                    child: Material(
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: const BorderSide(color: AppTheme.line),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => _selectModule(m['key'] as String),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 17,
                          ),
                          child: Column(
                            children: [
                              Icon(
                                moduleIcon(m['key'] as String),
                                size: 25,
                                color: AppTheme.forest,
                              ),
                              const SizedBox(height: 9),
                              Text(
                                _shortLabel(m['key'] as String) == 'Módulos'
                                    ? '${m['label']}'
                                    : _shortLabel(m['key'] as String),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        if (widget.user.isPlatform && _org == null) ...[
          const SizedBox(height: 22),
          _platformOnboarding(),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _run(() async {
                  await _showData(
                    'Estado operativo',
                    await api.getMap('/service-status/'),
                  );
                }),
                icon: const Icon(Icons.monitor_heart_outlined, size: 17),
                label: const Text('Estado de servicios'),
              ),
              OutlinedButton.icon(
                onPressed: () => _run(() async {
                  await _showData(
                    'Matriz de permisos',
                    await api.getMap('/grants/matrix/'),
                  );
                }),
                icon: const Icon(Icons.admin_panel_settings_outlined, size: 17),
                label: const Text('Permisos'),
              ),
            ],
          ),
        ],
        for (final panel in (_workspace!['panels'] as List? ?? []).take(2)) ...[
          const SizedBox(height: 26),
          _sectionTitle(
            '${panel['label']}',
            onView: () => _selectModule(panel['module'] as String),
          ),
          const SizedBox(height: 12),
          if ((panel['items'] as List).isEmpty)
            _emptyPanel(
              'Aún no hay registros',
              'Cuando tu equipo empiece a trabajar, podrás seguirlo aquí.',
            )
          else
            for (final item in (panel['items'] as List).take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: panel['module'] == 'finance' && item['margen'] != null
                    ? _profitTile(Map<String, dynamic>.from(item))
                    : RecordCard(
                        module: panel['module'] as String,
                        record: Map<String, dynamic>.from(item),
                        onTap: () async {
                          await _selectModule(panel['module'] as String);
                          if (mounted) {
                            await _detail(Map<String, dynamic>.from(item));
                          }
                        },
                      ),
              ),
        ],
        const SizedBox(height: 24),
        _sectionTitle('Actividad reciente'),
        const SizedBox(height: 12),
        if ((_workspace!['recent_activity'] as List).isEmpty)
          _emptyPanel(
            'Todo listo para comenzar',
            'Aquí encontrarás los últimos movimientos de tu equipo.',
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.line),
            ),
            child: Column(
              children: [
                for (final event
                    in (_workspace!['recent_activity'] as List).take(5))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      radius: 16,
                      backgroundColor: Color(0xFFEAF2E5),
                      child: Icon(
                        Icons.check,
                        size: 15,
                        color: AppTheme.forest,
                      ),
                    ),
                    title: Text(
                      _eventLabel('${event['action']}'),
                      style: const TextStyle(fontSize: 12),
                    ),
                    subtitle: Text(
                      dateText(event['created_at'], time: true),
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppTheme.muted,
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _metricTile(Map<String, dynamic> metric, int index) {
    const icons = [
      Icons.description_outlined,
      Icons.local_shipping_outlined,
      Icons.task_alt,
      Icons.bar_chart,
      Icons.verified_outlined,
    ];
    final amber = '${metric['label']}'.toLowerCase().contains('pendiente');
    return Container(
      height: 94,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppTheme.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: amber ? const Color(0xFFFCF3DF) : const Color(0xFFEAF2E6),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icons[(index - 1) % icons.length],
              color: amber ? const Color(0xFFB18430) : AppTheme.forest,
              size: 19,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${metric['label']}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppTheme.muted,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  number(metric['value']),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(
    String title, {
    String? subtitle,
    VoidCallback? onView,
  }) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: -.3,
              ),
            ),
            if (subtitle != null)
              Text(
                subtitle,
                style: const TextStyle(fontSize: 11, color: AppTheme.muted),
              ),
          ],
        ),
      ),
      if (onView != null)
        TextButton(
          onPressed: onView,
          child: const Text('Ver todos', style: TextStyle(fontSize: 11)),
        ),
    ],
  );
  Widget _emptyPanel(String title, String subtitle) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: AppTheme.line),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      children: [
        const Icon(Icons.eco_outlined, color: Color(0xFF9BB38C), size: 28),
        const SizedBox(height: 10),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11, color: AppTheme.muted),
        ),
      ],
    ),
  );
  Widget _platformOnboarding() => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: const Color(0xFFF0F2E8),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Una empresa. Su propio espacio.',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        const Text(
          'Registra la empresa e invita a su primer administrador. Él incorpora a su equipo y organiza la operación.',
          style: TextStyle(fontSize: 12, color: AppTheme.muted),
        ),
        const SizedBox(height: 15),
        FilledButton.icon(
          onPressed: _createOrganization,
          icon: const Icon(Icons.add_business_outlined, size: 17),
          label: const Text('Crear empresa'),
        ),
      ],
    ),
  );
  Widget _profitTile(Map<String, dynamic> item) => Card(
    child: Padding(
      padding: const EdgeInsets.all(17),
      child: Row(
        children: [
          const Icon(Icons.trending_up, color: AppTheme.forest),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '${item['title']}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${item['currency']} ${number(item['margen'])}',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.forest,
                ),
              ),
              const Text(
                'Margen de la operación',
                style: TextStyle(fontSize: 10, color: AppTheme.muted),
              ),
            ],
          ),
        ],
      ),
    ),
  );
  String _eventLabel(String action) =>
      '${const {'created': 'Registro creado', 'updated': 'Información actualizada', 'assigned': 'Responsable asignado', 'submitted': 'Enviado a revisión', 'downloaded': 'Documento descargado', 'version_uploaded': 'Nueva versión cargada', 'status_changed': 'Estado actualizado', 'aprobado': 'Documento aprobado', 'rechazado': 'Documento rechazado', 'accepted': 'Invitación aceptada', 'revoked': 'Acceso revocado', 'conforme': 'Evaluación registrada'}[action.split('.').last] ?? 'Actividad registrada'} · ${friendly(action.split('.').first)}';

  Widget _modulePage() {
    final m = selected;
    if (m == null) return const SizedBox.shrink();
    final filters = _module == 'exports'
        ? {
            '': 'Todas',
            'transito_internacional': 'En tránsito',
            'en_revision': 'En revisión',
            'aprobada_despacho': 'Aprobadas',
          }
        : _module == 'documents'
        ? {
            '': 'Todos',
            'pendiente': 'Pendientes',
            'aprobado': 'Aprobados',
            'correcciones': 'Correcciones',
          }
        : <String, String>{};
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        if (_module == 'finance' && m['can_report'] == true)
          FinanceReport(api: api, revision: _records.hashCode),
        Text(
          moduleHelp(_module!),
          style: const TextStyle(fontSize: 13, color: AppTheme.muted),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (m['can_create'] == true)
              FilledButton.icon(
                onPressed: () => _form(),
                icon: const Icon(Icons.add, size: 17),
                label: Text(
                  moduleCreateLabel(_module!),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            if (m['can_report'] == true)
              IconButton(
                tooltip: 'Descargar reporte',
                icon: const Icon(Icons.file_download_outlined, size: 22),
                onPressed: () => _run(() async {
                  final data = await api.getMap('/$_module/report/');
                  await _showData('Reporte de ${m['label']}', data);
                  await _saveFile(
                    'reporte-$_module.json',
                    Uint8List.fromList(
                      utf8.encode(
                        const JsonEncoder.withIndent('  ').convert(data),
                      ),
                    ),
                  );
                }),
              ),
          ],
        ),
        const SizedBox(height: 17),
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: _module == 'exports'
                ? 'Buscar exportación…'
                : 'Buscar ${'${m['label']}'.toLowerCase()}…',
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: IconButton(
              onPressed: _loadRecords,
              icon: const Icon(Icons.refresh_rounded, size: 19),
              tooltip: 'Actualizar',
            ),
          ),
          onChanged: (value) {
            _searchDebounce?.cancel();
            _searchDebounce = Timer(const Duration(milliseconds: 350), () {
              if (!mounted) return;
              setState(() {
                _search = value;
                _page = 1;
              });
              _loadRecords();
            });
          },
          onSubmitted: (value) {
            setState(() {
              _search = value;
              _page = 1;
            });
            _loadRecords();
          },
        ),
        if (filters.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 15),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final item in filters.entries)
                    Padding(
                      padding: const EdgeInsets.only(right: 7),
                      child: ChoiceChip(
                        label: Text(item.value),
                        selected: _status == item.key,
                        showCheckmark: false,
                        selectedColor: AppTheme.forest,
                        labelStyle: TextStyle(
                          fontFamily: 'Roboto',
                          fontSize: 11,
                          color: _status == item.key
                              ? Colors.white
                              : AppTheme.ink,
                        ),
                        onSelected: (_) {
                          setState(() {
                            _status = item.key;
                            _page = 1;
                          });
                          _loadRecords();
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        if (_module == 'documents') ...[
          _documentOverview(),
          const SizedBox(height: 15),
        ],
        if (_module == 'invitations')
          _helper(
            'Invita a tu equipo',
            'Comparte el código de la invitación con la persona indicada. Debe aceptarlo usando el mismo correo.',
          ),
        if (_module == 'members')
          _helper(
            'Un equipo, distintos permisos',
            'Incorpora personas desde Invitar personas. Aquí puedes cambiar su rol o revocar el acceso.',
          ),
        if (_module == 'platform-organizations')
          _helper(
            'Así empieza una empresa',
            'Indica el correo del primer administrador al crearla y comparte con esa persona el código de invitación que se genera.',
          ),
        if (_module == 'requirements')
          _helper(
            'Un expediente completo antes de salir',
            'Define los documentos obligatorios por destino. El sistema verificará su aprobación y vigencia.',
          ),
        const SizedBox(height: 12),
        if (_loadingRecords)
          const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[
          if (_records.isEmpty)
            _emptyPanel(
              _search.isNotEmpty || _status.isNotEmpty
                  ? 'No encontramos coincidencias'
                  : 'Aún no hay ${'${m['label']}'.toLowerCase()}',
              _search.isNotEmpty || _status.isNotEmpty
                  ? 'Prueba con otra búsqueda o cambia los filtros.'
                  : m['can_create'] == true
                  ? '${moduleHelp(_module!)} Para empezar, pulsa «${moduleCreateLabel(_module!)}».'
                  : 'Los registros aparecerán aquí cuando tu equipo los agregue.',
            ),
          for (final row in _records)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RecordCard(
                    module: _module!,
                    record: row,
                    onTap: () => _detail(row),
                    menu: _recordMenu(row, m),
                  ),
                  if (m['can_update'] == true ||
                      (m['actions'] as List).isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Wrap(
                        spacing: 4,
                        children: [
                          if (_canRecordTransport(m, row))
                            TextButton(
                              onPressed: () => _transportEvent(row),
                              child: const Text('Registrar avance'),
                            ),
                          if (m['can_update'] == true)
                            TextButton(
                              onPressed: () => _form(row),
                              child: const Text(
                                'Editar',
                                style: TextStyle(fontSize: 11),
                              ),
                            ),
                          for (final a in visibleRecordActions(m, row).take(1))
                            TextButton(
                              onPressed: () => _action(row, a['key'] as String),
                              child: Text(
                                '${a['label']}',
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          if (_count > 0)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: _page > 1
                      ? () {
                          _page--;
                          _loadRecords();
                        }
                      : null,
                  icon: const Icon(Icons.chevron_left, size: 20),
                ),
                Flexible(
                  child: Text(
                    '$_count registros · Página $_page',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 11, color: AppTheme.muted),
                  ),
                ),
                IconButton(
                  onPressed: _page * 50 < _count
                      ? () {
                          _page++;
                          _loadRecords();
                        }
                      : null,
                  icon: const Icon(Icons.chevron_right, size: 20),
                ),
              ],
            ),
        ],
      ],
    );
  }

  Widget _recordMenu(
    Map<String, dynamic> row,
    Map<String, dynamic> m,
  ) => PopupMenuButton<String>(
    padding: EdgeInsets.zero,
    icon: const Icon(Icons.more_horiz, color: AppTheme.muted, size: 19),
    onSelected: (key) {
      if (key == 'edit') {
        _form(row);
      } else if (key == 'detail') {
        _detail(row);
      } else if (key == 'transition') {
        _transition(row);
      } else if (key == 'transport-event') {
        _transportEvent(row);
      } else if (key == 'assign') {
        _assign(row);
      } else {
        _action(row, key);
      }
    },
    itemBuilder: (_) => [
      const PopupMenuItem(value: 'detail', child: Text('Ver detalle')),
      if (_canRecordTransport(m, row))
        const PopupMenuItem(
          value: 'transport-event',
          child: Text('Registrar avance'),
        ),
      if (m['can_update'] == true)
        const PopupMenuItem(value: 'edit', child: Text('Editar')),
      for (final a in visibleRecordActions(m, row))
        PopupMenuItem<String>(
          value: a['key'] as String,
          child: Text('${a['label']}'),
        ),
      if (_module == 'exports' &&
          (row['allowed_transitions'] as List? ?? ['legacy']).isNotEmpty &&
          (m['permissions'] as List).any(
            (p) => ['submit', 'approve', 'reject'].contains(p),
          ))
        const PopupMenuItem(value: 'transition', child: Text('Cambiar estado')),
      if (_module == 'exports' && (m['permissions'] as List).contains('assign'))
        const PopupMenuItem(
          value: 'assign',
          child: Text('Asignar responsable'),
        ),
    ],
  );
  Widget _helper(String title, String text) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: const Color(0xFFEFF4EA),
      borderRadius: BorderRadius.circular(13),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline, color: AppTheme.forest, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                text,
                style: const TextStyle(fontSize: 11, color: AppTheme.muted),
              ),
            ],
          ),
        ),
      ],
    ),
  );
  Widget _documentOverview() {
    final approved = _records.where((r) => r['status'] == 'aprobado').length;
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2E7),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: AppTheme.forest,
            child: Icon(
              Icons.description_outlined,
              color: Colors.white,
              size: 23,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Documentos de esta vista',
                  style: TextStyle(fontSize: 11),
                ),
                const SizedBox(height: 4),
                Text(
                  '$approved aprobados de ${_records.length}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.forest,
                  ),
                ),
                const SizedBox(height: 9),
                ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: LinearProgressIndicator(
                    value: _records.isEmpty ? 0 : approved / _records.length,
                    color: AppTheme.forest,
                    backgroundColor: const Color(0xFFD5E2D0),
                    minHeight: 5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _assign(Map<String, dynamic> row) async {
    await _run(() async {
      final team = await api.getAll('/team/');
      if (!mounted) return;
      final id = await showDialog<int>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Asignar responsable de exportación'),
          children: [
            for (final user in team)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, user['id']),
                child: Text('${user['name']} · ${user['role']}'),
              ),
          ],
        ),
      );
      if (id != null) {
        await api.post('/exports/${row['id']}/assign/', {'user': id});
        await _loadRecords();
      }
    });
  }
}

class _DataView extends StatelessWidget {
  const _DataView({required this.value});
  final dynamic value;
  @override
  Widget build(BuildContext context) {
    if (value is Map) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final entry in (value as Map).entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    const {
                          'email': 'Correo',
                          'token': 'Código de invitación',
                          'expires_at': 'Válida hasta',
                          'number': 'Versión',
                          'filename': 'Archivo',
                          'sha256': 'Huella del archivo',
                          'created_at': 'Fecha',
                          'operations': 'Operaciones',
                          'currency': 'Moneda',
                          'costo': 'Costos',
                          'ingreso': 'Ingresos',
                          'presupuesto': 'Presupuesto',
                          'margin': 'Margen',
                          'margin_percent': 'Margen (%)',
                          'budget_variance': 'Variación presupuestaria',
                          'pending_payments': 'Pagos pendientes',
                        }['${entry.key}'] ??
                        '${entry.key}'.replaceAll('_', ' '),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  _DataView(value: entry.value),
                ],
              ),
            ),
        ],
      );
    }
    if (value is List) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final item in value as List)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: _DataView(value: item),
              ),
            ),
        ],
      );
    }
    return SelectableText(
      value == null
          ? '—'
          : value is bool
          ? (value == true ? 'Sí' : 'No')
          : '$value',
    );
  }
}
