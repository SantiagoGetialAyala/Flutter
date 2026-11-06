# AgroPremium: navegación centrada en el trabajo

## Diagnóstico y decisiones

La barra anterior enumeraba los recursos del backend y reunía documentación, transporte, finanzas y ventas bajo «Operación». Abrir una exportación mostraba solo resumen, historial, lotes y documentos, mientras sus costos, requisitos, transporte y tareas exigían volver a otras listas. Los formularios mostraban muchos campos opcionales y el inicio podía mostrar más de cinco indicadores sin enlaces.

La navegación ahora tiene cinco destinos en móvil y escritorio: Inicio, Trabajo, Mapa, Tareas y Perfil. Trabajo cambia con la membresía activa: Producción, Operaciones, Revisiones, Mis envíos, Finanzas, Pedidos o Empresas. Superadministración usa Estado en lugar de Mapa. Los perfiles compatibles comercial y gerencia conservan su acceso real.

«Gestión y catálogos», accesible desde Perfil y la búsqueda del encabezado, conserva todas las herramientas autorizadas. Tiene búsqueda y grupos desplegables. No se eliminaron modelos, endpoints ni permisos. La interfaz consume los descriptores de `/api/workspace/`; no determina permisos usando únicamente el rol global del usuario.

## Inicio y tareas

El inicio limita los indicadores a una tarjeta principal y cuatro secundarias. Los indicadores enlazan a módulos permitidos; los accesos rápidos se adaptan al trabajo del rol. Los pendientes, las alertas de vencimiento y los registros recientes permiten abrir su trabajo correspondiente.

`pending_tasks` en `/api/workspace/` se deriva de documentos, actividades asignadas, transportes asignados, pagos, aprobaciones de terceros, pedidos por recibir y operaciones con transiciones autorizadas. Cada fuente se restringe por empresa, propiedad y acciones disponibles. La bandeja muestra hasta 40 pendientes, priorizando vencidos, y permite búsqueda, filtro de vencidas y actualización. No introduce otro modelo de tareas: las delegaciones y solicitudes usan las actividades existentes.

La respuesta también incluye las membresías activas (`contexts`). El selector de empresa muestra el rol de cada contexto y vuelve a consultar los permisos al cambiar. El modelo actual admite un rol por persona y empresa; no se simulan roles adicionales ni se unen permisos de empresas distintas.

## Expediente y ciclo de vida

El expediente conserva tres pestañas principales: Resumen, Expediente y Seguimiento. Las secciones del expediente reúnen reservas de lotes, requisitos del destino, documentos y versiones, checklist, cumplimiento, transporte, costos autorizados, cotizaciones, actividades, solicitudes, incidencias y pedidos. Solo aparecen secciones y acciones permitidas. Los registros nuevos reciben la exportación automáticamente y no permiten cambiarla desde ese formulario.

El plan de trabajo tiene cinco etapas:

1. Datos comerciales y destino: crear un borrador con los campos básicos y completar los detalles opcionales después.
2. Productos y lotes: reservar lotes del inventario dentro del expediente.
3. Preparación documental: reunir soportes, delegar solicitudes, verificar requisitos y registrar cumplimiento.
4. Coordinación logística: programar transportes, asignar responsables y registrar eventos con evidencias.
5. Seguimiento y cierre: consultar historial y mapa y avanzar por los estados autorizados.

No es un asistente que fuerce a una persona a completar todo. El borrador se guarda mediante el endpoint existente y abre el expediente para continuar o salir. Las actividades admiten responsables y fechas. Los campos opcionales se despliegan progresivamente. Las búsquedas, estados y páginas de cada herramienta se conservan durante la sesión; se descartan al cambiar de empresa.

`allowed_transitions` en la representación de una exportación describe cambios posibles por rol y estado. Las validaciones reales de cumplimiento, propiedad, evidencias y permisos siguen ejecutándose en Django al realizar una acción. Los indicios de transición no garantizan que estén satisfechos todos los requisitos documentales.

## Mapa: datos y límites

La vista geográfica dibuja las geometrías GeoJSON guardadas en parcelas y las ubicaciones de los eventos de trazabilidad. Permite ampliar, seleccionar registros y consultar coordenadas en un panel de detalle. Los trayectos logísticos muestran origen, destino, fechas previstas y estado, separados de la cronología de eventos registrados.

`GET /api/exports/{id}/map/` reúne únicamente parcelas ligadas a los lotes de ese expediente y recursos autorizados por los permisos existentes. También respeta la propiedad de la exportación: un importador no recibe parcelas ni eventos internos sin el permiso correspondiente.

No se geocodifican nombres de ciudades, no se generan posiciones GPS ni se dibujan rutas a partir de texto. Si faltan coordenadas, aparece un estado vacío. La vista usa una cuadrícula geográfica propia, sin proveedor externo de mapas base, GPS o cálculo de rutas. Los puntos de un evento son ubicaciones registradas, no una posición actual del transportador.

## Validación

Pruebas Django: propiedad y aislamiento de tareas, membresías activas, filtros de expediente, geografía ligada a los lotes, ocultación de recursos sin permisos y transiciones revocadas, además de los flujos de negocio existentes.

Pruebas Flutter: cinco destinos para ocho roles en teléfono pequeño, creación y validación de borradores, reserva con la exportación fijada, navegación de escritorio y móvil, recuperación de filtros, permisos del mapa y separación de monedas en finanzas.

Las comprobaciones locales de lectura con PostgreSQL y JWT recorren las ocho cuentas del laboratorio sin modificar registros empresariales. La suite aislada usa `config.test_settings`; la aplicación conserva PostgreSQL y JWT en su configuración habitual.

No se requieren migraciones ni nuevas dependencias. Para actualizar una sesión Flutter en ejecución, realizar un hot restart (`R`); Django debe ejecutar el código actualizado para exponer tareas, contextos, mapa y transiciones.
