import 'package:flutter/material.dart';

const lifecycleStages = [
  'Datos comerciales y destino',
  'Productos y lotes',
  'Preparación documental',
  'Coordinación logística',
  'Seguimiento y cierre',
];

int lifecycleStage(String status) => switch (status) {
  'borrador' => 0,
  'pendiente_documentacion' ||
  'en_revision' ||
  'requiere_correcciones' ||
  'bloqueada' ||
  'rechazada' => 2,
  'aprobada_despacho' || 'preparacion_logistica' => 3,
  _ => 4,
};

String nextStep(String status) => switch (status) {
  'borrador' =>
    'Completa los datos, reserva los lotes y solicita los documentos.',
  'pendiente_documentacion' =>
    'Reúne los soportes y solicita la revisión documental.',
  'en_revision' =>
    'El equipo documental debe verificar requisitos y registrar su decisión.',
  'requiere_correcciones' =>
    'Consulta las observaciones y corrige los documentos indicados.',
  'aprobada_despacho' =>
    'Coordina el vehículo, el conductor y las fechas de recogida.',
  'preparacion_logistica' =>
    'Confirma la recogida con sus evidencias para iniciar el envío.',
  'transporte_terrestre' || 'embarcada' || 'transito_internacional' =>
    'Registra los avances y confirma la llegada cuando ocurra.',
  'arribada' => 'Confirma la entrega y conserva sus evidencias.',
  'entregada' => 'Revisa los pendientes antes de cerrar la operación.',
  'cerrada' =>
    'Operación completada. Puedes consultar el expediente y su historial.',
  'cancelada' || 'rechazada' =>
    'Consulta el historial para conocer el motivo y las decisiones registradas.',
  'bloqueada' =>
    'Revisa el motivo del bloqueo con administración o cumplimiento documental.',
  _ => 'Consulta el expediente para continuar con tu equipo.',
};

String workLabel(String role) => switch (role) {
  'productor' => 'Producción',
  'importador' => 'Pedidos',
  'logistica' => 'Mis envíos',
  'documental' => 'Revisiones',
  'financiero' => 'Finanzas',
  'superadmin' => 'Empresas',
  _ => 'Operaciones',
};

List<String> workModules(String role) => switch (role) {
  'productor' => ['lots', 'farms', 'harvests', 'transports'],
  'importador' => ['orders', 'exports', 'transports', 'documents'],
  'logistica' => ['transports', 'transport-events', 'documents'],
  'documental' => ['documents', 'exports', 'checklist', 'compliance'],
  'financiero' => ['finance', 'quotes', 'exports'],
  'superadmin' => ['platform-organizations', 'platform-users', 'audit'],
  _ => ['exports', 'activities', 'orders'],
};

const primaryIcons = [
  Icons.home_outlined,
  Icons.work_outline_rounded,
  Icons.map_outlined,
  Icons.task_alt_rounded,
  Icons.person_outline_rounded,
];

List<Map<String, dynamic>> visibleRecordActions(
  Map<String, dynamic> module,
  Map<String, dynamic> row,
) => (module['actions'] as List? ?? []).cast<Map<String, dynamic>>().where((a) {
  final key = module['key'], action = a['key'];
  if (key == 'documents') {
    if (action == 'approve') return row['can_approve'] == true;
    if (action == 'reject') return row['can_review'] == true;
    if (action == 'submit') return row['can_submit'] == true;
    if (action == 'download') {
      return (row['versions'] as List? ?? []).isNotEmpty;
    }
    if (action == 'upload') {
      return ['borrador', 'correcciones', 'rechazado'].contains(row['status']);
    }
  }
  if (key == 'approvals' && ['approve', 'reject'].contains(action)) {
    return row['status'] == 'pendiente';
  }
  if (key == 'orders' && action == 'confirm') return row['can_confirm'] == true;
  return true;
}).toList();
