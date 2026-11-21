# GastroApp — Prototipo Interactivo UI/UX

Prototipo web navegable e independiente para evaluar la futura experiencia de usuario de **GastroApp** antes de trasladarla a la aplicación principal en Blazor Server.

**No modifica archivos de producción ni requiere conexión a backend ni cambios en `data.json`.**

---

## Cómo ejecutarlo localmente

Desde la raíz del repositorio (`GastroApp/`), levantar cualquier servidor HTTP estático (requerido porque el prototipo utiliza ES Modules nativos):

### Opción A — Python 3 (sin instalar nada)

```bash
python -m http.server 4173 --bind 127.0.0.1 -d prototypes/ui-ux
```

### Opción B — Node.js

```bash
npx serve prototypes/ui-ux -l 4173
```

Luego abrir en el navegador:

```text
http://127.0.0.1:4173
```

---

## Cómo evaluar los flujos

La barra superior (**Controles de demostración**) permite probar sin backend:

1. **Rol demo:** alternar entre `Administrador` (Camila Ríos) y `Empleado` (Lucas Méndez) para verificar navegación, permisos y la pantalla de acceso denegado.
2. **Escenarios rápidos:**
   - `Operación normal (Caja abierta)`
   - `Caja cerrada (bloqueo POS)`
   - `Stock crítico / Agotado`
   - `Arqueo desactualizado` (simula movimientos concurrentes durante el arqueo en `/cash`)
   - `Estado vacío`
   - `Simular carga`
3. **Ver Login / Reiniciar demo:** probar validación de inicio de sesión o restaurar los datos ficticios de *Bistró Sur — Café & Cocina*.

---

## Qué es existente, qué es propuesta y qué es supuesto

Verificado directamente sobre el código fuente actual de la rama `feat/stock-movements` (`Pages/`, `Services/`, `Models/` y `Docs/Architecture/`):

### 1. Funcionalidades implementadas en el código actual
- Autenticación con roles `Admin` y `Employee`, aislamiento por circuito y guarda `/unauthorized`.
- Dashboard contextual según estado de caja y rol.
- **POS (`/sales`)**: filtros por categoría (`Todos`, categorías, `Sin categoría`), búsqueda, carrito, observaciones por línea, descuentos de línea y generales (`None`/`Percentage`/`Fixed`), 6 medios de pago + pagos mixtos, efectivo recibido + vuelto, validación de caja abierta y descuento atómico de stock por receta.
- **Caja diaria (`/cash`) y Historial de cajas (`/cash/history`)**: apertura, movimientos manuales auditados (`Ingreso`, `Gasto`, `Retiro`), arqueo obligatorio por denominación con detección de movimientos concurrentes, cobros registrados por medio de pago con estado de completitud y cierre con `DailySummary`.
- **Historial completo de ventas (`/sales/history`, M12)**: filtros, detalle, línea cronológica de eventos, anulación con reposición de stock y devoluciones parciales/totales (`Vuelve a stock` / `Merma`).
- **Resumen del día (`/summary`)**: ventas brutas, descuentos, anulaciones, devoluciones y neto diario.
- **Productos y categorías (`/products`, `/product-categories`)**: margen `(precio - costo) / precio * 100` con umbrales visuales, estado activo/inactivo y bloqueo al eliminar categorías en uso.
- **Ingredientes, movimientos históricos y conteo físico (`/ingredients`, `/ingredients/{id}/movements`, `/stock/count`, M15)**: alertas con cobertura a 7 días (`Agotado` / `Bajo mínimo`), ajustes auditados, mermas con `WasteCategory`, libro histórico append-only y conteo físico en 3 pasos.
- **Recetas y costos (`/recipes`)**: conversión de unidades compatibles (`kg↔gr`, `lt↔ml`, `unidad`), costeo por última factura e indicador de variación relativa (`<10%`, `10–30%`, `>=30%`).
- **Proveedores y facturas (`/suppliers`, `/invoices`)**: alta de proveedores (solo nombre) y carga de facturas con ingreso automático de stock y actualización de último precio.

### 2. Propuestas de evolución (no implementadas aún — identificadas en UI con badge `Propuesta`)
- **Reportes y rentabilidad (`#reports`, M20):** análisis multidía (7/30 días), facturación vs costo teórico y rentabilidad por categoría.
- **Configuración del negocio y usuarios (`#settings`, M01 / M18 / M21):** perfil comercial/fiscal, umbral configurable de margen, tope de descuento y visualización de usuarios existentes (`UserService` existe en backend pero aún no tiene pantalla Razor).
- **Mejoras UX propuestas dentro de módulos existentes:** comprobante visual inmediato post-cobro (M13 futuro), botón "Sincronizar costo de receta → producto" y aviso preventivo de disponibilidad en tarjetas del POS.

### 3. Supuestos de demostración del prototipo
- Todos los datos pertenecen a un negocio ficticio (*Bistró Sur — Café & Cocina*, moneda `ARS`, formato `es-AR`) almacenados exclusivamente en memoria del navegador.
- El selector de rol y escenarios de la barra superior existe únicamente para evaluación del prototipo y no forma parte del producto final.
- Se mantiene la restricción real del backend actual: el vínculo Producto ↔ Receta coincide por nombre exacto (`Product.Name == Recipe.Name`).

---

## Entregables incluidos

- **Sistema de diseño:** [docs/DESIGN_SYSTEM.md](./docs/DESIGN_SYSTEM.md)
- **Mapa de navegación por rol:** [docs/NAVIGATION_MAP.md](./docs/NAVIGATION_MAP.md)
- **Registro de decisiones UX:** [docs/UX_DECISIONS.md](./docs/UX_DECISIONS.md)
- **Capturas validadas en navegador (`1440px`, `1024px`, `390px`):** carpeta [`screenshots/`](./screenshots/):
  - `01-dashboard-admin-1440.png` — Panel operativo Administrador (1440px)
  - `02-pos-employee-1440.png` — POS Empleado en vista dividida + toast accesible (1440px)
  - `03-pos-checkout-1440.png` — Diálogo nativo de cobro con pago mixto y vuelto (1440px)
  - `04-cash-arqueo-1440.png` — Caja diaria, movimientos manuales y arqueo por denominación (1440px)
  - `05-catalog-1440.png` — Productos, alertas de margen bajo y desfasaje de receta (1440px)
  - `06-inventory-1440.png` — Ingredientes y tabla de alertas con cobertura a 7 días (1440px)
  - `07-reports-proposal-1440.png` — Propuesta de Reportes y rentabilidad M20 (1440px)
  - `08-login-1440.png` — Login con validación accesible post-interacción (1440px)
  - `09-pos-tablet-1024.png` — POS táctil en Tablet (1024px) sin overflow
  - `10-pos-mobile-390.png` — POS en Mobile (390px) con barra fija de carrito
  - `11-inventory-mobile-390.png` — Tabla apilada responsiva por `@container` en Mobile (390px)
  - `12-recipes-multi-ingredient-1440.png` — Modal de receta multi-ingrediente con vista previa de costos en vivo
  - `13-invoice-multi-item-1440.png` — Modal de factura multi-ítem con impacto en stock y total en vivo
  - `14-refund-multi-line-1440.png` — Modal de devolución parcial/total multi-línea y multi-medio de pago
