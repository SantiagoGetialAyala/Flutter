# Cuatro roles para exportar

El **Administrador** es la persona encargada de la empresa. Solo él invita al equipo, asigna funciones y gestiona exportaciones, documentos y pagos. Ya no hace falta buscar un rol de coordinación, comercial, documental, financiero o gerencia.

| Rol en Invitar personas | Qué hace | Qué consulta |
| --- | --- | --- |
| Administrador | Invita y vincula cuentas; registra importadores, exportaciones y pedidos; reserva lotes; verifica documentos; aprueba despacho; asigna transporte; registra ingresos, costos y pagos; cierra. | Los registros de su empresa. |
| Productor | Registra su perfil, fincas, parcelas, cosechas, lotes y soportes de origen. | Su origen y las entregas relacionadas. |
| Transportador | Atiende sus cargas; registra vehículo, conductor, recogida, salida y entrega con evidencias. | Solo los envíos asignados a su cuenta. |
| Importador | Consulta pedidos y archivos compartidos; confirma recepción y reporta problemas. | Solo sus compras y envíos. |

El identificador interno del Transportador continúa siendo `logistica` para conservar las asignaciones existentes. La cuenta técnica de plataforma se mantiene fuera de las invitaciones empresariales.

## Invitar a una persona

1. Entra como **Administrador** y abre **Invitar personas → Invitar persona**.
2. Escribe el correo y elige uno de los cuatro roles. La descripción debajo del selector explica su trabajo.
3. Comparte el código que muestra el sistema. La persona crea primero su cuenta normal con ese correo.
4. Después de iniciar sesión, usa **Aceptar invitación** y escribe el código. La empresa y el rol se asignan automáticamente; no selecciona rol.
5. Vincula la cuenta importadora a su ficha en **Clientes e importadores**. El productor puede crear su propio perfil; si ya existía, administración vincula su cuenta.

Puedes invitar a otro Administrador si necesitas compartir la gestión. Cada código vence a los siete días y solo se puede usar una vez.

## Recorrido de una exportación

1. **Productor:** finca con sus parcelas → cosecha → lote disponible.
2. **Importador:** solicita café o cacao, cantidad, país de destino y hasta tres documentos.
3. **Administrador:** abre la solicitud y pulsa **Crear exportación**. El expediente queda vinculado al importador y a su solicitud.
4. **Administrador:** reserva lotes del producto solicitado hasta completar la cantidad; carga hasta tres documentos solicitados en **Documentos y versiones** y completa requisitos del destino.
5. **Administrador:** asigna un transporte a una cuenta Transportador.
6. **Transportador:** consulta solo sus cargas asignadas y registra recogida → inicio → entrega con archivos de evidencia.
7. **Administrador:** actualiza los estados de la exportación hasta llegada y entrega.
8. **Importador:** confirma recepción del pedido.
9. **Administrador:** registra costos, ingresos y pagos; revisa pendientes y cierra.

La [guía de prueba completa](prueba-exportacion-completa.md) contiene botones, cuentas de laboratorio, datos de ejemplo y PDF para cargar.

## Controles que se conservan

El servidor comprueba empresa, propiedad, asignación, permisos y transiciones en cada petición. Solo el superadministrador crea empresas y genera el código inicial para su administrador. Una cuenta se crea con correo y contraseña; el código se canjea después para vincularla a la empresa y asignarle el rol. Cada código debe estar pendiente, vigente y asociado al correo de la cuenta. Productores, transportadores e importadores no invitan ni cambian funciones.

El Administrador puede verificar los documentos que él mismo cargó. Se registra quién subió y quién aprobó, junto con fecha y observaciones. El despacho sigue exigiendo archivos aprobados, vigentes, requisitos verificados y evaluación conforme. Una versión nueva devuelve el documento a borrador e invalida su verificación.

Los archivos son privados. El importador solo accede a documentos aprobados marcados como compartidos. El inventario no permite reservas superiores al disponible. Los eventos logísticos exigen orden, fechas y archivos de esa exportación. Los reportes separan monedas; el reporte del expediente solo incluye esa operación.

## Cuentas existentes

La migración `users.0007_four_business_roles` convierte los perfiles empresariales anteriores —Exportaciones, Comercial, Documental, Financiero y Gerencia— en Administrador. Conserva usuarios, contraseñas, membresías activas/inactivas, códigos de invitación, responsables, operaciones y archivos. Los cambios de membresía quedan auditados y los roles anteriores quedan inactivos como registros históricos.

Para nuevas invitaciones y cambios de función, tanto el selector como el servidor aceptan únicamente los cuatro roles. Los identificadores históricos permanecen en código para compatibilidad de datos; no son opciones para el equipo.

## Laboratorio

```bash
cd backend
python manage.py migrate
python manage.py seed_role_demo
```

Las cuatro cuentas empresariales son `administrador@roles.ritech.test`, `productor@roles.ritech.test`, `logistica@roles.ritech.test` e `importador@roles.ritech.test`. Sus contraseñas están en `backend/.demo-credentials.txt`, excluido de versiones. El comando no restablece contraseñas existentes.
