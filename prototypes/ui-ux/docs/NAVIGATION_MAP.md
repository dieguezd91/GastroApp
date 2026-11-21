# Mapa de Navegación por Rol — GastroApp

GastroApp cuenta estrictamente con **dos roles** (`Models/UserRole.cs`): **Administrador (`Admin`)** y **Empleado (`Employee`)**. No se agregan roles nuevos.

---

## 1. Arquitectura de navegación por rol

### Rol: Empleado (`Employee`)
Enfocado en velocidad de mostrador, mínima fricción y cero ruido administrativo.

```text
Login (#login)
 └── Operación diaria
      ├── Inicio (#dashboard)           [Contextual: estado de caja + métricas de turno + CTA directo al POS]
      └── Vender / POS (#pos)           [Prioridad 1: catálogo, búsqueda, carrito, descuentos, cobro y vuelto]
 └── Cuenta
      └── Cerrar sesión
```

- Si intenta acceder por URL directa a cualquier ruta de administración, el router presenta **Acceso denegado (`/unauthorized`)** con vuelta directa al POS o al Inicio (mismo contrato que `Pages/Unauthorized.razor`).

### Rol: Administrador (`Admin`)
Comparte el mismo POS y lenguaje visual, sumando supervisión de caja, ventas, catálogo, recetas, stock y compras.

```text
Login (#login)
 ├── Operación diaria
 │    ├── Panel operativo (#dashboard)          [Hero de caja + KPIs + panel "Requiere tu atención" + ventas recientes]
 │    └── Vender / POS (#pos)                   [Prioridad 1]
 ├── Caja y ventas
 │    ├── Caja diaria (#cash)                   [Prioridad 2: apertura, movimientos manuales, arqueo y cierre]
 │    ├── Historial de cajas (#cash-history)    [Solo lectura con detalle completo de sesiones y arqueos]
 │    ├── Historial de ventas (#sales-history)  [Filtros, detalle, eventos, anulación y devoluciones parciales/totales]
 │    └── Resumen del día (#summary)            [Cierre diario de ventas, descuentos, anulaciones y neto]
 ├── Catálogo e inventario
 │    ├── Productos y categorías (#catalog)     [Prioridad 3A: tabs Productos / Categorías, márgenes y sync de costo]
 │    ├── Ingredientes y stock (#inventory)     [Prioridad 3B: tabs Stock y alertas / Movimientos / Conteo físico]
 │    ├── Recetas y costos (#recipes)           [Prioridad 3C: costeo por última factura, variación y recálculo]
 │    └── Proveedores y facturas (#purchasing)  [Tabs Facturas / Proveedores con ingreso automático de stock]
 └── Evolución (Propuestas — marcadas en UI)
      ├── Reportes y rentabilidad (#reports)    [Propuesta M20 · No implementado]
      └── Configuración (#settings)             [Propuesta M01/M18/M21 · No implementado]
```

---

## 2. Correspondencia con rutas actuales de GastroApp (`feat/stock-movements`)

| Pantalla en prototipo | Ruta Blazor actual | Roles | Estado real en repositorio |
|---|---|---|---|
| `#login` | `/login` | Público | Implementado |
| `#dashboard` | `/` | Admin, Empleado | Implementado |
| `#pos` | `/sales` | Admin, Empleado | Implementado |
| `#cash` | `/cash` | Admin | Implementado |
| `#cash-history` | `/cash/history` | Admin | Implementado |
| `#sales-history` | `/sales/history` | Admin | Implementado (M12) |
| `#summary` | `/summary` | Admin | Implementado |
| `#catalog` (tabs) | `/products` + `/product-categories` | Admin | Implementado (unificado en 2 tabs) |
| `#inventory` (tabs) | `/ingredients` + `/ingredients/{id}/movements` + `/stock/count` | Admin | Implementado (M15, unificado en 3 tabs) |
| `#recipes` | `/recipes` | Admin | Implementado |
| `#purchasing` (tabs) | `/invoices` + `/suppliers` | Admin | Implementado (unificado en 2 tabs) |
| `#reports` | — | Admin | **Propuesta (M20 — no implementado)** |
| `#settings` | — | Admin | **Propuesta (M01/M18/M21 — no implementado)** |
| Acceso denegado | `/unauthorized` | Empleado en ruta Admin | Implementado |

---

## 3. Adaptación responsiva del shell

- **Desktop (`>= 1152px` / `72rem`):** sidebar fija a la izquierda (`240px`) + topbar de estado global (estado de caja y rol) + área de trabajo fluida.
- **Tablet (`1024px`) y Mobile (`390px`):** sidebar colapsada en un `<dialog>` nativo deslizable (`#nav-drawer`) para liberar el 100% del ancho a la operación (permitiendo vista dividida catálogo + carrito en POS tablet `1024px`).
