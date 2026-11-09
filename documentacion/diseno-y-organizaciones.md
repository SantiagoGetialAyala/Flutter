# Diseño y funcionamiento de las organizaciones

> Roles actuales: Administrador, Productor, Transportador e Importador. Las referencias históricas a perfiles separados de oficina se consolidaron en Administrador. Consulta [Roles actuales](roles-y-flujos.md) y la [guía de prueba](prueba-exportacion-completa.md).


## Diseño aplicado

La referencia se utiliza como dirección visual, manteniendo la marca RiTech: verdes de bosque, tonos crema, bordes suaves, iconos discretos y fotografía de café/cacao.

- Inicio: saludo, organización activa, indicador principal, tarjetas compactas y accesos rápidos.
- Móvil: navegación inferior con módulos prioritarios del rol y una sección Más para el resto.
- Escritorio: menú lateral agrupado en operación, origen, organización y plataforma.
- Exportaciones: tarjetas con estado, país, fechas y progreso basado en la etapa real. Ficha con pestañas Resumen, Seguimiento, Lotes y Documentos.
- Documentos: estados y vigencia visibles, filtros y resumen de los registros de la vista.
- Finanzas: ingresos, costos, margen, presupuesto y gráfico por moneda de reporte. Las monedas no se mezclan.
- Acceso: fotografía local de origen; no depende de una imagen remota.

Las capturas de `output/design/` son renderizados de Flutter con datos de prueba. No representan estadísticas reales de la empresa. Se generan mediante:

```bash
cd frontend
flutter test test/design_preview_test.dart --dart-define=CAPTURE_DESIGN=true
```

## Quién crea las empresas y las cuentas

La plataforma es multiempresa. Una cuenta puede pertenecer a varias organizaciones y tener un rol diferente en cada una. Iniciar sesión identifica a la persona; elegir una organización determina el equipo y los datos que puede consultar.

**Alta asistida:** el superadministrador entra a Administración de plataforma → Empresas → Nueva empresa. Registra nombre, NIT y correo del primer administrador. Se crea una invitación de administrador válida durante siete días. El código se muestra al finalizar y puede recuperarse desde el detalle de la empresa mientras siga pendiente y vigente. Se comparte manualmente con su destinatario; no hay envío automático de correo.

El destinatario crea su cuenta individual o inicia sesión con el correo invitado y acepta el código. Desde ese momento administra esa empresa y puede invitar empleados, productores, responsables documentales, transportadores, financieros o clientes. Cada persona acepta su propia invitación. El administrador no puede conceder superadministración.

**Alta propia:** se mantiene la posibilidad existente de que un perfil global comercial o administrador registre su empresa. El sistema lo vincula como administrador de esa nueva organización. Esto permite el registro directo además del alta asistida por la plataforma.

Los formularios de cuentas globales de superadministración permiten crear o suspender usuarios, pero crear una cuenta individual no la convierte automáticamente en miembro de una empresa.

## Por qué aparecía una sola organización

Las nueve cuentas empresariales del laboratorio están vinculadas a una sola empresa de demostración. Por eso cada una lista una empresa. El selector solo muestra membresías autorizadas; no expone otras empresas a personas sin acceso.

Para acceder a otra organización hay que crearla por el flujo autorizado o aceptar una invitación de su administrador. Las pruebas verifican que la misma persona puede cambiar de empresa y de rol sin mezclar datos.

El superadministrador inicia en el panel global, puede listar todas las empresas y entra excepcionalmente en una de ellas con una justificación auditada. Al recargar sin esa justificación vuelve al contexto de plataforma. Se corrigió la creación de empresas para reconocer el rol de plataforma aunque no tenga la marca interna de superusuario de Django.

## Recurso gráfico

Archivo final: `frontend/assets/images/origin-hero.jpg`.

Se utilizó la herramienta integrada de generación de imágenes. Prompt final:

> Use case: photorealistic-natural. Asset type: background photograph for a premium coffee and cacao export management app login. A real Colombian coffee plantation on softly misty green mountains in golden early morning sunlight. Foreground in the lower half: lush glossy coffee leaves, ripe red coffee cherries, a natural opened cacao pod and a few rich brown coffee beans, editorial premium agricultural photography, elegant restrained composition, deep forest greens, warm soft cream light and natural cocoa browns. Portrait 2:3 composition also usable with landscape crop. Leave upper middle mountains softly uncluttered for a white wordmark overlay implemented separately in the app. No text, no logos, no UI, no people, no watermark. Photographic, sophisticated and believable, avoid illustration.
