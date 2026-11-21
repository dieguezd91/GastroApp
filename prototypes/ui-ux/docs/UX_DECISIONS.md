# Registro de Decisiones UX — GastroApp

Resumen de las principales decisiones de diseño, arquitectura de información y patrones web aplicados en el prototipo.

---

## 1. Consolidación de navegación sin perder contratos funcionales
- **Decisión:** agrupar módulos íntimamente relacionados en vistas con pestañas (`Productos + Categorías`, `Stock + Movimientos + Conteo físico`, `Facturas + Proveedores`) en lugar de 13 enlaces planos en el menú lateral.
- **Por qué:** reduce la carga cognitiva del Administrador y acorta los saltos en el recorrido de diagnóstico → acción (Prioridad 3: ver alerta de stock → ajustar → consultar historial o conteo en el mismo espacio).
- **Respeto de contratos:** conserva todos los flujos y reglas del backend (`feat/stock-movements`), incluyendo M12 (historial de ventas + anulaciones/devoluciones) y M15 (libro de stock + conteo en 3 pasos).

## 2. Prioridad 1 — POS orientado a mostrador y tablets táctiles
- **Split-view desde `48rem` (`768px` de contenedor):** tanto en desktop `1440px` como en tablet `1024px`, el catálogo y el carrito conviven lado a lado para cobrar sin hacer scroll vertical.
- **Bloqueo preventivo de stock en catálogo y carrito (mejora propuesta sobre el POS actual):** los productos sin stock disponible por receta quedan marcados con `aria-disabled="true"` y no permiten agregarse al carrito (explicando qué ingrediente falta). Además, el cálculo descuenta en tiempo real el stock ya reservado por el carrito actual, bloqueando superar el máximo disponible tanto desde las tarjetas como desde `+` o el campo numérico de cantidad, manteniendo la validación atómica al cobrar como segunda línea de defensa.
- **Descuentos y observaciones sin ensuciar el carrito:** los controles secundarios por línea (`Observación`, `Descuento de línea`) se abren en un diálogo nativo liviano, manteniendo las filas del carrito legibles y rápidas de tocar.
- **Checkout guiado con pagos mixtos y billetes rápidos:** permite cobrar en 1 clic con un único medio o sumar medios únicos hasta saldar `Restante = $ 0`, con atajos de billetes argentinos (`Exacto`, `$10.000`, `$20.000`, `$50.000`) y cálculo en vivo de `Vuelto`.

## 3. Prioridad 2 — Caja diaria y cierre con arqueo verificable
- **Separación visual de tareas:** la sesión abierta muestra en primer plano la franja de KPIs (`Apertura`, `Efectivo ingresado`, `Esperado en caja`, `Cobros netos`) y divide en dos columnas `Movimiento manual` y `Arqueo y cierre`.
- **Protección contra errores de cierre:**
  - Diferencia en vivo (`Exacto` / `Sobrante` / `Faltante`) con motivo obligatorio si difiere.
  - Manejo explícito del caso de movimientos concurrentes (`Saldo esperado desactualizado` → `Actualizar saldo esperado`).
  - Confirmación en dos pasos (`Revisar cierre` → modal `<dialog>` con `autofocus` en `Volver a editar` y confirmación explícita cuando el conteo es `$ 0`).

## 4. Prioridad 3 — Diagnóstico accionable en productos, costos e inventario
- **Panel "Requiere tu atención" en Dashboard:** sintetiza alertas de stock agotado/bajo mínimo, recetas con variación `>= 30%` y productos con margen `< 30%`, llevando al Administrador directo a la acción correctiva.
- **Conexión visible entre receta y producto:** en `#catalog` se advierte cuando el costo guardado del producto quedó desfasado respecto al último cálculo de receta y se ofrece sincronizarlo en un clic (visibilizando además el contrato actual de coincidencia por nombre exacto).
- **Unidades a prueba de errores (*poka-yoke*) en Recetas y Facturas:** la unidad nunca ofrece categorías incompatibles (imposible asignar `ml` a un insumo en `kg`). Si el insumo es `unidad`, queda fijo sin selector; si es peso o volumen, muestra un control segmentado de 2 opciones compatibles (`gr`/`kg` o `ml`/`lt`, preseleccionando `gr`/`ml` en recetas para evitar cálculos mentales de `0,018 kg`), acompañado de una franja de vista previa en vivo (`Equivale a 0,018 kg · Costo estimado: $ 648`) para detectar errores de ceros antes de confirmar.

## 5. Patrones seleccionados de Modern Web Guidance (Google Chrome)
- **Diálogos nativos (`dialog`, `prevent-page-scroll-under-modal-dialog`, `light-dismiss-a-dialog`):** `<dialog>` + `showModal()`, `overscroll-behavior: contain` en `dialog:modal` y `dialog::backdrop` (`overflow: hidden`) en lugar de bloquear scroll en `body`, reset de `dialog.returnValue = ''` y fallback de light-dismiss para navegadores sin `closedby`.
- **Validación post-interacción (`forms`, `validate-input-after-interaction`, `accessible-error-announcement`):** uso de `:is(:user-invalid, .user-invalid-fallback)` y `:has()` para no mostrar errores prematuros al cargar la página, sincronizando `aria-invalid` y `aria-describedby` dinámicamente.
- **Tablas adaptativas (`responsive-table`):** `container-type: inline-size` con transformación a tarjetas compactas de 2 columnas en contenedores estrechos (`< 30rem`) manteniendo headers semánticos, filas tabulares limpias en columnas desktop de ancho medio y accesibilidad por teclado (`tabindex="0" role="region"`).
- **Drawer táctil nativo (`navigation-drawer`):** `<dialog>` modal con `scroll-snap-type: x mandatory`, `100svh` e `IntersectionObserver` para gestos táctiles y retorno automático de foco.
- **Toasts no intrusivos (`persistent-toast-notifications`):** `[popover="manual"]` en esquina inferior derecha con botón explícito de cierre, pausa por foco, supresión cuando hay un modal abierto y respaldo en live region `polite`.

## 6. Hallazgos corregidos tras la validación en navegador (1440 / 1024 / 390)
1. **Overflow en POS móvil (`390px`) y tablet (`1024px`):** corregido con `minmax(0, 1fr)` en `.app-shell` y `.pos-layout`, `min-inline-size: 0` en hijos de grid/tarjetas y breakpoint de sidebar desktop en `72rem` (`1152px`).
2. **Toast en Top Layer tapando barra superior:** reposicionado explícitamente con `position: fixed; inset-block-end / inset-inline-end` y reemplazo limpio de toast previo.
3. **Mensaje de error en campo Contraseña (Login):** resuelto mediante `.field:has(:user-invalid) > .field__error` para atravesar el wrapper `.password-wrap`.
4. **Cálculo en vivo en pagos mixtos:** actualizado sobre evento `input` sin perder el foco del campo numérico.

## 7. Refinamientos tras revisión UX (ronda 2)
1. **Cobro mixto sincronizado y seguro (Crítica):** el botón `Confirmar cobro` permanece deshabilitado mientras `Restante != $ 0`, exista un importe `<= 0` o `Efectivo recibido < importe aplicado`. Se sincronizan `Asignado`, `Restante`, `Vuelto` y el atajo en 1 clic `Completar ($X)` en vivo sin destruir el foco al tipear.
2. **Tabla de Productos sin desbordamiento (Alta):** consolidación de 7 a 5 columnas (`Producto` con aviso/botón compacto de sincronización de receta, `Categoría`, `Precio / Costo` apilados, `Margen`, `Acciones`), logrando ajuste completo sin recorte horizontal en `1440px` y `1024px`.
3. **Barra demo compacta en POS móvil (Alta):** colapsada a una única fila (`~45px`) en `< 60rem` con botón `Opciones` (`aria-expanded`) para desplegar selector de escenario y reinicio solo a demanda; en desktop (`>= 60rem`) el botón `Opciones` se oculta y los controles permanecen en una sola línea.
4. **Tarjetas compactas en Inventario móvil (Alta):** la vista apilada usa grilla de métricas en 2 columnas (`< 30rem`) para comparar stock actual, mínimo, estado y cobertura de varios insumos en pantalla.
5. **Workspaces embebidos en lugar de modales extensos (Media):** Recetas, Facturas de compra y Devoluciones pasan a paneles de ancho completo dentro de cada vista (`← Volver`), eliminando el desplazamiento interno en `<dialog>`.
6. **Jerarquía operativa en 3 niveles en Dashboard (Media):** Hero principal de caja + métricas clave arriba; lista compacta `Requiere atención` + `Últimas ventas del turno` en el nivel medio; franja discreta de accesos secundarios al pie.
7. **Nota discreta de funcionalidad propuesta (Media):** `.proposal-note` de una línea compacta en Reportes y Configuración para priorizar KPIs y gráficos.
