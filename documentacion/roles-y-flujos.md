# Roles, permisos y flujos de negocio

La interfaz principal obtiene su panel, módulos, formularios y acciones desde `GET /api/workspace/`. El rol efectivo procede de la membresía de la organización seleccionada, no del perfil global que se eligió al registrarse. Cambiar de empresa vuelve a cargar los permisos. Las autorizaciones se comprueban también en el servidor en cada petición.

## Probar todos los perfiles

Las migraciones y el laboratorio ya fueron aplicados en la base PostgreSQL local durante esta entrega. Las cuentas del laboratorio y sus contraseñas aleatorias están en `backend/.demo-credentials.txt`, un archivo local excluido del control de versiones. Hay una cuenta por cada identificador:

`superadmin`, `administrador`, `productor`, `exportaciones`, `documental`, `logistica`, `financiero`, `importador`, y los perfiles compatibles `comercial` y `gerencia`.

Los correos siguen el formato `productor@roles.ritech.test`. Cierra sesión e inicia con otro correo para probar su experiencia. Todas las cuentas empresariales pertenecen a **Laboratorio de roles RiTech**. Superadministración inicia en el panel de plataforma.

Para reproducir el laboratorio en una instalación nueva:

```bash
cd backend
python3 manage.py migrate
python3 manage.py seed_role_demo
```

El comando solo crea las cuentas que faltan; no cambia contraseñas existentes. Los datos del laboratorio tienen una organización propia. Los registros antiguos sin organización se conservan, pero ya no se exponen como catálogo compartido. Para usarlos hay que asignar explícitamente su organización mediante Django o una migración de datos revisada.

## Funciones por rol

| Rol | Panel y operaciones disponibles | Límite de acceso |
| --- | --- | --- |
| Superadministrador | Organizaciones, cuentas activas/suspendidas/desactivadas, roles, matriz de permisos, funcionalidades, catálogos comunes, estadísticas agregadas, incidentes técnicos, auditoría y comprobación de API/base de datos. | El acceso empresarial exige seleccionar empresa, justificar el acceso excepcional y queda auditado; es de consulta. |
| Administrador empresarial | Información y parámetros de empresa, invitaciones, asignación/revocación de roles del equipo, clientes, proveedores, supervisión de exportaciones, documentos, transporte, aprobaciones e indicadores financieros. | Solo su organización; no puede asignar superadministración ni editar cuentas globales. |
| Productor | Perfil propio, fincas, cultivos, parcelas y GeoJSON, cosechas, cantidades/unidades, lotes, características de café/cacao, inventario y transformaciones, certificados, archivos/fotografías de origen, trazabilidad, observaciones y entregas relacionadas. | Solo productores vinculados a su cuenta y recursos derivados. No accede a finanzas ni al expediente comercial. |
| Coordinador de exportaciones | Clientes/importadores, proveedores, productos, creación de exportaciones, lotes y reservas, destinos, Incoterms, condiciones, fechas previstas/reales, asignación de responsables y transportadores, cronograma, historial, documentos, incidencias y solicitudes de aprobación. | Su organización; no aprueba expedientes regulatorios con el rol predeterminado. Comercial conserva estas funciones de coordinación. |
| Responsable documental | Expedientes, carga/clasificación, versiones, emisión/vencimiento, revisión, correcciones, aprobación/rechazo, requisitos por destino, checklist, trazabilidad, evaluaciones e informes documentales. | No valida sus propios archivos ni accede a finanzas. Bloquea la aprobación cuando el expediente está incompleto. |
| Logística/transportador | Transportes asignados, vehículos y conductores propios, guías, recogida, inicio de trayecto, seguimiento, incidencias, fotografías/documentos de evidencia y entrega con fecha real. | Solo cargas asignadas. No modifica exportaciones, contratos ni información financiera. |
| Financiero | Costos, seguros y gastos por categoría; ingresos; presupuestos; cotizaciones de proveedores; monedas y tasas de cambio con fuente; cobros, pagos y saldos; rentabilidad y variaciones por operación. | No altera origen ni aprueba documentos regulatorios. Los reportes separan las monedas de reporte. |
| Cliente/importador | Pedidos, productos/lotes adquiridos dentro de su exportación, fechas y estados de envío, documentos aprobados compartidos, descargas, recepción e incidencias, notificaciones e historial. | Solo exportaciones vinculadas a su ficha de cliente. No ve documentos internos, versiones sustituidas ni datos de otros compradores. |
| Gerencia | Consulta empresarial, reportes y decisiones de aprobación empresarial. | Sin edición de origen, documentos, transporte o finanzas. |

## Recorrido de una operación

1. **Equipo:** el administrador crea una invitación con correo y rol. Comparte manualmente el código mostrado en el detalle. La persona se registra o inicia sesión con ese correo y usa **Aceptar invitación**. La invitación vence a los siete días y solo se acepta una vez. En **Equipo y roles** se cambia el rol o se desactiva la membresía. Las cuentas vinculadas de productores y clientes se seleccionan desde el directorio de su empresa.
2. **Origen:** el administrador vincula una cuenta productora a un productor, o el productor crea su perfil propio. Este registra finca, cultivo, parcela, cosecha y lote. El inventario no permite saldos negativos. Las reservas se crean desde **Reservas de lotes**; las liberaciones se generan al cancelar la exportación, evitando liberaciones manuales repetidas.
3. **Operación comercial:** el coordinador crea el cliente y vincula su cuenta importadora; crea exportación, reserva lotes, registra pedido y programa actividades. El detalle de la exportación ofrece historial y cambio de estado. Asigna un responsable empresarial activo y un transporte a una cuenta logística.
4. **Documentos:** se crea la ficha, se carga el archivo con **Cargar nueva versión** y se envía a revisión. Los archivos admitidos incluyen PDF, imágenes y documentos de oficina hasta 10 MB. Se guardan privadamente con versión, hash SHA-256 y autor. Otro usuario documental aprueba, rechaza o pide correcciones. Cargar una versión nueva devuelve el documento a borrador e invalida su verificación anterior.
5. **Cumplimiento:** configura requisitos obligatorios para todos los destinos o para un país concreto; verifica cada elemento del checklist y registra una evaluación conforme. Para pasar de `en_revision` a `aprobada_despacho`, cada requisito debe tener un documento aprobado con archivo y vigencia válida, una verificación positiva y una evaluación conforme. Sin requisitos configurados tampoco se aprueba. Los requisitos demo son ejemplos; el contenido normativo lo define la organización.
6. **Transporte:** el transportador registra su vehículo/conductor y guía. En **Seguimiento y evidencias** registra `recogida → inicio → entrega`, adjuntando un documento con archivo de esa exportación. El servidor exige el orden y conserva fechas/evidencias. Los eventos de incidencia crean una incidencia operativa. El coordinador actualiza los estados logísticos de la exportación; el transportador no tiene permiso para editar el expediente comercial.
7. **Finanzas:** registra presupuesto, costos e ingresos. Para convertir entre monedas, selecciona una tasa con moneda de origen, moneda de destino, fecha y fuente. Se conserva el importe convertido del movimiento. `Importe pagado` deriva estado pendiente/parcial/pagado y nunca puede superar el importe. **Reporte** muestra costos, ingresos, margen, porcentaje, variación presupuestaria y pagos pendientes por exportación y moneda.
8. **Entrega:** una vez la exportación está arribada, entregada o cerrada, el cliente confirma la recepción del pedido una sola vez y puede reportar incidencias de su operación. Ve únicamente documentos aprobados que el exportador haya marcado como compartidos.

## Permisos y funcionalidades

`backend/users/access.py` centraliza las acciones `view`, `create`, `update`, `delete`, `submit`, `approve`, `reject`, `assign`, `upload`, `download`, `export` y `manage`. La plataforma puede consultar la matriz efectiva y registrar excepciones por rol/módulo/acción en **Matriz de permisos**. Una excepción con `Permitido` desactivado revoca la acción. Los límites de empresa, propiedad, asignación y transiciones siguen siendo obligatorios aunque se conceda una acción adicional.

En **Configuración y funcionalidades**, una clave como `module.finance` con `Habilitado` desactivado oculta el módulo y bloquea sus peticiones empresariales. Las claves de parámetros generales almacenan su valor para consulta/gestión; no se interpretan como código.

Los registros de trazabilidad no se eliminan físicamente por API. Se archivan/desactivan cuando el modelo lo permite. Auditoría registra cambios, revisiones, descargas, asignaciones, decisiones y accesos excepcionales. Los intentos de login fallidos generan eventos de seguridad.

## Validación y límites de esta entrega

La suite cubre aislamiento entre organizaciones, productores, clientes y transportadores; bloqueo de permisos; invitaciones; versiones privadas; revisión documental; cumplimiento; stock; estados; conversiones/pagos; recepción y aprobaciones. Flutter tiene pruebas de navegación, visibilidad por rol, creación y edición.

Las invitaciones se entregan por código, sin envío automático de correo. Los reportes se consultan en pantalla y se descargan en JSON. El estado de servicios comprueba la API y la conexión a base de datos, sin afirmar disponibilidad de integraciones externas. No se incluyen integraciones bancarias, tasas automáticas, validación legal externa, antivirus ni firma electrónica. El selector de archivos se integró para web y plataformas Flutter compatibles; la verificación realizada cubre compilación web y pruebas de widgets, no una sesión manual de navegador ni dispositivos físicos.
