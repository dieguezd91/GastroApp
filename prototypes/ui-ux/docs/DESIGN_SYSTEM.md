# Sistema de Diseño — GastroApp ("Bistro Craft")

Sistema visual reutilizable y modular diseñado para operaciones gastronómicas rápidas en escritorio, tablets táctiles y móviles, con objetivo de conformidad **WCAG 2.2 AA**.

---

## 1. Arquitectura CSS

Hojas organizadas con **Cascade Layers** declaradas al inicio de [`styles/tokens.css`](../styles/tokens.css):

```css
@layer base, theme, layout, components, views, utilities;
```

- [`styles/tokens.css`](../styles/tokens.css): tokens de 3 niveles (primitivos, semánticos, UI/layout), soporte `pointer: coarse` y `forced-colors: active`.
- [`styles/base.css`](../styles/base.css): tipografía, `box-sizing` por elemento (sin reset global `*`), `:focus-visible`, `.visually-hidden` y `.skip-link`.
- [`styles/layout.css`](../styles/layout.css): shell con sidebar desktop persistente (`>= 72rem`), topbar sticky, drawer móvil/tablet en `<dialog>` nativo y grillas `@container`.
- [`styles/components.css`](../styles/components.css): tarjetas, KPIs, botones, badges semánticos, banners, formularios con `:user-invalid`, tabs de fila única, tablas `@container` apilables, modales `<dialog>` y toasts `[popover="manual"]`.
- [`styles/views.css`](../styles/views.css): layout POS dividido, calculadora de arqueo por denominación, barra fija móvil, stepper y timeline.

---

## 2. Identidad visual y tokens

### Paleta de color (contraste AA verificado)

| Rol | Token | Valor | Contraste / Uso |
|---|---|---|---|
| Lienzo | `--surface-canvas` | `#F5F3EE` | Piedra cálida neutra; reduce fatiga visual en barra/cocina |
| Superficie | `--surface-card` | `#FFFFFF` | Tarjetas, tablas, modales y controles |
| Sidebar | `--surface-sidebar` | `#161B18` | Rail oscuro de alto contraste (`#F7F6F2` texto > 15:1) |
| Primario marca | `--brand-primary` | `#B84A27` | Terracota tostado (5.24:1 sobre blanco; hover `#993B1D`) |
| Acción Cobrar / Abierta | `--action-collect` | `#14704B` | Esmeralda profundo (5.9:1 sobre blanco) |
| Texto principal | `--text-primary` | `#161B18` | > 16:1 sobre blanco |
| Texto secundario / muted | `--text-secondary` / `--text-muted` | `#3D443F` / `#555D57` | > 6.3:1 sobre blanco |
| Borde de control | `--border-control` | `#727973` | 4.4:1 sobre blanco (supera WCAG 1.4.11 >= 3:1) |
| Propuesta futura | `--status-proposal-ink` / `bg` | `#5B21B6` / `#F4EFFF` | Distingue módulos propuestos del producto actual |

**Regla estricta (WCAG 1.4.1):** ningún estado se comunica solo con color; todo badge, alerta o error combina color + ícono SVG + etiqueta textual explícita.

### Tipografía y números
- Familia principal: `Plus Jakarta Sans` con fallback limpio a `Inter`, `system-ui`, `sans-serif`.
- Títulos con escala fluida acotada por `clamp()` (máximo `<= 2.5x` mínimo para cumplir WCAG 1.4.4 zoom 200%) y `text-wrap: balance`.
- Todos los importes en `ARS`, cantidades de stock, porcentajes y columnas numéricas usan `font-variant-numeric: tabular-nums` (`.tnum`).

### Iconografía
- Set SVG inline minimalista (`js/utils/icons.js`, trazo `1.85px`, `viewBox="0 0 24 24"`).
- Cero emojis como iconografía UI.
- Los íconos decorativos llevan `aria-hidden="true"`; los botones de solo ícono llevan `aria-label` descriptivo.

---

## 3. Componentes reutilizables

- **Botones (`.btn`):** variantes `--primary`, `--collect`, `--danger`, `--danger-outline`, `--ghost`, tamaños `--sm`, `--lg`, `--icon`, altura táctil `44–50px` (`--control-height: 3rem` en `pointer: coarse`).
- **Badges (`.badge`) y Banners (`.banner`):** `ok`, `warn`, `danger`, `info`, `neutral`, `proposal`.
- **Tablas responsivas (`.table-wrapper` + `.data-table--stack`):** envueltas en `tabindex="0" role="region"` con `container: data-table / inline-size`; por debajo de `37rem` se apilan en tarjetas semánticas inyectando `data-label` vía `::before`.
- **Modales nativos (`<dialog class="modal">`):** abiertos con `showModal()`, `overscroll-behavior: contain` en `dialog:modal` y `dialog::backdrop` (con `overflow: hidden` en `::backdrop`), `closedby="any"` + fallback JS en modales no destructivos, y `autofocus` en "Cancelar" para confirmaciones destructivas.
- **Formularios (`.field`, `.input`, `.select`):** `font-size: max(1rem, 1em)` (evita zoom automático en iOS), validación diferida con `:is(:user-invalid, .user-invalid-fallback)` + sincronización automática de `aria-invalid` y `aria-describedby` (`js/utils/a11y.js`).
- **Notificaciones (`[popover="manual"]`):** ubicadas en la esquina inferior derecha del Top Layer, con botón explícito "Cerrar", pausa de autocierre al recibir foco, supresión visual mientras hay un modal abierto y anuncio vía `ariaNotify()` / live region `polite`.

---

## 4. Guía de adopción en Blazor Server

1. Migrar `styles/tokens.css`, `base.css`, `layout.css`, `components.css` y `views.css` a `wwwroot/css/` reemplazando gradualmente Bootstrap/Open Iconic sin tocar los servicios C#.
2. Encapsular `Badge`, `Banner`, `KpiCard`, `ModalDialog` y `ResponsiveTable` como componentes Razor reutilizables en `Shared/Components/`.
3. Conservar los helpers mínimos de JS (`a11y.js`: `showModal()`, drawer scroll-snap, `aria-invalid` sync) a través de un pequeño módulo JS interop en Blazor.
