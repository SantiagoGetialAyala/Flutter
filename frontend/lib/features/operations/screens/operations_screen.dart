import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/services/api_client.dart';

class OperationsScreen extends StatefulWidget {
  const OperationsScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<OperationsScreen> createState() => _OperationsScreenState();
}

class _OperationsScreenState extends State<OperationsScreen> {
  late Future<List<Map<String, dynamic>>> _organizations = _loadOrganizations();
  String _module = 'producers';
  String? _organizationId;
  final _searchController = TextEditingController();
  String _search = '';
  Future<_RecordPage>? _records;
  int _page = 1;
  String? _error;

  static const _modules = <_Module>[
    _Module('producers', 'Productores', Icons.agriculture_outlined, [
      _Field('name', 'Nombre o razón social'),
      _Field('identification', 'Identificación', optional: true),
      _Field('email', 'Correo', optional: true),
      _Field('phone', 'Teléfono', optional: true),
      _Field('location', 'Ubicación general', optional: true),
    ]),
    _Module('farms', 'Fincas', Icons.landscape_outlined, [
      _Field('producer', 'Productor', endpoint: 'producers'),
      _Field('code', 'Código'),
      _Field('name', 'Nombre'),
      _Field('department', 'Departamento', optional: true),
      _Field('municipality', 'Municipio', optional: true),
      _Field('area', 'Superficie en hectáreas'),
    ]),
    _Module('crops', 'Cultivos', Icons.spa_outlined, [
      _Field('farm', 'Finca', endpoint: 'farms'),
      _Field('name', 'Nombre del cultivo'),
      _Field(
        'product_type',
        'Producto',
        choices: {'cafe': 'Café', 'cacao': 'Cacao'},
      ),
      _Field('variety', 'Variedad', optional: true),
      _Field('planted_area', 'Área sembrada'),
      _Field('planted_on', 'Fecha de siembra (AAAA-MM-DD)', optional: true),
    ]),
    _Module('plots', 'Parcelas', Icons.map_outlined, [
      _Field('farm', 'Finca', endpoint: 'farms'),
      _Field('code', 'Código'),
      _Field('name', 'Nombre', optional: true),
      _Field('area', 'Superficie en hectáreas'),
      _Field(
        'crop_type',
        'Cultivo',
        choices: {'cafe': 'Café', 'cacao': 'Cacao'},
      ),
      _Field(
        'geometry',
        'GeoJSON de ubicación (Point, Polygon o MultiPolygon)',
        json: true,
      ),
    ]),
    _Module('harvests', 'Cosechas', Icons.grass_outlined, [
      _Field('plot', 'Parcela', endpoint: 'plots'),
      _Field('harvest_date', 'Fecha (AAAA-MM-DD)'),
      _Field(
        'product_type',
        'Producto',
        choices: {'cafe': 'Café', 'cacao': 'Cacao'},
      ),
      _Field('quantity', 'Cantidad'),
      _Field('unit', 'Unidad', choices: {'kg': 'kg', 'tonelada': 'Tonelada'}),
      _Field('notes', 'Observaciones', optional: true),
    ]),
    _Module('certifications', 'Certificaciones', Icons.verified_outlined, [
      _Field('producer', 'Productor', endpoint: 'producers'),
      _Field('name', 'Certificación'),
      _Field('issuer', 'Entidad emisora', optional: true),
      _Field('certificate_code', 'Código', optional: true),
      _Field('issued_on', 'Fecha de emisión (AAAA-MM-DD)', optional: true),
      _Field('expires_on', 'Vencimiento (AAAA-MM-DD)', optional: true),
    ]),
    _Module('lots', 'Lotes e inventario', Icons.inventory_2_outlined, [
      _Field('producer', 'Productor', endpoint: 'producers'),
      _Field('code', 'Código único'),
      _Field(
        'product_type',
        'Producto',
        choices: {'cafe': 'Café', 'cacao': 'Cacao'},
      ),
      _Field('variety', 'Variedad', optional: true),
      _Field('presentation', 'Presentación', optional: true),
      _Field('processing', 'Procesamiento', optional: true),
      _Field('fermentation', 'Fermentación', optional: true),
      _Field('drying', 'Secado', optional: true),
      _Field('humidity_percent', 'Humedad %', optional: true),
      _Field('classification', 'Clasificación', optional: true),
      _Field('quantity_initial', 'Cantidad inicial'),
      _Field('unit', 'Unidad', choices: {'kg': 'kg', 'tonelada': 'Tonelada'}),
    ]),
    _Module(
      'lot-relationships',
      'Mezclas y transformaciones',
      Icons.hub_outlined,
      [
        _Field('source_lot', 'Lote de origen', endpoint: 'lots'),
        _Field('target_lot', 'Lote resultante', endpoint: 'lots'),
        _Field(
          'relation_type',
          'Relación',
          choices: {
            'derivado': 'Derivado',
            'mezcla': 'Mezcla',
            'transformacion': 'Transformación',
          },
        ),
        _Field('quantity', 'Cantidad consumida del lote de origen'),
        _Field('output_quantity', 'Cantidad recibida por el lote resultante'),
        _Field('notes', 'Observaciones', optional: true),
      ],
    ),
    _Module(
      'inventory-movements',
      'Movimientos de inventario',
      Icons.swap_vert_circle_outlined,
      [
        _Field('lot', 'Lote', endpoint: 'lots'),
        _Field(
          'movement_type',
          'Movimiento',
          choices: {
            'entrada': 'Entrada',
            'salida': 'Salida',
            'ajuste': 'Ajuste',
          },
        ),
        _Field('quantity', 'Cantidad'),
        _Field('reference', 'Referencia', optional: true),
        _Field('notes', 'Observaciones', optional: true),
      ],
    ),
    _Module('exports', 'Exportaciones', Icons.local_shipping_outlined, [
      _Field('code', 'Código único'),
      _Field('importer', 'Importador / cliente', endpoint: 'clients'),
      _Field('destination_country', 'País de destino'),
      _Field('destination_place', 'Ciudad o lugar', optional: true),
      _Field('incoterm', 'Incoterm', optional: true),
      _Field('incoterm_version', 'Versión Incoterm', optional: true),
      _Field('departure_port', 'Puerto de salida', optional: true),
      _Field('arrival_port', 'Puerto de llegada', optional: true),
      _Field(
        'estimated_departure',
        'Salida estimada (AAAA-MM-DD)',
        optional: true,
      ),
      _Field(
        'estimated_arrival',
        'Llegada estimada (AAAA-MM-DD)',
        optional: true,
      ),
      _Field('gross_weight', 'Peso bruto', optional: true),
      _Field('net_weight', 'Peso neto', optional: true),
      _Field('currency', 'Moneda (ISO 4217)', optional: true),
      _Field('commercial_value', 'Valor comercial', optional: true),
      _Field('notes', 'Condiciones u observaciones', optional: true),
    ]),
    _Module(
      'export-allocations',
      'Reservas de lotes',
      Icons.add_shopping_cart_outlined,
      [
        _Field('export', 'Exportación', endpoint: 'exports'),
        _Field('lot', 'Lote', endpoint: 'lots'),
        _Field('quantity', 'Cantidad a reservar'),
        _Field('unit', 'Unidad', choices: {'kg': 'kg', 'tonelada': 'Tonelada'}),
      ],
    ),
    _Module('traceability-events', 'Trazabilidad', Icons.timeline_outlined, [
      _Field('lot', 'Lote', endpoint: 'lots'),
      _Field('event_type', 'Tipo de evento'),
      _Field('event_at', 'Fecha y hora ISO 8601'),
      _Field('quantity', 'Cantidad (opcional)', optional: true),
      _Field('notes', 'Observaciones', optional: true),
    ]),
  ];

  _Module get _selectedModule =>
      _modules.firstWhere((item) => item.endpoint == _module);

  Future<List<Map<String, dynamic>>> _loadOrganizations() async {
    final items = (await widget.api.getList(
      '/organizations/',
    )).cast<Map<String, dynamic>>();
    if (items.isNotEmpty) {
      final current = await widget.api.activeOrganizationId;
      final selected = items.any((item) => '${item['id']}' == current)
          ? current!
          : '${items.first['id']}';
      _organizationId = selected;
      await widget.api.setActiveOrganization(selected);
      _records = _loadRecords();
    }
    return items;
  }

  Future<_RecordPage> _loadRecords() async {
    final response = await widget.api.getMap(
      '/$_module/?search=${Uri.encodeQueryComponent(_search)}&page=$_page',
    );
    return _RecordPage(
      items: (response['results'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>(),
      count: response['count'] as int? ?? 0,
    );
  }

  void _reload() => setState(() => _records = _loadRecords());

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _createOrganization() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Registrar organización exportadora'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nombre de la empresa'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Crear'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    try {
      final organization = await widget.api.post('/organizations/', {
        'name': name,
      });
      await widget.api.setActiveOrganization('${organization['id']}');
      if (mounted) {
        setState(() {
          _error = null;
          _organizations = _loadOrganizations();
        });
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Future<void> _createRecord() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _RecordForm(api: widget.api, module: _selectedModule),
    );
    if (saved == true) _reload();
  }

  Future<void> _openExport(Map<String, dynamic> record) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _ExportDetails(api: widget.api, record: record),
    );
    if (changed == true) _reload();
  }

  Future<void> _openLot(Map<String, dynamic> record) async {
    try {
      final trace = await widget.api.getMap(
        '/lots/${record['id']}/traceability/',
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => _LotTraceability(trace: trace),
      );
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _organizations,
      builder: (context, snapshot) {
        final organizations = snapshot.data ?? const [];
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        return _OperationsPage(
          organizations: organizations,
          error: _error,
          api: widget.api,
          organizationId: _organizationId,
          onCreateOrganization: _createOrganization,
          module: _selectedModule,
          modules: _modules,
          records: _records,
          onModuleChanged: (module) async {
            setState(() {
              _module = module;
              _page = 1;
              _records = _loadRecords();
            });
          },
          onCreate: _createRecord,
          onOpenExport: _openExport,
          onOpenLot: _openLot,
          onRefresh: _reload,
          searchController: _searchController,
          onSearch: (value) {
            setState(() {
              _search = value.trim();
              _page = 1;
              _records = _loadRecords();
            });
          },
          page: _page,
          onPage: (value) {
            setState(() {
              _page = value;
              _records = _loadRecords();
            });
          },
          onOrganizationChanged: (value) async {
            await widget.api.setActiveOrganization(value);
            setState(() {
              _organizationId = value;
              _page = 1;
              _records = _loadRecords();
            });
          },
        );
      },
    );
  }
}

class _OperationsPage extends StatelessWidget {
  const _OperationsPage({
    required this.organizations,
    required this.error,
    required this.api,
    required this.organizationId,
    required this.onCreateOrganization,
    required this.module,
    required this.modules,
    required this.records,
    required this.onModuleChanged,
    required this.onCreate,
    required this.onOpenExport,
    required this.onOpenLot,
    required this.onRefresh,
    required this.searchController,
    required this.onSearch,
    required this.page,
    required this.onPage,
    required this.onOrganizationChanged,
  });

  final List<Map<String, dynamic>> organizations;
  final String? error;
  final ApiClient api;
  final String? organizationId;
  final VoidCallback onCreateOrganization;
  final _Module module;
  final List<_Module> modules;
  final Future<_RecordPage>? records;
  final ValueChanged<String> onModuleChanged;
  final VoidCallback onCreate;
  final ValueChanged<Map<String, dynamic>> onOpenExport;
  final ValueChanged<Map<String, dynamic>> onOpenLot;
  final VoidCallback onRefresh;
  final TextEditingController searchController;
  final ValueChanged<String> onSearch;
  final int page;
  final ValueChanged<int> onPage;
  final ValueChanged<String> onOrganizationChanged;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Origen y exportaciones',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        const Text(
          'Administra productores, parcelas, lotes, inventario, expediciones y su trazabilidad.',
        ),
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 16),
        if (organizations.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Primero registra la organización que será propietaria de estos datos.',
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: onCreateOrganization,
                    icon: const Icon(Icons.add_business_outlined),
                    label: const Text('Crear organización'),
                  ),
                ],
              ),
            ),
          )
        else ...[
          if (organizations.length > 1)
            DropdownButtonFormField<String>(
              initialValue: organizationId,
              decoration: const InputDecoration(
                labelText: 'Organización activa',
              ),
              items: [
                for (final item in organizations)
                  DropdownMenuItem(
                    value: '${item['id']}',
                    child: Text(item['name'] as String),
                  ),
              ],
              onChanged: (value) {
                if (value != null) {
                  onOrganizationChanged(value);
                }
              },
            ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: module.endpoint,
            decoration: const InputDecoration(labelText: 'Módulo'),
            items: [
              for (final item in modules)
                DropdownMenuItem(value: item.endpoint, child: Text(item.title)),
            ],
            onChanged: (value) {
              if (value != null) onModuleChanged(value);
            },
          ),
          const SizedBox(height: 14),
          TextField(
            controller: searchController,
            decoration: InputDecoration(
              labelText: 'Buscar en ${module.title.toLowerCase()}',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                icon: const Icon(Icons.search),
                onPressed: () => onSearch(searchController.text),
              ),
            ),
            onSubmitted: onSearch,
          ),
          const SizedBox(height: 12),
          FutureBuilder<_RecordPage>(
            future: records,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(snapshot.error.toString()),
                  ),
                );
              }
              final result =
                  snapshot.data ?? const _RecordPage(items: [], count: 0);
              final items = result.items;
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              module.title,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          IconButton(
                            onPressed: onRefresh,
                            icon: const Icon(Icons.refresh),
                            tooltip: 'Actualizar',
                          ),
                          FilledButton.icon(
                            onPressed: onCreate,
                            icon: const Icon(Icons.add),
                            label: const Text('Nuevo'),
                          ),
                        ],
                      ),
                      const Divider(),
                      if (items.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Text(
                            'Todavía no hay registros en este módulo.',
                          ),
                        )
                      else
                        for (final item in items)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              module.icon,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            title: Text(_recordTitle(item)),
                            subtitle: Text(_recordSubtitle(item)),
                            onTap: module.endpoint == 'exports'
                                ? () => onOpenExport(item)
                                : module.endpoint == 'lots'
                                ? () => onOpenLot(item)
                                : null,
                          ),
                      if (result.count > 50) ...[
                        const Divider(),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            IconButton(
                              onPressed: page > 1
                                  ? () => onPage(page - 1)
                                  : null,
                              icon: const Icon(Icons.chevron_left),
                              tooltip: 'Página anterior',
                            ),
                            Text(
                              'Página $page de ${(result.count / 50).ceil()}',
                            ),
                            IconButton(
                              onPressed: page * 50 < result.count
                                  ? () => onPage(page + 1)
                                  : null,
                              icon: const Icon(Icons.chevron_right),
                              tooltip: 'Página siguiente',
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ],
    );
  }

  String _recordTitle(Map<String, dynamic> item) =>
      '${item['name'] ?? item['code'] ?? item['event_type'] ?? item['movement_type'] ?? item['id']}';
  String _recordSubtitle(Map<String, dynamic> item) {
    final parts = <String>[];
    for (final key in [
      'product_type',
      'quantity_available',
      'quantity_initial',
      'quantity',
      'unit',
      'status_display',
      'status',
      'harvest_date',
      'destination_country',
      'municipality',
      'department',
    ]) {
      if (item[key] != null && item[key].toString().isNotEmpty) {
        parts.add('${_pretty(key)}: ${item[key]}');
      }
    }
    return parts.join(' · ');
  }

  String _pretty(String key) => key.replaceAll('_', ' ');
}

class _LotTraceability extends StatelessWidget {
  const _LotTraceability({required this.trace});
  final Map<String, dynamic> trace;

  @override
  Widget build(BuildContext context) {
    final lot = trace['lot'] as Map<String, dynamic>? ?? const {};
    final origin = trace['origin'] as Map<String, dynamic>? ?? const {};
    final events = trace['events'] as List<dynamic>? ?? const [];
    final exports = trace['exports'] as List<dynamic>? ?? const [];
    final derivedFrom = trace['derived_from'] as List<dynamic>? ?? const [];
    final derivedInto = trace['derived_into'] as List<dynamic>? ?? const [];
    return AlertDialog(
      title: Text('Trazabilidad · ${lot['code'] ?? 'Lote'}'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Productor: ${origin['producer'] ?? '—'}'),
              Text(
                'Finca: ${origin['farm'] ?? '—'} · Parcela: ${origin['plot'] ?? '—'}',
              ),
              Text('Cosecha: ${origin['harvest_date'] ?? '—'}'),
              Text('Código de consulta segura: ${lot['public_id'] ?? '—'}'),
              const SizedBox(height: 12),
              const Text(
                'Eventos',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              if (events.isEmpty)
                const Text('Todavía no hay eventos de trazabilidad.')
              else
                for (final event in events)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('${event['event_type']}'),
                    subtitle: Text(
                      '${event['event_at']} · ${event['notes'] ?? ''}',
                    ),
                  ),
              const SizedBox(height: 8),
              Text(
                'Exportaciones asociadas: ${exports.map((item) => item['export__code']).join(', ')}',
              ),
              Text(
                'Lotes de origen: ${derivedFrom.map((item) => item['source_lot__code']).join(', ')}',
              ),
              Text(
                'Lotes derivados: ${derivedInto.map((item) => item['target_lot__code']).join(', ')}',
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
      ],
    );
  }
}

class _ExportDetails extends StatefulWidget {
  const _ExportDetails({required this.api, required this.record});
  final ApiClient api;
  final Map<String, dynamic> record;

  @override
  State<_ExportDetails> createState() => _ExportDetailsState();
}

class _ExportDetailsState extends State<_ExportDetails> {
  late final Future<List<Map<String, dynamic>>> _history = widget.api
      .getList('/exports/${widget.record['id']}/history/')
      .then((items) => items.cast<Map<String, dynamic>>());
  String? _next;
  bool _saving = false;
  String? _error;

  static const _transitions = <String, List<String>>{
    'borrador': ['pendiente_documentacion', 'cancelada'],
    'pendiente_documentacion': ['en_revision', 'cancelada'],
    'en_revision': ['requiere_correcciones', 'aprobada_despacho', 'rechazada'],
    'requiere_correcciones': ['pendiente_documentacion', 'cancelada'],
    'aprobada_despacho': ['preparacion_logistica', 'bloqueada'],
    'preparacion_logistica': ['transporte_terrestre', 'embarcada', 'bloqueada'],
    'transporte_terrestre': ['embarcada', 'bloqueada'],
    'embarcada': ['transito_internacional', 'bloqueada'],
    'transito_internacional': ['arribada', 'bloqueada'],
    'arribada': ['entregada', 'bloqueada'],
    'entregada': ['cerrada'],
  };

  static const _labels = <String, String>{
    'borrador': 'Borrador',
    'pendiente_documentacion': 'Pendiente de documentación',
    'en_revision': 'En revisión',
    'requiere_correcciones': 'Requiere correcciones',
    'aprobada_despacho': 'Aprobada para despacho',
    'preparacion_logistica': 'En preparación logística',
    'transporte_terrestre': 'En transporte terrestre',
    'embarcada': 'Embarcada',
    'transito_internacional': 'En tránsito internacional',
    'arribada': 'Arribada a destino',
    'entregada': 'Entregada',
    'cerrada': 'Cerrada',
    'bloqueada': 'Bloqueada',
    'rechazada': 'Rechazada',
    'cancelada': 'Cancelada',
  };

  Future<void> _transition() async {
    if (_next == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.post('/exports/${widget.record['id']}/transition/', {
        'status': _next,
      });
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = '${widget.record['status']}';
    final nextStatuses = _transitions[status] ?? const <String>[];
    final allocations =
        (widget.record['allocations'] as List<dynamic>? ?? const []);
    return AlertDialog(
      title: Text('${widget.record['code']} · ${_labels[status] ?? status}'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Importador: ${widget.record['importer_name'] ?? '—'}'),
              Text(
                'Destino: ${widget.record['destination_place'] ?? ''}, ${widget.record['destination_country'] ?? '—'}',
              ),
              Text('Incoterm: ${widget.record['incoterm'] ?? '—'}'),
              const SizedBox(height: 12),
              const Text(
                'Lotes reservados',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              if (allocations.isEmpty)
                const Text('No hay lotes asociados.')
              else
                for (final item in allocations)
                  Text(
                    '${item['lot_code']}: ${item['quantity']} ${item['unit']}',
                  ),
              const SizedBox(height: 12),
              const Text(
                'Historial de estados',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              FutureBuilder<List<Map<String, dynamic>>>(
                future: _history,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const LinearProgressIndicator();
                  }
                  if (snapshot.hasError) {
                    return Text(
                      'No se pudo cargar el historial: ${snapshot.error}',
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final event in snapshot.data ?? const [])
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.circle, size: 10),
                          title: Text(
                            _labels['${event['new_status']}'] ??
                                '${event['new_status']}',
                          ),
                          subtitle: Text(
                            '${event['created_at']} · ${event['actor'] ?? ''}',
                          ),
                        ),
                    ],
                  );
                },
              ),
              if (nextStatuses.isNotEmpty) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _next,
                  decoration: const InputDecoration(
                    labelText: 'Siguiente estado',
                  ),
                  items: [
                    for (final value in nextStatuses)
                      DropdownMenuItem(
                        value: value,
                        child: Text(_labels[value] ?? value),
                      ),
                  ],
                  onChanged: (value) => setState(() => _next = value),
                ),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
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
        if (nextStatuses.isNotEmpty)
          FilledButton(
            onPressed: _saving || _next == null ? null : _transition,
            child: _saving
                ? const CircularProgressIndicator()
                : const Text('Cambiar estado'),
          ),
      ],
    );
  }
}

class _RecordForm extends StatefulWidget {
  const _RecordForm({required this.api, required this.module});
  final ApiClient api;
  final _Module module;

  @override
  State<_RecordForm> createState() => _RecordFormState();
}

class _RecordFormState extends State<_RecordForm> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, String?> _selected = {};
  final Map<String, Future<List<Map<String, dynamic>>>> _options = {};
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final field in widget.module.fields) {
      _controllers[field.name] = TextEditingController();
      if (field.endpoint != null) {
        _options[field.name] = _loadOptions(field.endpoint!);
      }
    }
  }

  Future<List<Map<String, dynamic>>> _loadOptions(String endpoint) async =>
      (await widget.api.getList('/$endpoint/')).cast<Map<String, dynamic>>();

  @override
  void dispose() {
    for (final item in _controllers.values) {
      item.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final data = <String, dynamic>{};
    try {
      for (final field in widget.module.fields) {
        if (field.endpoint != null) {
          final value = _selected[field.name];
          if (value != null) data[field.name] = int.parse(value);
        } else {
          final raw = _controllers[field.name]!.text.trim();
          if (raw.isEmpty && field.optional) {
            continue;
          }
          if (field.json) {
            data[field.name] = jsonDecode(raw);
          } else if ({
            'area',
            'planted_area',
            'quantity',
            'quantity_initial',
            'output_quantity',
            'humidity_percent',
            'commercial_value',
            'gross_weight',
            'net_weight',
          }.contains(field.name)) {
            data[field.name] = num.parse(raw);
          } else {
            data[field.name] = raw;
          }
        }
      }
      setState(() {
        _saving = true;
        _error = null;
      });
      await widget.api.post('/${widget.module.endpoint}/', data);
      if (mounted) {
        Navigator.pop(context, true);
      }
    } on FormatException catch (_) {
      if (mounted) {
        setState(() => _error = 'Revisa los números y el GeoJSON ingresado.');
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Nuevo registro · ${widget.module.title}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 18),
                for (final field in widget.module.fields) ...[
                  if (field.endpoint != null)
                    _relationship(field)
                  else if (field.choices != null)
                    DropdownButtonFormField<String>(
                      initialValue: _selected[field.name],
                      decoration: InputDecoration(labelText: field.label),
                      items: [
                        for (final item in field.choices!.entries)
                          DropdownMenuItem(
                            value: item.key,
                            child: Text(item.value),
                          ),
                      ],
                      validator: (value) => !field.optional && value == null
                          ? 'Selecciona una opción.'
                          : null,
                      onChanged: (value) =>
                          setState(() => _selected[field.name] = value),
                    )
                  else
                    TextFormField(
                      controller: _controllers[field.name],
                      minLines: field.json || field.name == 'notes' ? 3 : 1,
                      maxLines: field.json || field.name == 'notes' ? 6 : 1,
                      keyboardType:
                          {
                            'area',
                            'planted_area',
                            'quantity',
                            'quantity_initial',
                            'output_quantity',
                            'humidity_percent',
                            'commercial_value',
                            'gross_weight',
                            'net_weight',
                          }.contains(field.name)
                          ? const TextInputType.numberWithOptions(decimal: true)
                          : TextInputType.text,
                      decoration: InputDecoration(
                        labelText: field.label,
                        hintText: field.json
                            ? '{"type":"Point","coordinates":[-75.5,6.2]}'
                            : null,
                      ),
                      validator: (value) =>
                          !field.optional &&
                              (value == null || value.trim().isEmpty)
                          ? 'Este campo es obligatorio.'
                          : null,
                    ),
                  const SizedBox(height: 12),
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const CircularProgressIndicator()
                      : const Text('Guardar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _relationship(
    _Field field,
  ) => FutureBuilder<List<Map<String, dynamic>>>(
    future: _options[field.name],
    builder: (context, snapshot) {
      final items = snapshot.data ?? const [];
      return DropdownButtonFormField<String>(
        initialValue: _selected[field.name],
        decoration: InputDecoration(labelText: field.label),
        items: [
          for (final item in items)
            DropdownMenuItem(
              value: '${item['id']}',
              child: Text(
                '${item['name'] ?? item['code'] ?? item['business_name'] ?? item['id']}',
              ),
            ),
        ],
        validator: (value) => snapshot.hasError
            ? 'No se pudieron cargar las opciones.'
            : value == null
            ? 'Selecciona una opción.'
            : null,
        onChanged: snapshot.connectionState == ConnectionState.done
            ? (value) => setState(() => _selected[field.name] = value)
            : null,
      );
    },
  );
}

class _RecordPage {
  const _RecordPage({required this.items, required this.count});
  final List<Map<String, dynamic>> items;
  final int count;
}

class _Module {
  const _Module(this.endpoint, this.title, this.icon, this.fields);
  final String endpoint;
  final String title;
  final IconData icon;
  final List<_Field> fields;
}

class _Field {
  const _Field(
    this.name,
    this.label, {
    this.endpoint,
    this.choices,
    this.optional = false,
    this.json = false,
  });
  final String name;
  final String label;
  final String? endpoint;
  final Map<String, String>? choices;
  final bool optional;
  final bool json;
}
