# Arquitectura

> Roles actuales: Administrador, Productor, Transportador e Importador. Las referencias históricas a perfiles separados de oficina se consolidaron en Administrador. Consulta [Roles actuales](roles-y-flujos.md) y la [guía de prueba](prueba-exportacion-completa.md).


- **Presentación:** Flutter. `features/workspace` construye navegación, paneles y formularios a partir de la membresía y permisos enviados por la API. No decide autorizaciones del servidor.
- **Identidad:** Django y JWT. `users` contiene cuentas globales, organizaciones, membresías, invitaciones, roles, excepciones de permisos y auditoría.
- **Autorización:** `users/access.py` centraliza módulo y acción. `business/scoping.py` añade límites por organización, productor, cliente y transportador. Las relaciones se validan al crear y editar.
- **Origen y expediciones:** `operations` contiene fincas, parcelas, cosechas, lotes, inventario transaccional, reservas, transformación, trazabilidad y estados de exportación.
- **Negocio:** `business` contiene documentos privados y versiones, requisitos/checklist/evaluaciones, logística, finanzas, cotizaciones, actividades, incidencias, aprobaciones, pedidos, notificaciones y configuración de plataforma.
- **Catálogos:** `catalog` contiene países comunes y productos/clientes de cada organización. Los datos antiguos sin organización permanecen almacenados y fuera de las consultas empresariales.
- **Datos:** PostgreSQL. Las actualizaciones de existencias y transiciones críticas usan transacciones y bloqueos de filas. Los importes usan decimales y las conversiones guardan su valor de reporte.
- **Archivos:** almacenamiento privado en `backend/private_media`; la descarga verifica sesión, acción y propiedad. Las versiones tienen número, autor y hash; no se publican rutas directas.

Consulta [Roles y flujos](roles-y-flujos.md) para la cobertura funcional, las cuentas de laboratorio y los límites de las integraciones.
