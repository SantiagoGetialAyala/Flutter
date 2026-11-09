# Modelo de negocio de AgroPremium

AgroPremium es un software de gestión para empresas que exportan café y cacao. Cada exportación reúne comprador, origen de la mercancía, documentos, transporte y resultado financiero en un expediente compartido con permisos por función.

## Cliente, valor e ingresos

| Elemento | Propuesta |
| --- | --- |
| Quién contrata | La empresa exportadora o cooperativa que coordina la venta internacional. |
| Quién participa | Administrador de la exportadora, productores, transportadores e importadores. |
| Problema | Información dispersa, responsabilidades confusas, faltantes documentales y poca visibilidad del envío y sus costos. |
| Valor | Un expediente por exportación, trazabilidad del origen, tareas según función, acceso limitado por empresa y seguimiento de entrega. |
| Ingreso propuesto | Suscripción por empresa, con planes según volumen de exportaciones y almacenamiento. Incorporación y capacitación como servicio adicional opcional. |
| Costos del servicio | Infraestructura, archivos privados, copias de seguridad, soporte, desarrollo y capacitación. |
| Canales propuestos | Venta directa a exportadoras y cooperativas, demostraciones y alianzas sectoriales. |
| Indicadores | Empresas activas, exportaciones completadas, tiempo de preparación documental, entregas a tiempo y renovación de suscripciones. |

La suscripción es una propuesta comercial. El sistema actual no incluye cobro de suscripciones ni procesamiento bancario. Los ingresos y costos registrados en una exportación pertenecen a la operación de la empresa cliente; son distintos de los ingresos del proveedor del software. Los precios requieren validación comercial.

## Cuatro roles, una persona encargada

| Rol | Trabajo principal |
| --- | --- |
| Administrador | Invita al equipo; registra importadores, exportaciones y pedidos; reserva lotes; carga y verifica documentos; aprueba despacho; asigna transporte; registra costos, ingresos y pagos; cierra la operación. |
| Productor | Registra su perfil, fincas, parcelas, cosechas, lotes y soportes de origen. |
| Transportador | Consulta sus cargas asignadas y registra recogida, salida y entrega con evidencias. |
| Importador | Consulta sus pedidos y documentos compartidos; confirma recepción y reporta problemas. |

El administrador es la persona encargada de la empresa. Puede invitar a otro administrador para compartir el trabajo. Ya no se invita por separado a coordinación, comercial, documental, financiero ni gerencia. Las cuentas y membresías existentes de esos perfiles se convierten en Administrador; se conservan sus operaciones, archivos e historial. La migración registra los cambios de membresía en auditoría. Superadministración es una función técnica de plataforma y no aparece en las invitaciones de la empresa.

El administrador puede cargar y verificar el mismo documento. Se conservan los controles de archivo, vencimiento, checklist y evaluación conforme, junto con el autor de cada acción. El productor registra los lotes; el administrador registra los pedidos; el transportador entrega y el importador confirma recepción.

## Recorrido necesario para exportar

1. El administrador invita al productor, transportador e importador.
2. El productor registra finca, cosecha y lote. La cosecha vincula el lote con su parcela en el mapa.
3. El administrador registra importador y exportación, reserva lotes y crea el pedido.
4. El administrador carga y verifica documentos, requisitos y evaluación de cumplimiento; después aprueba despacho.
5. El administrador asigna el transporte. El transportador registra recogida, salida y entrega con evidencias.
6. El administrador actualiza la llegada y entrega. El importador confirma recepción.
7. El administrador registra costos, ingresos y pagos, revisa los pendientes y cierra la exportación.

La [guía completa de prueba](prueba-exportacion-completa.md) incluye cada botón, los cuatro accesos de laboratorio, valores de ejemplo y archivos para cargar.

## Cómo dar acceso a un productor

1. El administrador abre **Invitar personas**, escribe el correo y elige **Productor**.
2. Avisa a la persona que ya puede registrarse con ese correo.
3. La persona abre **Crear cuenta**, completa sus datos y contraseña usando el correo invitado. La empresa y la función se obtienen de la invitación vigente; no hay selector de rol ni campo de código.
4. Al crear la cuenta entra directamente a su empresa. Si ya tenía cuenta, inicia sesión y pulsa **Aceptar invitación** en Inicio.
5. Dentro de la empresa abre **Perfil de productor** y registra sus datos; después crea la finca con sus parcelas desde **Fincas y parcelas**, y continúa con cosechas y lotes.

Si el administrador ya creó la ficha del productor, debe vincularla a la cuenta correspondiente. La ficha comercial de un productor y su cuenta de acceso son registros distintos. Para el importador también hay que vincular su cuenta a la ficha de cliente para que consulte sus exportaciones.

## Qué coordenadas aparecen

El mapa muestra las coordenadas guardadas de **fincas**, **parcelas de origen** y **eventos de trazabilidad**. Cada ubicación identifica su finca, parcela o evento junto a latitud y longitud. La ficha muestra todos los vértices cuando existe un polígono. En el mapa de una exportación solo aparece el origen relacionado con sus lotes reservados.

Al registrar la finca se eligen departamento y municipio, y se marca el terreno en un mapa OpenStreetMap. Sus parcelas se crean en el mismo formulario. Latitud y longitud quedan como alternativa manual para quien ya tenga un GPS. También se pueden registrar límites de parcelas mediante GeoJSON como opción avanzada. El [recorrido de fincas y entregas](fincas-y-entregas.md) explica los campos y la asignación a logística.

Seleccionar un país o escribir el nombre de un puerto no aporta sus coordenadas. La vista actual presenta ubicaciones registradas y planificación logística; no obtiene la posición en vivo de vehículos.

## Interfaz principal

Cada función ve primero sus herramientas esenciales. **Más herramientas** permite acceder a funciones secundarias autorizadas. Inicio muestra la explicación de cada función y accesos a sus primeras herramientas: para el productor, perfil → finca → cosecha; para administración, invitaciones → equipo → operaciones. Las funciones adicionales se conservan para operaciones que las necesiten.

El catálogo inicial se amplió de siete a los 27 países de la UE, tomando como referencia la [lista oficial de países de la Unión Europea](https://european-union.europa.eu/principles-countries-history/eu-countries_en). La migración actualiza el catálogo conservando los identificadores y relaciones existentes. Los requisitos documentales siguen siendo configurados por la empresa según su operación.
