# Matriz de alcance de lanzamiento

**Decisión de producto (2026-11-22):** GastroApp sale al mercado apto para cualquier tipo de emprendimiento gastronómico desde la primera versión, aunque eso retrase el lanzamiento.
**Criterio:** amplitud con profundidad mínima. Cada modalidad recibe lo necesario para operar un día completo; lo que no impide operar a ningún rubro queda postergado.
**Documento base:** [GastroApp_Documento_Diseno_Producto.docx](../Architecture/GastroApp_Documento_Diseno_Producto.docx) (módulos M01–M24).

## Leyenda

| Símbolo | Significado |
|---|---|
| ● | Completo: profundidad descrita en el documento de diseño, salvo lo marcado como postergado |
| ◐ | Mínimo: subconjunto definido en la sección 3 |
| — | No aplica a la modalidad |
| ⏸ | Postergado para después del lanzamiento |

Modalidades:

- **Mostrador:** cafetería, kiosco, rotisería, comida para llevar.
- **Salón:** restaurante, bar, cervecería con mozos.
- **Retiro / Delivery:** pedidos para retirar o enviar, propios o telefónicos.
- **Producción:** panadería, pastelería, elaboración anticipada y encargos.

El **estado actual** surge de `IMPLEMENTED_FEATURES.md` y el código al 2026-11-22. Es orientativo; el código manda.

## 1. Prerrequisitos de plataforma

Se resuelven antes de construir módulos que usan varios dispositivos a la vez (salón, cocina, delivery). Construir esos módulos sobre la base actual obliga a reescribirlos.

| ID | Prerrequisito | Motivo | Estado actual |
|---|---|---|---|
| P1 | Base de datos en reemplazo de `data.json` | Concurrencia entre dispositivos, transacciones, respaldo | JSON temporal de prueba |
| P2 | Identidad de negocio y sucursal en todos los datos | Producto comercial multi-cliente; la multi-sucursal se posterga pero el modelo la contempla desde el inicio | No iniciado |
| P3 | Roles y permisos por operación | Mozo, cocina, cajero, encargado y dueño ven y hacen cosas distintas | Solo `Admin` y `Employee` |
| P4 | Sesión que sobrevive a reconexiones | En un celular la pantalla se bloquea y la conexión se corta; hoy la sesión vive en memoria por circuito y se pierde al reconectar | Se pierde al recargar o reconectar |
| P5 | Pedidos, cuentas y carritos guardados en el servidor | Ningún dispositivo puede perder una ronda o un carrito por cortarse | Carrito en memoria del circuito |
| P6 | Actualización en tiempo real entre dispositivos | El mozo envía y la cocina lo ve; la cocina marca listo y el mozo se entera | No iniciado |
| P7 | Cobro sin conexión en el punto de venta; el resto avisa y no pierde datos | Un punto de venta no puede dejar de vender si se corta internet (decisión D1) | Definido (D1), no iniciado |
| P8 | Impresión de tickets y comandas | Un local sin comandera ni ticket no opera | No iniciado |
| P9 | Facturación electrónica (ARCA) | Requisito para vender el producto en Argentina | No iniciado |
| P10 | Vínculo producto–receta por identificador estable | Exigido por M02 y M14; hoy un cambio de nombre rompe el descuento de stock | Vínculo por nombre |
| P11 | Facturas de compra con efecto trazable sobre el stock | Exigido por M16 y regla 9.4; hoy editar o borrar una factura no reconcilia stock | Sin reconciliación |
| P12 | Operaciones idempotentes con identificador generado en el dispositivo | Reintentos en redes móviles y sincronizaciones posteriores a un corte no deben duplicar ventas, cobros ni comandas (D1) | Parcial |

## 2. Matriz por módulo

| Módulo | Mostrador | Salón | Retiro / Delivery | Producción | Estado actual |
|---|---|---|---|---|---|
| M01 + M21 Configuración del negocio (fusionados) | ◐ | ◐ | ◐ | ◐ | No iniciado |
| M02 Catálogo, precios y disponibilidad | ● | ● | ● | ● | Parcial |
| M03 Punto de venta | ● | ◐ | ● | ● | Avanzado |
| M04 Medios de pago y cobro | ● | ● | ● | ● | Avanzado |
| M05 Descuentos y promociones | ◐ | ◐ | ◐ | ◐ | Parcial |
| M06 Pedidos y canales | ◐ | ● | ● | ◐ | No iniciado |
| M07 Mesas y salón | — | ◐ | — | — | No iniciado |
| M08 Comandas y pantalla de cocina/barra | ◐ | ● | ● | — | No iniciado |
| M09 Retiro y delivery | ◐ | — | ◐ | ◐ | No iniciado |
| M10 Reservas y lista de espera | — | ⏸ | — | — | No iniciado |
| M11 Caja | ● | ● | ● | ● | Avanzado |
| M12 Historial, anulaciones y devoluciones | ● | ● | ● | ● | Avanzado |
| M13 Comprobantes | ● | ● | ● | ● | No iniciado |
| M14 Recetas y costos | ● | ● | ● | ● | Parcial |
| M15 Ingredientes, stock y movimientos | ● | ● | ● | ● | Avanzado |
| M25 Producción y elaboración anticipada (nuevo) | ◐ | ◐ | ◐ | ● | No iniciado |
| M16 Proveedores y compras | ◐ | ◐ | ◐ | ◐ | Parcial |
| M17 Clientes | ◐ | ◐ | ◐ | ◐ | No iniciado |
| M18 Equipo y permisos | ● | ● | ● | ● | Parcial |
| M19 Notificaciones | ◐ | ◐ | ◐ | ◐ | Parcial (alertas de stock) |
| M20 Paneles e informes | ◐ | ◐ | ◐ | ◐ | Parcial (resumen diario) |
| M22 Sucursales, integraciones y continuidad | ◐ | ◐ | ◐ | ◐ | No iniciado |
| M23 Menú digital y autopedido | ◐ | ◐ | ◐ | ◐ | No iniciado |
| M24 Gastos del negocio | ◐ | ◐ | ◐ | ◐ | No iniciado |

## 3. Alcance mínimo de lanzamiento por módulo

**M01 + M21 Configuración del negocio.** Datos comerciales y fiscales, modalidades activables, medios de pago habilitados, comisión porcentual o fija por medio de pago y por canal de venta, parámetros de caja, asistente de puesta en marcha con lista de datos faltantes, importación de productos, ingredientes y proveedores desde planilla (CSV o Excel). Historial de cambios de configuración: postergado.

**M02 Catálogo.** Lo ya implementado más: variantes y agregados con precio y selecciones obligatorias, agotado en el momento, canales habilitados por producto, archivar en lugar de borrar, **actualización masiva de precios por porcentaje o categoría**. Precio distinto por canal solo para Retiro / Delivery. Promociones por horario y calendario de disponibilidad: postergados.

**M03 Punto de venta.** Lo implementado más: variantes y agregados, ventas suspendidas, prevención de doble confirmación, emisión de comprobante. En Salón el POS se usa para cobrar cuentas, no para cargar pedidos.

**M04 Medios de pago.** Lo implementado más: pagos parciales de una cuenta abierta (Salón) y distinción entre pago registrado manualmente y pago verificado. Integración directa con proveedores de pago: decisión abierta.

**M05 Descuentos.** Descuentos por línea y por total (implementados) con autorización por rol. Promociones automáticas, cupones y compatibilidades: postergados.

**M06 Pedidos.** Pedido con número, canal, responsable, estados (recibido, en preparación, listo, entregado, cancelado) separados del estado de cobro, tablero de pedidos activos, modificación con impacto visible en cocina. En Mostrador: aviso de "pedido listo" por número. En Producción: encargos con fecha y hora de retiro.

**M07 Mesas.** Plano simple por sector, estados de mesa, abrir cuenta con comensales y mozo, envío de rondas sin reenviar lo confirmado, traslado de cuenta, división por partes iguales o por producto, propina, cierre explícito. Unir mesas y división por importe libre: postergados.

**M08 Comandas.** Envío por área de preparación, impresión o pantalla, estados (recibido, en preparación, listo), tiempo transcurrido, cambios y cancelaciones destacados, sin importes visibles para cocina. Métricas de carga y tiempos: postergadas.

**M09 Retiro y delivery.** Retiro con hora estimada; delivery con dirección, costo de envío fijo o por zona simple, repartidor propio, estados de despacho, importe y medio de cobro en la entrega. Integración con aplicaciones de delivery: decisión abierta.

**M11 Caja.** Lo implementado más: varios puntos de cobro simultáneos y relevo de responsable sin cerrar la caja.

**M12 Historial.** Lo implementado más: comprobante de anulación o devolución y permisos finos por rol (P3).

**M13 Comprobantes.** Ticket operativo impreso, copia digital compartible, factura electrónica (P9), reimpresión marcada como copia, estado de emisión sin duplicar cobros.

**M14 Recetas.** Lo implementado más: vínculo por identificador (P10), subrecetas, merma de preparación, costo desconocido señalado, alerta cuando un aumento de insumo deja productos por debajo del margen objetivo. Comparación de versiones de receta: postergada.

**M15 Stock.** Lo implementado alcanza. Lotes, vencimientos, varios depósitos y stock comprometido: postergados.

**M25 Producción y elaboración anticipada (nuevo).** Orden de producción que consume ingredientes y genera stock de producto elaborado (medialunas, salsas, masas, viandas). Al vender un producto elaborado se descuenta su stock, no sus ingredientes, para no descontar dos veces. Completo en Producción; mínimo en el resto para preparaciones previas.

**M16 Compras.** Proveedores, factura de compra como recepción (sin orden de compra), historial de precios por proveedor, alerta de aumento de precio, corrección y anulación trazables (P11), **pedido de compra sugerido** a partir del stock mínimo y el consumo reciente, agrupado por proveedor habitual y exportable o compartible para enviarlo al proveedor. Órdenes de compra formales, recepciones parciales y cuentas por pagar: postergadas.

**M17 Clientes.** Venta anónima por defecto. Ficha mínima con nombre, teléfono y dirección para delivery y encargos. Historial de compras del cliente. Fidelización, saldo a favor y comunicaciones: postergados.

**M18 Equipo y permisos.** Roles dueño, encargado, cajero, mozo y cocina; permisos por operación; ingreso rápido por PIN; autorización de supervisor para descuentos, anulaciones y devoluciones; operador registrado en cada acción. Control horario: decisión abierta.

**M19 Notificaciones.** Avisos internos de stock bajo, pedidos demorados, diferencias de caja y anulaciones o descuentos fuera de lo habitual. Resumen de cierre diario enviado al dueño. Comunicaciones al cliente y configuración avanzada de destinatarios: postergadas.

**M20 Informes.** Ventas por período, producto, categoría, canal, medio de pago y empleado; ticket promedio; bruto, descuentos, anulaciones, devoluciones y neto; margen estimado y merma; **margen real por canal y por medio de pago**, descontando las comisiones configuradas; **ingeniería de menú** (popularidad contra margen); panel del dueño usable desde el celular; exportación a planilla. Tiempos de cocina, ocupación y comparativas avanzadas: postergados.

**M22 Sucursales, integraciones y continuidad.** Impresoras (P8), respaldo y recuperación visibles para el administrador, exportación de datos. Multi-sucursal como funcionalidad: postergada (el modelo la contempla por P2).

**M23 Menú digital.** Carta digital pública por QR, de solo lectura, con disponibilidad real. Autopedido, pago desde la carta y pedido de cuenta desde la mesa: postergados.

**M24 Gastos.** Registro simple de gastos por categoría y período para mostrar rentabilidad operativa separada del margen de receta. Devengado, vencimientos y obligaciones recurrentes: postergados.

## 4. Diferenciales comerciales

Capacidades que el dueño valora y paga porque le ahorran dinero, tiempo o riesgo. Todas forman parte del alcance de lanzamiento y se usan como argumentos de venta.

### Faltantes críticos que el documento de diseño subestimaba

| Capacidad | Por qué importa | Dónde queda |
|---|---|---|
| Facturación electrónica (ARCA) como núcleo | Sin factura electrónica el producto no se puede vender en Argentina; el documento la dejaba "según jurisdicción" | P9, M13 |
| Impresión de tickets y comandas desde el primer día | Un local sin comandera ni ticket no opera; el documento la ubicaba como ampliación | P8, M08, M13 |
| Producción por lotes | Panaderías y rotiserías elaboran antes de vender; el documento solo descuenta stock al vender | M25 |
| Pedido de compra sugerido | Con mínimos y consumo registrados, el sistema propone qué comprar y a qué proveedor | M16 |
| Importación inicial desde planilla | Cargar cientos de productos a mano es la principal barrera de entrada | M01 + M21 |

### Valor comercial

| Capacidad | Beneficio para el dueño | Dónde queda |
|---|---|---|
| Actualización masiva de precios | Ajusta precios por porcentaje o categoría en segundos, clave en contextos de inflación | M02 |
| Alerta de margen por aumento de insumos | Avisa cuando un aumento deja productos por debajo del margen objetivo ("subió la harina y 8 productos quedaron debajo del margen") | M14, M19 |
| Ingeniería de menú | Cruza popularidad y margen para decidir qué productos promover, revisar o retirar | M20 |
| Panel del dueño en el celular y resumen de cierre diario | El dueño sigue el negocio sin estar en el local | M19, M20 |
| Alertas antifraude | Avisa anulaciones, descuentos o diferencias de caja fuera de lo habitual por empleado | M19 |
| Margen real por canal y por medio de pago | Muestra cuánto queda después de las comisiones de cada aplicación de delivery y de cada medio de pago | M01 + M21, M20 |
| Sin inversión en hardware | El mozo usa su propio celular y la cocina cualquier dispositivo con navegador | Sección 5 |
| Cobro sin conexión | Si se corta internet, el local sigue cobrando | D1 |

## 5. Mozo con celular propio

Decisión: el mozo puede trabajar desde su propio celular usando la aplicación web, para que el dueño no tenga que invertir en tablets. Las tablets siguen siendo opcionales. Es un argumento de venta: **se empieza sin comprar hardware**.

Requisitos derivados:

- **Vista de mozo pensada para celular:** uso con una mano, botones grandes, mesas y carga de ronda en pocos toques. No es la vista de escritorio achicada.
- **Instalable desde el navegador** (aplicación web instalable), sin pasar por tiendas de aplicaciones.
- **Ingreso rápido por PIN** sobre una sesión del local, sin escribir usuario y contraseña en cada turno.
- **La sesión y la ronda en curso sobreviven** al bloqueo de pantalla, al cambio de aplicación y a cortes de señal (P4, P5).
- **Envío a cocina sin duplicados** aunque el mozo toque dos veces o la red reintente (P12).
- **Funciona con datos móviles o wifi débil**, con un estado de conexión visible y sin perder lo cargado (P7).
- **Exposición mínima de datos:** el mozo no ve costos, caja, reportes ni datos de clientes que no necesita.
- **Revocación por el dueño:** cerrar las sesiones de un empleado o de un dispositivo en cualquier momento, por ejemplo cuando alguien deja de trabajar en el local.
- **Cocina sin hardware dedicado:** pantalla de cocina en cualquier dispositivo con navegador, o comandera impresa.

## 6. Postergado para después del lanzamiento

Reservas y lista de espera; autopedido y pago desde la carta; promociones automáticas, cupones y fidelización; lotes, vencimientos y varios depósitos; órdenes de compra, recepciones parciales y cuentas por pagar; multi-sucursal como funcionalidad; comunicaciones al cliente; gastos con devengado y vencimientos; comparación de versiones de receta; métricas de tiempos de cocina y ocupación.

## 7. Orden sugerido de construcción

Fases internas de desarrollo, no lanzamientos al mercado.

| Fase | Contenido | Desbloquea |
|---|---|---|
| F0 Plataforma | P1–P5, P10–P12; toda operación nace con identificador generado en el dispositivo y clave contra duplicados (D1) | Todo lo multi-dispositivo y el cobro sin conexión |
| F1 Núcleo | M01+M21, M02, M03, M04, M05, M11, M12, M13 (con P8–P9), M14, M15, M16, M18 | Mostrador completo |
| F2 Pedidos y cocina | P6, P7 (punto de venta sin conexión y cola de rondas del mozo, D1), M06, M08 | Base común de Salón y Delivery |
| F3 Salón | M07, vista de mozo en celular | Restaurantes y bares |
| F4 Retiro y delivery | M09, M17 mínimo | Rotiserías y delivery propio |
| F5 Producción | M25 | Panaderías y pastelerías |
| F6 Gestión | M19, M20, M22, M23 mínimo, M24 mínimo | Valor para el dueño |
| F7 Pilotos | Dos o tres locales por modalidad usando el sistema en operación real | Lanzamiento |

## 8. Decisiones tomadas

### D1 Funcionamiento sin conexión acotado al cobro (2026-11-22)

**Decisión:** el punto de venta sigue cobrando sin internet; el resto de las áreas avisa la falta de conexión y no pierde datos. No se busca funcionamiento completo sin conexión en todos los módulos.

**Motivo:** los cortes de internet son habituales y un punto de venta que deja de cobrar en hora pico es motivo de rechazo del producto. El funcionamiento sin conexión completo (salón, cocina, stock, compras, reportes) multiplica conflictos de sincronización, numeración y stock, y retrasa el lanzamiento sin un beneficio proporcional.

| Área | Comportamiento sin internet |
|---|---|
| Punto de venta | Sigue vendiendo: carga la venta, cobra en efectivo o con terminal de tarjeta registrada como pago manual e imprime ticket. Guarda las operaciones en el dispositivo y las sincroniza al recuperar la conexión |
| Mozo (celular) | No pierde lo cargado: las rondas quedan en cola y se envían al recuperar la conexión, sin duplicarse |
| Cocina / barra | Avisa la falta de conexión; la operación continúa con comanda impresa desde la caja o aviso del mozo |
| Pagos que requieren internet (QR, transferencia verificada) | No disponibles; se avisa y se ofrecen efectivo o terminal de tarjeta |
| Factura electrónica | Ticket provisorio y emisión diferida al recuperar la conexión. Evaluar el mecanismo de contingencia de ARCA (CAEA) y su aplicabilidad a cada cliente |
| Stock | Se descuenta al sincronizar; un saldo negativo transitorio se muestra con advertencia |
| Administración e informes | Avisa la falta de conexión y espera a recuperarla |

**Consecuencias:**

- El punto de venta y la vista del mozo deben ejecutarse en el dispositivo e instalarse desde el navegador; no pueden depender de una conexión permanente con el servidor.
- Desde la fase F0, cada operación se crea con un identificador generado en el dispositivo y una clave contra duplicados (P12), para que la sincronización posterior no duplique ventas, cobros ni comandas.
- Las ventas sincronizadas después de un corte conservan su fecha y hora reales y quedan identificadas como registradas sin conexión.
- Argumento comercial: "si se corta internet, seguís cobrando".

## 9. Decisiones abiertas

1. Integración directa con proveedores de pago (por ejemplo QR o terminales) en el lanzamiento o después.
2. Integración con aplicaciones de delivery de terceros en el lanzamiento o después.
3. Control horario y fichaje del personal.
4. Modelo comercial: planes, qué módulos incluye cada uno y precio.
