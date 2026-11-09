# Estado de la implementación

> Roles actuales: Administrador, Productor, Transportador e Importador. Las referencias históricas a perfiles separados de oficina se consolidaron en Administrador. Consulta [Roles actuales](roles-y-flujos.md) y la [guía de prueba](prueba-exportacion-completa.md).


Se completaron los módulos de roles, permisos y flujos empresariales descritos en [Roles y flujos de negocio](roles-y-flujos.md). Ese documento reemplaza el diagnóstico anterior que marcaba documentos, logística y finanzas como fases futuras.

La entrega incorpora permisos por acción y objeto, membresías e invitaciones, dashboards por perfil, documentos privados con versiones y revisión, requisitos que bloquean aprobación, transporte asignado con evidencias, costos y pagos con conversiones, pedidos y recepciones, notificaciones, auditoría y administración de plataforma.

Las migraciones locales se aplicaron a PostgreSQL. El laboratorio tiene una organización separada y una cuenta por rol, sin reasignar registros comerciales antiguos. Las pruebas verifican permisos y flujos tanto en SQLite aislado como en PostgreSQL; Flutter verifica navegación, formularios y compilación web.

Las integraciones externas y los formatos de entrega están delimitados en el documento funcional: invitaciones por código, reportes JSON, tasas de cambio manuales con fuente y reglas documentales configuradas por la empresa. La comprobación de servicios cubre API/base de datos.
