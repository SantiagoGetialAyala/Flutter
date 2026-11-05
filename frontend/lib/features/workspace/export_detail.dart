import 'package:flutter/material.dart';
import '../../../core/services/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/brand.dart';
import 'presentation.dart';

class ExportDetail extends StatefulWidget {
  const ExportDetail({
    super.key,
    required this.api,
    required this.record,
    required this.canTransition,
    required this.onTransition,
    this.canViewDocuments = false,
  });
  final ApiClient api;
  final Map<String, dynamic> record;
  final bool canTransition, canViewDocuments;
  final Future<void> Function(Map<String, dynamic>) onTransition;
  @override
  State<ExportDetail> createState() => _ExportDetailState();
}

class _ExportDetailState extends State<ExportDetail> {
  late Map<String, dynamic> _record = widget.record;
  List<Map<String, dynamic>> _history = [], _documents = [];
  bool _loading = true;
  String? _error;
  int _tab = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        widget.api.getAll('/exports/${_record['id']}/history/'),
        if (widget.canViewDocuments)
          widget.api.getAll('/documents/?export=${_record['id']}'),
      ]);
      if (!mounted) return;
      setState(() {
        _history = results[0];
        if (results.length > 1) _documents = results[1];
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final mobile = size.width < 650;
    final tabs = [
      'Resumen',
      'Seguimiento',
      'Lotes',
      if (widget.canViewDocuments) 'Documentos',
    ];
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
                    if (widget.canTransition)
                      PopupMenuButton<String>(
                        onSelected: (_) async {
                          await widget.onTransition(_record);
                          try {
                            final fresh = await widget.api.getMap(
                              '/exports/${_record['id']}/',
                            );
                            if (mounted) setState(() => _record = fresh);
                            await _load();
                          } catch (e) {
                            if (mounted) setState(() => _error = '$e');
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'transition',
                            child: Text('Actualizar estado'),
                          ),
                        ],
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
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: switch (_tab) {
                    0 => _summary(),
                    1 => _timeline(),
                    2 => _lots(),
                    _ => _docs(),
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

  Widget _docs() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${_documents.length} documentos del expediente',
          style: const TextStyle(fontSize: 12, color: AppTheme.muted),
        ),
        const SizedBox(height: 14),
        if (_documents.isEmpty)
          const Text('No hay documentos disponibles para esta exportación.'),
        for (final doc in _documents)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: RecordCard(
              module: 'documents',
              record: doc,
              onTap: () => showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text('${doc['title']}'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      StatusPill(doc['status']),
                      const SizedBox(height: 15),
                      Text('Emisión: ${dateText(doc['issued_on'])}'),
                      Text('Vencimiento: ${dateText(doc['expires_on'])}'),
                      if (doc['review_notes'] != null &&
                          doc['review_notes'] != '')
                        Text('${doc['review_notes']}'),
                      const SizedBox(height: 12),
                      const Text(
                        'Gestiona las versiones y descargas desde Documentos.',
                        style: TextStyle(color: AppTheme.muted, fontSize: 12),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cerrar'),
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
