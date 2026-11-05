import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/brand.dart';

IconData moduleIcon(String key) => switch (key) {
  'exports' ||
  'platform-organizations' ||
  'organizations' => Icons.work_outline_rounded,
  'lots' || 'products' || 'export-allocations' => Icons.inventory_2_outlined,
  'producers' ||
  'farms' ||
  'crops' ||
  'plots' ||
  'harvests' => Icons.agriculture_outlined,
  'documents' ||
  'requirements' ||
  'checklist' ||
  'compliance' ||
  'certifications' => Icons.description_outlined,
  'transports' ||
  'vehicles' ||
  'drivers' ||
  'transport-events' => Icons.local_shipping_outlined,
  'finance' || 'quotes' || 'exchange-rates' => Icons.bar_chart_rounded,
  'members' ||
  'platform-users' ||
  'clients' ||
  'suppliers' ||
  'invitations' => Icons.people_outline_rounded,
  'activities' => Icons.event_note_outlined,
  'orders' => Icons.shopping_bag_outlined,
  'notifications' => Icons.notifications_none_rounded,
  'incidents' || 'technical-incidents' => Icons.report_outlined,
  'audit' => Icons.history_rounded,
  'roles' || 'grants' => Icons.admin_panel_settings_outlined,
  _ => Icons.tune_rounded,
};

String sectionFor(String key) {
  if ([
    'platform-organizations',
    'platform-users',
    'roles',
    'grants',
    'platform-settings',
    'technical-incidents',
    'audit',
    'countries',
  ].contains(key)) {
    return 'PLATAFORMA';
  }
  if ([
    'producers',
    'farms',
    'crops',
    'plots',
    'harvests',
    'certifications',
    'lots',
    'inventory-movements',
    'lot-relationships',
    'traceability-events',
  ].contains(key)) {
    return 'ORIGEN Y PRODUCTOS';
  }
  if ([
    'organizations',
    'members',
    'invitations',
    'organization-settings',
    'clients',
    'suppliers',
    'notifications',
  ].contains(key)) {
    return 'MI ORGANIZACIÓN';
  }
  return 'OPERACIÓN';
}

String friendly(dynamic value) {
  final text = value?.toString() ?? '';
  return const {
        'activa': 'Activa',
        'suspendida': 'Suspendida',
        'desactivada': 'Desactivada',
        'borrador': 'Borrador',
        'pendiente_documentacion': 'Documentación pendiente',
        'en_revision': 'En revisión',
        'requiere_correcciones': 'Requiere correcciones',
        'aprobada_despacho': 'Aprobada',
        'preparacion_logistica': 'Preparando envío',
        'transporte_terrestre': 'En transporte',
        'embarcada': 'Embarcada',
        'transito_internacional': 'En tránsito',
        'arribada': 'En destino',
        'entregada': 'Entregada',
        'entregado': 'Entregado',
        'cerrada': 'Completada',
        'bloqueada': 'Bloqueada',
        'rechazada': 'Rechazada',
        'cancelada': 'Cancelada',
        'pendiente': 'Pendiente',
        'aprobado': 'Aprobado',
        'rechazado': 'Rechazado',
        'correcciones': 'Correcciones',
        'asignado': 'Asignado',
        'recogido': 'Recogido',
        'en_transito': 'En tránsito',
        'cafe': 'Café',
        'cacao': 'Cacao',
        'conforme': 'Conforme',
        'no_conforme': 'No conforme',
        'administrador': 'Administrador',
        'superadmin': 'Superadministrador',
        'productor': 'Productor',
        'exportaciones': 'Exportaciones',
        'documental': 'Documental',
        'logistica': 'Logística',
        'financiero': 'Financiero',
        'comercial': 'Comercial',
        'gerencia': 'Gerencia',
        'importador': 'Importador',
        'pagado': 'Pagado',
        'parcial': 'Pago parcial',
        'costo': 'Costo',
        'ingreso': 'Ingreso',
        'presupuesto': 'Presupuesto',
      }[text] ??
      (text.isEmpty ? '—' : text.replaceAll('_', ' '));
}

String number(dynamic value) {
  final n = num.tryParse('$value');
  if (n == null) return '$value';
  final fixed = n.toStringAsFixed(n == n.roundToDouble() ? 0 : 2).split('.');
  final integer = fixed.first.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]}.',
  );
  return '$integer${fixed.length > 1 ? ',${fixed[1]}' : ''}';
}

String dateText(dynamic value, {bool time = false}) {
  final date = DateTime.tryParse('$value')?.toLocal();
  if (date == null) return 'Por definir';
  const months = [
    'ene',
    'feb',
    'mar',
    'abr',
    'may',
    'jun',
    'jul',
    'ago',
    'sep',
    'oct',
    'nov',
    'dic',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}${time ? ' · ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}' : ''}';
}

double exportProgress(dynamic status) => switch (status) {
  'borrador' => .05,
  'pendiente_documentacion' => .15,
  'en_revision' || 'requiere_correcciones' => .25,
  'aprobada_despacho' => .4,
  'preparacion_logistica' => .5,
  'transporte_terrestre' => .6,
  'embarcada' => .7,
  'transito_internacional' => .8,
  'arribada' => .9,
  'entregada' || 'cerrada' => 1,
  _ => 0,
};

class StatusPill extends StatelessWidget {
  const StatusPill(this.status, {super.key});
  final dynamic status;
  @override
  Widget build(BuildContext context) {
    final red = [
      'rechazado',
      'rechazada',
      'cancelada',
      'bloqueada',
      'no_conforme',
      'correcciones',
      'requiere_correcciones',
    ].contains(status);
    final amber = [
      'pendiente',
      'en_revision',
      'pendiente_documentacion',
      'borrador',
      'asignado',
      'parcial',
    ].contains(status);
    final fg = red
        ? const Color(0xFFA5483D)
        : amber
        ? const Color(0xFF966C16)
        : AppTheme.forest;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: red
            ? const Color(0xFFFCECE7)
            : amber
            ? const Color(0xFFFFF2CF)
            : const Color(0xFFE8F3E7),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        friendly(status),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }
}

class RecordCard extends StatelessWidget {
  const RecordCard({
    super.key,
    required this.module,
    required this.record,
    required this.onTap,
    this.menu,
  });
  final String module;
  final Map<String, dynamic> record;
  final VoidCallback onTap;
  final Widget? menu;

  @override
  Widget build(BuildContext context) {
    final r = record;
    final title =
        '${r['title'] ?? r['name'] ?? r['business_name'] ?? r['code'] ?? r['reference'] ?? r['email'] ?? r['description'] ?? r['plate'] ?? r['key'] ?? 'Registro #${r['id']}'}';
    final photo = [
      'exports',
      'lots',
      'products',
      'farms',
      'producers',
      'harvests',
    ].contains(module);
    final status =
        r['status'] ??
        r['payment_status'] ??
        r['account_status'] ??
        (module == 'platform-organizations'
            ? (r['is_active'] == false ? 'desactivada' : 'activa')
            : null);
    final subtitle = module == 'exports'
        ? (r['allocations'] is List && (r['allocations'] as List).isNotEmpty
              ? '${(r['allocations'] as List).length} lote(s) de origen'
              : 'Operación de exportación')
        : r['product_type'] != null
        ? '${friendly(r['product_type'])}${r['variety'] != null && r['variety'] != '' ? ' · ${r['variety']}' : ''}'
        : r['role'] != null
        ? friendly(r['role'])
        : module == 'documents'
        ? friendly(r['document_type'])
        : r['email'] ??
              r['identification'] ??
              r['pickup_place'] ??
              (r['export'] != null ? 'Exportación #${r['export']}' : null);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.line),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF172C24).withValues(alpha: .035),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (photo)
                      const OriginImage(
                        width: 61,
                        height: 66,
                        alignment: Alignment(0, .75),
                      )
                    else
                      Container(
                        width: 43,
                        height: 47,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0F5ED),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          moduleIcon(module),
                          size: 23,
                          color: AppTheme.forest,
                        ),
                      ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              letterSpacing: -.25,
                            ),
                          ),
                          if (subtitle != null && '$subtitle'.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Text(
                                '$subtitle',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.muted,
                                ),
                              ),
                            ),
                          if (r['destination_country'] != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 5),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.public,
                                    size: 12,
                                    color: AppTheme.forest,
                                  ),
                                  const SizedBox(width: 5),
                                  Expanded(
                                    child: Text(
                                      '${r['destination_country']}',
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (module == 'lots')
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                'Disponible: ${number(r['quantity_available'])} ${r['unit'] ?? 'kg'}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          if (r['amount'] != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                '${r['currency'] ?? ''} ${number(r['amount'])}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (status != null)
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 126),
                            child: StatusPill(status),
                          ),
                        if (menu != null)
                          SizedBox(height: 30, width: 32, child: menu),
                      ],
                    ),
                  ],
                ),
                if (module == 'exports') ...[
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: exportProgress(r['status']),
                      minHeight: 5,
                      backgroundColor: const Color(0xFFEBEEE8),
                      color: const Color(0xFF438558),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          r['net_weight'] != null
                              ? '${number(r['net_weight'])} kg'
                              : r['allocations'] is List
                              ? '${(r['allocations'] as List).length} lotes asociados'
                              : 'Sin lotes asociados',
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppTheme.muted,
                          ),
                        ),
                      ),
                      Text(
                        'Salida: ${dateText(r['estimated_departure'])}',
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppTheme.muted,
                        ),
                      ),
                    ],
                  ),
                ],
                if (r['scheduled_pickup'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      'Recogida · ${dateText(r['scheduled_pickup'], time: true)}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.muted,
                      ),
                    ),
                  ),
                if (module == 'documents' && r['expires_on'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      'Vence el ${dateText(r['expires_on'])}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppTheme.muted,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
