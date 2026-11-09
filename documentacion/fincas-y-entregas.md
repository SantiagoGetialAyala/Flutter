# Registro de origen y asignación de entregas

## Finca y parcelas, en un solo formulario

En **Producción → Fincas y parcelas → Nueva finca** se completan tres partes:

1. **Tamaño:** unidad (hectáreas o km²), superficie total y nombre. El productor se selecciona automáticamente cuando la cuenta solo tiene un perfil. El código interno se genera al guardar.
2. **Ubicación:** departamento y municipio de Colombia. El catálogo local DIVIPOLA del DANE filtra los municipios por departamento. **Elegir ubicación en OpenStreetMap** abre un mapa con esos mismos selectores: puedes cambiar departamento y municipio allí para acercar la vista automáticamente, tocar el terreno y confirmar **Usar esta ubicación**. También están disponibles al ubicar una parcela independiente o al editarla; si tiene una finca seleccionada, parte de su departamento y municipio. Elegir un municipio solo centra la vista; no registra sus coordenadas como si fueran las de la finca.
3. **Cultivo:** café o cacao. Si no se divide el terreno, se crea una sola parcela llamada **Área principal**, con el área completa y el punto de referencia de la finca. Si solo se cultiva una parte, activa la división y registra el área realmente cultivada. La suma de parcelas puede ser menor que la superficie total, pero no superarla.

**Dividir en varias parcelas** es opcional. Permite registrar nombres, áreas en hectáreas, cultivo y, opcionalmente, un punto propio para cada zona. Sin punto propio, la parcela usa explícitamente la ubicación de la finca como referencia; no se dibujan límites inventados. Un km² equivale a 100 hectáreas.

Al editar una finca se consultan y editan sus parcelas desde el mismo formulario. Para dividir una parcela ya registrada, primero reduce su superficie y luego agrega las demás. Las cosechas y lotes existentes conservan sus relaciones; no se eliminan parcelas.

La parcela sigue existiendo como registro para enlazar cosecha y terreno, pero ya no es un trámite separado al crear la finca. El recorrido queda: **perfil del productor → finca con sus parcelas → cosecha → lote**. El registro independiente de cultivos queda como herramienta secundaria para quien necesite más detalle.

Las coordenadas manuales están plegadas como opción para quien ya tenga un GPS. Latitud significa posición norte/sur (−90 a 90); longitud, este/oeste (−180 a 180). Se usan grados decimales WGS84 y punto decimal. Marcar un punto identifica una ubicación de referencia: no certifica ni delimita el predio. Los límites mediante GeoJSON siguen disponibles como opción avanzada al editar parcelas.

La finca y sus nuevas parcelas se guardan en una transacción: si una parcela es inválida, no queda una finca incompleta. El servidor comprueba permisos, propiedad, coordenadas y suma de superficies, incluida la conversión desde km².

## Quién asigna una entrega

1. El **administrador de la empresa** invita a la persona que transportará la carga con el rol **Transportador**. Esa persona debe aceptar la invitación.
2. El **administrador** abre el expediente y elige **Programar transporte**.
3. Selecciona el **Transportador responsable** entre las cuentas activas de Logística, y completa recogida, lugar de entrega y fecha prevista. También puede hacerlo administración, según sus permisos.
4. Al guardar, la carga queda vinculada a esa cuenta. El sistema crea una notificación y la carga aparece en **Mis envíos** y en las tareas del transportador asignado.
5. El transportador registra vehículo, conductor y guía cuando corresponda; después registra **recogida → inicio → entrega** con documentos de evidencia. Solo puede actuar sobre sus cargas asignadas.
6. El importador consulta su envío y confirma la recepción del pedido cuando la exportación está arribada, entregada o cerrada. La entrega del transportador y la recepción del comprador son confirmaciones distintas.

Crear una finca o un lote no programa automáticamente un transporte. El administrador debe reservar los lotes de la exportación y programar la recogida.

## Fuentes y conexión

Los 1122 registros territoriales del selector proceden del [catálogo DIVIPOLA del DANE](https://www.datos.gov.co/Mapas-Nacionales/DIVIPOLA-C-digos-municipios/gdxc-w37w), descargado el 6 de noviembre de 2026; la fuente indica corte de diciembre de 2024. El catálogo se incluye en la aplicación y las coordenadas de los municipios solo se usan para centrar el mapa.

El mapa carga teselas de OpenStreetMap por HTTPS e incluye atribución visible y enlace de licencia conforme a su [política de uso](https://operations.osmfoundation.org/policies/tiles/). El proveedor se puede cambiar al compilar con `--dart-define=OSM_TILE_URL=...`. El mapa requiere conexión; los campos manuales permiten introducir una ubicación GPS si falla la cartografía. No se solicita geolocalización del dispositivo ni se hacen búsquedas automáticas en Nominatim.
