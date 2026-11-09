import 'package:flutter/material.dart';

const lifecycleStages = [
  'Datos comerciales y destino',
  'Productos y lotes',
  'Preparación documental',
  'Transporte y entrega',
  'Seguimiento y cierre',
];

const lifecycleGuides = [
  'Administrador · registra el importador, destino, condiciones y fechas; guarda el borrador.',
  'Administrador · reserva los lotes del productor y registra el pedido del comprador.',
  'Administrador · configura requisitos, revisa archivos, verifica el checklist y aprueba el despacho.',
  'El administrador asigna el transporte. El transportador registra recogida, salida y entrega con evidencias.',
  'El administrador actualiza la llegada y entrega. El importador confirma recepción; el administrador registra pagos y cierra.',
];

String resourceOwner(String key) => switch (key) {
  'export-allocations' => 'Administrador reserva; productor registra el lote',
  'orders' => 'Importador o administrador registra; importador confirma recepción',
  'requirements' || 'checklist' || 'compliance' => 'Administrador',
  'documents' => 'Administrador carga (se aprueba directo) o verifica',
  'transports' => 'El administrador asigna; transportador entrega',
  'finance' || 'quotes' => 'Administrador',
  'approvals' => 'Administrador',
  _ => 'Equipo asignado',
};

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
    'El administrador verifica los requisitos y aprueba el despacho.',
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
  'bloqueada' => 'Revisa el motivo del bloqueo con el administrador.',
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
  'productor' => ['producers', 'farms', 'harvests', 'lots', 'documents'],
  'administrador' => ['exports', 'invitations', 'documents', 'finance'],
  'importador' => ['orders', 'exports', 'transports', 'documents'],
  'logistica' => ['transports', 'transport-events', 'documents'],
  'documental' => ['exports', 'documents', 'requirements'],
  'financiero' => ['finance', 'exports'],
  'exportaciones' ||
  'comercial' => ['exports', 'clients', 'documents', 'transports'],
  'superadmin' => ['platform-organizations', 'platform-users', 'audit'],
  _ => ['exports', 'activities', 'orders'],
};

List<String> essentialModules(String role) => switch (role) {
  'productor' => ['producers', 'farms', 'harvests', 'lots', 'documents'],
  'importador' => ['orders', 'exports', 'transports', 'documents', 'incidents'],
  'logistica' => [
    'transports',
    'transport-events',
    'vehicles',
    'drivers',
    'documents',
    'incidents',
  ],
  'documental' => ['exports', 'documents', 'requirements'],
  'financiero' => ['finance', 'exports'],
  'administrador' => [
    'exports',
    'invitations',
    'members',
    'producers',
    'clients',
    'documents',
    'requirements',
    'transports',
    'finance',
  ],
  'exportaciones' ||
  'comercial' => ['exports', 'clients', 'transports', 'documents'],
  _ => workModules(role),
};

String roleInstructions(String role) => switch (role) {
  'productor' =>
    'Registra tu perfil y luego tu finca: allí eliges su ubicación y organizas las parcelas. Después registra cosechas y lotes. El administrador reserva tus lotes y registra el pedido.',
  'importador' =>
    'Registra tus pedidos, consulta tu envío y documentos compartidos, y confirma la recepción cuando llegue la mercancía.',
  'logistica' =>
    'Abre tu transporte asignado y registra recogida, salida y entrega con sus evidencias.',
  'documental' =>
    'Configura requisitos del destino, revisa documentos y completa la verificación antes de aprobar el despacho.',
  'financiero' =>
    'Registra costos, ingresos y pagos de la exportación. Consulta el saldo y la rentabilidad.',
  'administrador' =>
    'Invita al productor, transportador e importador. Crea la exportación y el pedido, verifica documentos, asigna el transporte, registra pagos y cierra la operación.',
  'gerencia' =>
    'Consulta el avance de las exportaciones y los resultados. Atiende las aprobaciones empresariales que requieran tu decisión.',
  _ =>
    'Registra el importador, crea la exportación, reserva lotes y registra el pedido. Coordina documentos y transporte desde el expediente.',
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
