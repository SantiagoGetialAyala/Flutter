# Probar una exportación de principio a fin

Solo hay cuatro roles: **Administrador, Productor, Transportador e Importador**. El administrador es la persona encargada de invitar y gestionar toda la exportación.

El recorrido es **preparar mercancía → crear pedido y exportación → aprobar documentos → transportar → confirmar recepción y cerrar**. Trabaja sobre una sola exportación: su pestaña **Expediente** reúne los formularios de esa operación.

## 1. Encender el proyecto

Desde la carpeta del proyecto, en una terminal:

```bash
cd backend
source .venv/bin/activate
python manage.py migrate
python manage.py seed_role_demo
python manage.py runserver 127.0.0.1:8000
```

En otra terminal:

```bash
cd frontend
flutter pub get
flutter run -d chrome --web-port=8080 --dart-define=API_BASE_URL=http://127.0.0.1:8000/api
```

PostgreSQL debe estar iniciado con la conexión configurada en `backend/.env`. Abre `http://localhost:8080`.

El laboratorio crea una empresa separada y cuentas para todos los roles. Abre **`backend/.demo-credentials.txt` en tu editor** para consultar las contraseñas; no están en esta guía. El comando conserva las contraseñas de las cuentas existentes.

| Para hacer esto | Cuenta de laboratorio |
| --- | --- |
| Invitar al equipo, gestionar exportaciones, documentos y pagos | `administrador@roles.ritech.test` |
| Registrar finca, cosecha y lote | `productor@roles.ritech.test` |
| Registrar recogida, salida y entrega | `logistica@roles.ritech.test` |
| Confirmar recepción | `importador@roles.ritech.test` |

Cierra sesión para cambiar de cuenta. Selecciona **Laboratorio de roles RiTech** si aparece el selector de empresa. No necesitas usar superadministración para esta prueba.

Cada cambio de estado pide una justificación. En esta simulación puedes escribir **Avance de prueba** y confirmar. Los nombres de estado que aparecen a continuación son los de los botones de la aplicación.

## 2. Preparar la mercancía — Productor

1. Inicia sesión como **productor**. El laboratorio ya tiene el perfil **Productor demo**; no crees otro.
2. Abre **Producción → Fincas y parcelas → Nueva finca**.
3. Registra **Finca prueba**, **2 hectáreas**, departamento **Antioquia**, municipio **Medellín** y cultivo **Café**.
4. Pulsa **Elegir ubicación en OpenStreetMap**. Dentro del mapa también puedes seleccionar departamento y municipio. La vista se acerca automáticamente; toca el terreno de prueba y confirma **Usar esta ubicación**. Como alternativa, abre **Ingresar coordenadas manualmente** y usa latitud `6.25`, longitud `-75.58` para esta simulación.
5. Deja desactivada la división de parcelas y guarda. Se crea **Área principal** con el área y la ubicación de referencia de la finca. No tienes que registrar un cultivo o una parcela en otro módulo.
6. Abre **Cosechas → Registrar cosecha**. Selecciona **Área principal** de **Finca prueba**, fecha actual, producto **Café**, cantidad **1000**, unidad **kg**. Guarda.
7. Abre **Lotes → Nuevo lote**. Código **PRUEBA-LOTE-001**, productor **Productor demo**, producto **Café**, cantidad inicial **1000**, unidad **kg**. Selecciona la cosecha anterior y guarda. Los demás atributos pueden quedar vacíos.

**Comprueba:** el lote tiene 1000 kg disponibles. La relación lote → cosecha → parcela permite mostrar el origen en el mapa de la exportación.

## 3. Crear la venta — Administrador

1. Cierra sesión y entra como **administrador**.
2. Abre **Operaciones → Nueva exportación**. Código **PRUEBA-EXP-001**, importador **Importadora demo**, destino **Alemania** y moneda **EUR**. Puedes completar fechas previstas. Guarda el borrador.
3. Si estás usando una empresa propia y falta el comprador, pulsa **Crear aquí: Clientes e importadores**. Completa razón social, correo, teléfono, dirección y país. Vincula la cuenta con función **Importador** para que después pueda consultar y confirmar su pedido. Al guardar vuelves al borrador.
4. Dentro de la exportación, pulsa **Preparar productos y lotes**, o abre **Expediente → 1. Pedido y mercancía**.
5. En **Productos y lotes reservados → Reservar lote**, selecciona **PRUEBA-LOTE-001**, cantidad **100**, unidad **kg**. La exportación ya está seleccionada.
6. En **Pedido del comprador y recepción → Nuevo pedido**, registra referencia **PRUEBA-PED-001**, descripción **100 kg de café**, cantidad **100**, unidad **kg**. Guarda.
7. Abre **2. Documentos y aprobación → Documentos y versiones → Nuevo documento**. Título **Origen prueba**, tipo de documento **`origen`**. En los detalles opcionales activa **Compartir con cliente**. Guarda.
8. En ese documento pulsa **Cargar nueva versión** y selecciona [origen-prueba.pdf](archivos-prueba/origen-prueba.pdf). Después pulsa **Enviar a revisión**.
9. En **Actualizar estado de la operación**, selecciona **Documentación pendiente** y confirma.

**Comprueba:** el lote conserva 900 kg disponibles, la reserva es de 100 kg y el pedido corresponde a esta exportación. En **Seguimiento → Mapa y puntos logísticos** debe aparecer la parcela vinculada. El documento queda pendiente de revisión.

## 4. Aprobar el expediente — Administrador

1. Continúa como **administrador**, abre **Exportaciones → PRUEBA-EXP-001 → Expediente**.
2. En **Requisitos del destino** consulta los requisitos aplicables. El laboratorio ya incluye **Certificado de origen demo**, tipo `origen`, obligatorio. Para esta prueba basta ese requisito; no crees otro duplicado. En una empresa nueva pulsa **Nuevo requisito**, nombre **Certificado de origen**, tipo **`origen`**, destino **Alemania**, **Obligatorio** y **Activo** habilitados.
3. En **Actualizar estado de la operación**, pasa a **En revisión**.
4. En **Documentos y versiones**, abre **Origen prueba** y pulsa **Aprobar**. El administrador puede verificar el archivo que él mismo cargó. Su decisión queda registrada con usuario, fecha y observaciones; no necesitas otra cuenta para esta revisión.
5. En **Verificación de requisitos → Verificar requisito**, elige **Certificado de origen demo** —o el requisito creado en tu empresa— y activa **Verificado**. Guarda. Si aparecen más requisitos obligatorios, verifica cada uno con su documento correspondiente.
6. En **Resultado de cumplimiento → Registrar revisión**, elige **Conforme** y escribe **Expediente verificado para la prueba**. Guarda.
7. En **Actualizar estado de la operación**, selecciona **Aprobada** —corresponde a la aprobación para despacho—.

**Comprueba:** el documento está aprobado y la exportación está aprobada para despacho. Si faltan archivos, requisitos, vigencias, verificación o evaluación conforme, el servidor explica el faltante y bloquea la aprobación. El PDF incluido es una muestra para probar el software; no acredita una exportación real.

## 5. Asignar el envío — Administrador

1. Continúa como **administrador** y abre la misma exportación.
2. En **Expediente → 3. Transporte y entrega → Transporte y responsables → Programar transporte**, selecciona la cuenta **Transportador** del laboratorio.
3. Lugar de recogida **Finca prueba**, entrega **Hamburgo**, fecha de recogida actual y fecha prevista de entrega posterior. Guarda. Vehículo y conductor pueden completarse después; el laboratorio ya incluye ambos.
4. En **Actualizar estado de la operación**, selecciona **Preparando envío**.

**Comprueba:** el transportador recibe la asignación en **Mis envíos**. No crees manualmente una tarea adicional para asignar el transporte.

## 6. Registrar el recorrido — Transportador y administrador

Entra como **transportador** y abre el transporte asignado. Puedes editarlo para seleccionar vehículo **DEMO-001**, **Conductor demo** y una guía de prueba.

Para cada avance usa **Registrar avance**. Si lo abres desde la bandeja de tareas, se propone el siguiente evento permitido. Selecciona fecha/hora y un documento de evidencia de esta misma exportación que ya tenga un archivo cargado.

| Orden | Evento | Soporte de ejemplo | Resultado del transporte |
| --- | --- | --- | --- |
| 1 | Recogida | [recogida-prueba.pdf](archivos-prueba/recogida-prueba.pdf) | Recogido |
| 2 | Inicio del trayecto | [salida-prueba.pdf](archivos-prueba/salida-prueba.pdf) | En tránsito |
| 3 | Entrega | [entrega-prueba.pdf](archivos-prueba/entrega-prueba.pdf) | Entregado |

Para cargar un soporte: en **Documentos → Nuevo documento**, vincula **PRUEBA-EXP-001**, escribe un título —por ejemplo **Recogida prueba**— y tipo **`evidencia`**; guarda y pulsa **Cargar nueva versión**. Regresa a **Registrar avance** y selecciona ese documento. También puedes crearlo con **Crear aquí** desde el selector de evidencia; después vuelve a Documentos para cargar su archivo antes de guardar el evento.

Registra las fechas en orden cronológico. Entre avances, el administrador puede actualizar el estado de la exportación según lo ocurrido:

**Preparando envío → En transporte → Embarcada → En tránsito → En destino → Entregada.**

Los eventos del transportador actualizan su transporte. El estado general de la exportación se cambia desde **Actualizar estado de la operación**, con la cuenta de **administrador**. Para una simulación puedes completar los eventos y después recorrer esos estados en orden; en una operación real se registran cuando ocurren.

**Comprueba:** el transporte tiene recogida y entrega reales, los eventos conservan sus archivos y la exportación llega a **Entregada**.

## 7. Confirmar la recepción — Importador

1. Entra como **importador**.
2. Abre **Pedidos** y localiza **PRUEBA-PED-001**.
3. Pulsa **Confirmar recepción**, escribe **Recibido completo** y confirma. Está disponible cuando la exportación está arribada, entregada o cerrada.
4. Consulta el documento **Origen prueba**, que fue aprobado y marcado como compartido.

**Comprueba:** la recepción queda registrada una sola vez. El importador consulta sus propios pedidos; no crea pedidos ni ve soportes internos.

## 8. Registrar pagos y cerrar — Administrador

Entra como **administrador**. En **Finanzas → Registrar costo o ingreso**, registra estos movimientos vinculados a **PRUEBA-EXP-001**:

| Campo | Venta | Transporte |
| --- | --- | --- |
| Tipo de registro | Ingreso | Costo |
| Categoría | Venta | Logística |
| Descripción | Venta prueba | Flete prueba |
| Importe | 2500 | 300 |
| Moneda | EUR | EUR |
| Moneda de reporte | EUR | EUR |
| Importe pagado | 2500 | 300 |

Guarda cada registro. Al usar EUR en ambos casos no necesitas crear una tasa de cambio. Abre **Exportaciones → PRUEBA-EXP-001 → Expediente → 4. Pagos y cierre** para ver el reporte de esa exportación: ingreso **2500 EUR**, costo **300 EUR**, margen **2200 EUR** y los dos movimientos pagados. Ese reporte utiliza solamente esta operación; la pantalla general de Finanzas reúne las operaciones de la empresa.

Como **administrador**, abre **PRUEBA-EXP-001**, comprueba recepción, entrega y pagos, y usa **Actualizar estado de la operación → Completada** —estado interno `cerrada`—.

**Resultado final:** exportación cerrada, pedido recibido, transporte entregado, documentos aprobados y movimientos financieros consultables. El historial conserva los cambios. La comprobación de recepción y pagos antes del cierre es una revisión del administrador; la transición de cierre actual no los concilia automáticamente.

## Crear tu propia empresa y cuentas, en vez de usar el laboratorio

Esta preparación se hace una vez:

1. Desde **Crear cuenta** pulsa **Quiero registrar mi empresa**. Completa nombre de empresa, NIT opcional, tus datos, correo y contraseña. No hay selector de rol.
2. Pulsa **Crear empresa y cuenta**. La empresa y su cuenta administradora se crean juntas; entras directamente a la empresa.
3. Desde **Invitar personas**, crea una invitación por participante: **Productor**, **Transportador** e **Importador**. Puedes invitar a otro **Administrador** si necesitas ayuda. Usa correos distintos para probar cada función.
4. Cada persona abre **Crear cuenta**, completa nombre, apellido, el mismo correo invitado y su contraseña. El servidor encuentra la invitación vigente de ese correo y aplica su empresa y rol automáticamente. No elige rol ni escribe código. Si ya tenía cuenta, inicia sesión y pulsa **Aceptar invitación** con el código que puede consultar el administrador.
5. El productor crea su **Perfil de productor**; queda vinculado a su cuenta. Después registra finca, cosecha y lote como en el paso 2.
6. El administrador crea el cliente/importador y selecciona su **Cuenta vinculada**. Si la ficha del productor ya existía, administración debe vincularla también a su cuenta desde **Perfil de productor → Editar**.
7. El administrador configura al menos un requisito obligatorio para el destino. Para la simulación usa tipo `origen` y nombre **Certificado de origen**.
8. Continúa desde el paso 3 de esta guía con el importador y el productor de tu empresa.

El administrador avisa a la persona que ya puede crear su cuenta con el correo invitado; el programa no envía correos automáticamente. El código queda como alternativa para vincular una cuenta que ya existía. La cuenta de acceso y la ficha de productor o importador son registros distintos: la vinculación permite mostrar a cada persona sus datos.

## Qué puedes omitir en la primera prueba

No necesitas crear productos de catálogo, cultivos independientes, proveedores, cotizaciones, mezclas, movimientos manuales de inventario, tareas adicionales ni aprobaciones empresariales. La finca crea su parcela principal, la reserva descuenta el inventario y la asignación del transporte avisa al transportador. Usa **Opciones adicionales** o **Más herramientas** cuando la operación los necesite.

Si repites la prueba, cambia los códigos del lote, pedido y exportación —por ejemplo el sufijo `002`—. Si aparece un faltante, abre el formulario indicado en **Crear aquí** o vuelve con el rol responsable. Si el mapa queda vacío, comprueba la cadena **reserva → lote → cosecha → parcela con coordenadas**.
