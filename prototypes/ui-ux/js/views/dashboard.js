import {
  getState,
  getOpenCashRegister,
  getExpectedCash,
  getStockAlerts,
  getProductMargin,
  getRecipeCalculation,
  getSaleDisplayStatus,
} from '../state/store.js';
import { formatARS, formatTime, escapeHtml } from '../utils/format.js';
import { icon } from '../utils/icons.js';
import { badge, banner, kpiCard, emptyState, loadingSkeleton } from '../utils/ui.js';

export function renderDashboard(container, navigate) {
  const state = getState();
  const user = state.auth.currentUser;
  const isAdmin = user?.role === 'Admin';
  const openReg = getOpenCashRegister();

  if (state.demo.simulateLoading) {
    container.innerHTML = `
      <div class="page-header">
        <div>
          <h1 id="page-heading" tabindex="-1">Inicio</h1>
          <p class="page-header__subtitle">Cargando resumen operativo del turno…</p>
        </div>
      </div>
      ${loadingSkeleton(4)}
    `;
    return;
  }

  const todaySales = state.demo.simulateEmpty
    ? []
    : state.sales.filter((s) => s.cashRegisterId === (openReg?.id || state.cashRegisters[0]?.id));
  const collectedSales = todaySales.filter((s) => s.status !== 'Cancelled');
  const todayTotal = collectedSales.reduce((a, s) => a + s.total, 0);
  const refundedTotal = collectedSales.reduce(
    (a, s) => a + (s.refunds || []).reduce((rAcc, r) => rAcc + r.total, 0),
    0
  );
  const netToday = todayTotal - refundedTotal;
  const expectedCash = openReg ? getExpectedCash(openReg.id) : 0;

  // Operational problems for Admin (feeds Priority 3)
  const stockAlerts = state.demo.simulateEmpty ? [] : getStockAlerts();
  const lowMarginProducts = state.demo.simulateEmpty
    ? []
    : state.products.filter((p) => {
        const m = getProductMargin(p);
        return p.isActive && m != null && m < state.businessSettings.lowMarginThresholdPct;
      });
  const costSpikeRecipes = state.demo.simulateEmpty
    ? []
    : state.recipes.filter((r) => Math.abs(getRecipeCalculation(r).variationPct) >= 30);

  if (!isAdmin) {
    // EMPLOYEE DASHBOARD: Focused, low cognitive load, immediate POS path
    container.innerHTML = `
      <div class="page-header">
        <div>
          <h1 id="page-heading" tabindex="-1">Hola, ${escapeHtml(user.fullName)}</h1>
          <p class="page-header__subtitle">Vista operativa de turno · Rol Empleado</p>
        </div>
      </div>

      <div class="stack stack--lg">
        <section class="cash-hero ${openReg ? '' : 'cash-hero--closed'}" aria-label="Estado de la caja actual">
          <div class="stack stack--sm">
            <div class="flex-wrap-gap">
              ${openReg ? badge('Caja abierta', 'ok', 'checkCircle') : badge('Caja cerrada', 'danger', 'alertOctagon')}
              ${openReg ? `<span class="text-sm text-secondary">Sesión #${openReg.id} · Apertura ${formatTime(openReg.openedAt)}</span>` : ''}
            </div>
            <h2>${openReg ? 'Todo listo para tomar pedidos y cobrar' : 'La caja todavía no está abierta'}</h2>
            <p class="text-sm text-secondary">
              ${openReg
                ? 'Podés entrar al Punto de Venta para cargar productos, aplicar descuentos y cobrar con efectivo o medios digitales.'
                : 'Pedile a un Administrador que realice la apertura de caja para habilitar las ventas del turno.'}
            </p>
          </div>
          <div>
            <button type="button" class="btn btn--collect btn--lg" data-go="pos">
              ${icon('pos', 20)}
              <span>${openReg ? 'Ir al Punto de Venta' : 'Ver Punto de Venta'}</span>
            </button>
          </div>
        </section>

        <section class="grid-kpi" aria-label="Indicadores del turno">
          ${kpiCard({
            label: 'Ventas del turno',
            value: String(collectedSales.length),
            meta: openReg ? `Sesión #${openReg.id}` : 'Sin sesión activa',
          })}
          ${kpiCard({
            label: 'Total vendido hoy',
            value: formatARS(netToday),
            meta: refundedTotal > 0 ? `Incluye ${formatARS(refundedTotal)} en devoluciones` : 'Sin devoluciones hoy',
          })}
          ${kpiCard({
            label: 'Productos sin stock',
            value: String(stockAlerts.filter((i) => i.currentStock <= 0).length),
            meta: stockAlerts.length ? 'Verificá disponibilidad al cargar pedidos' : 'Sin faltantes informados',
            badgeHtml: stockAlerts.some((i) => i.currentStock <= 0) ? badge('Atención', 'warn', 'alertTriangle') : badge('OK', 'ok', 'check'),
          })}
        </section>

        ${!openReg ? banner({
          variant: 'warn',
          title: 'Permisos de Empleado',
          body: 'La apertura, movimientos manuales y cierre de caja son exclusivos del rol Administrador. Podés explorar el catálogo, pero el cobro queda bloqueado hasta abrir caja.',
        }) : ''}
      </div>
    `;

    container.querySelectorAll('[data-go]').forEach((el) => {
      el.addEventListener('click', () => navigate(el.dataset.go));
    });
    return;
  }

  // ADMIN DASHBOARD: Contextual operational cockpit
  const totalAttention = stockAlerts.length + lowMarginProducts.length + costSpikeRecipes.length;

  container.innerHTML = `
    <div class="page-header">
      <div>
        <h1 id="page-heading" tabindex="-1">Panel operativo</h1>
        <p class="page-header__subtitle">${escapeHtml(state.businessSettings.tradeName)} · Supervisión diaria de caja, ventas, costos e inventario</p>
      </div>
      <div class="page-header__actions">
        <button type="button" class="btn" data-go="cash">
          ${icon('cash', 18)}
          <span>${openReg ? 'Gestionar caja y arqueo' : 'Abrir caja'}</span>
        </button>
        <button type="button" class="btn btn--collect" data-go="pos">
          ${icon('pos', 18)}
          <span>Vender (POS)</span>
        </button>
      </div>
    </div>

    <div class="stack stack--lg">
      <!-- Contextual Cash Register Hero -->
      <section class="cash-hero ${openReg ? '' : 'cash-hero--closed'}" aria-label="Estado de la caja diaria">
        <div class="stack stack--sm">
          <div class="flex-wrap-gap">
            ${openReg ? badge(`Caja abierta · Sesión #${openReg.id}`, 'ok', 'checkCircle') : badge('Caja cerrada', 'danger', 'alertOctagon')}
            ${openReg
              ? `<span class="text-sm text-secondary">Abierta a las ${formatTime(openReg.openedAt)} por ${escapeHtml(openReg.openedBy)} · Fondo inicial ${formatARS(openReg.initialAmount)}</span>`
              : `<span class="text-sm text-secondary">Abrí la caja con el fondo inicial para habilitar cobros en el POS.</span>`}
          </div>
          <h2>${openReg ? `Esperado en caja: ${formatARS(expectedCash)}` : 'Caja cerrada — Ventas bloqueadas'}</h2>
        </div>
        <div class="flex-wrap-gap">
          ${openReg
            ? `<button type="button" class="btn btn--primary" data-go="cash">Ir a arqueo y cierre</button>`
            : `<button type="button" class="btn btn--collect btn--lg" data-go="cash">Abrir caja ahora</button>`}
        </div>
      </section>

      <!-- KPI Strip -->
      <section class="grid-kpi" aria-label="Resumen del día">
        ${kpiCard({
          label: 'Ventas netas hoy',
          value: formatARS(netToday),
          meta: `${collectedSales.length} ventas cobradas${refundedTotal > 0 ? ` · ${formatARS(refundedTotal)} devuelto` : ''}`,
        })}
        ${kpiCard({
          label: 'Ticket promedio',
          value: collectedSales.length ? formatARS(netToday / collectedSales.length) : formatARS(0),
          meta: 'Sobre ventas no anuladas',
        })}
        ${kpiCard({
          label: 'Alertas de stock',
          value: String(stockAlerts.length),
          meta: stockAlerts.length ? `${stockAlerts.filter((a) => a.currentStock <= 0).length} agotado(s) · ${stockAlerts.filter((a) => a.currentStock > 0).length} bajo mínimo` : 'Todos los ingredientes sobre el mínimo',
          badgeHtml: stockAlerts.length ? badge('Revisar', 'danger', 'alertTriangle') : badge('Normal', 'ok', 'check'),
        })}
        ${kpiCard({
          label: 'Alertas de costo / margen',
          value: String(lowMarginProducts.length + costSpikeRecipes.length),
          meta: `${costSpikeRecipes.length} receta(s) con suba >= 30% · ${lowMarginProducts.length} producto(s) margen < ${state.businessSettings.lowMarginThresholdPct}%`,
          badgeHtml: (lowMarginProducts.length + costSpikeRecipes.length) ? badge('Acción sugerida', 'warn', 'alertTriangle') : badge('OK', 'ok', 'check'),
        })}
      </section>

      <!-- Actionable Priorities Grid -->
      <div class="grid-2">
        <section class="card stack" aria-labelledby="dash-alerts-title">
          <div class="card__header" style="margin-block-end: 0;">
            <div>
              <h2 id="dash-alerts-title" class="card__title">Requiere tu atención (${totalAttention})</h2>
              <p class="card__desc">Desvíos detectados en stock, recetas y márgenes para resolver en un clic.</p>
            </div>
          </div>

          ${totalAttention === 0
            ? emptyState({
                iconName: 'checkCircle',
                title: 'Sin desvíos operativos',
                description: 'El stock, los costos de recetas y los márgenes de productos están dentro de los parámetros esperados.',
              })
            : `<div class="stack stack--sm">
                ${stockAlerts.slice(0, 3).map((ing) => `
                  <div class="banner banner--${ing.currentStock <= 0 ? 'danger' : 'warn'}" style="padding: var(--space-3);">
                    <div class="banner__body">
                      <span class="banner__icon">${icon(ing.currentStock <= 0 ? 'alertOctagon' : 'alertTriangle', 18)}</span>
                      <div>
                        <p class="banner__title">${escapeHtml(ing.name)} — ${ing.currentStock <= 0 ? 'Agotado' : 'Bajo mínimo'}</p>
                        <p class="text-xs">Stock actual: <strong>${ing.currentStock} ${ing.unit}</strong> (mínimo ${ing.minStock} ${ing.unit})</p>
                      </div>
                    </div>
                    <button type="button" class="btn btn--sm" data-go="inventory">Resolver en stock</button>
                  </div>
                `).join('')}

                ${costSpikeRecipes.slice(0, 2).map((r) => {
                  const calc = getRecipeCalculation(r);
                  return `
                    <div class="banner banner--danger" style="padding: var(--space-3);">
                      <div class="banner__body">
                        <span class="banner__icon">${icon('recipes', 18)}</span>
                        <div>
                          <p class="banner__title">Suba de costo en ${escapeHtml(r.name)} (+${calc.variationPct}%)</p>
                          <p class="text-xs">Anterior: ${formatARS(r.lastCalculatedCost)} → Actual: <strong>${formatARS(calc.unitCost)}</strong> por porción</p>
                        </div>
                      </div>
                      <button type="button" class="btn btn--sm" data-go="recipes">Recalcular receta</button>
                    </div>
                  `;
                }).join('')}

                ${lowMarginProducts.slice(0, 2).map((p) => {
                  const m = getProductMargin(p);
                  return `
                    <div class="banner banner--warn" style="padding: var(--space-3);">
                      <div class="banner__body">
                        <span class="banner__icon">${icon('tag', 18)}</span>
                        <div>
                          <p class="banner__title">Margen bajo en ${escapeHtml(p.name)} (${m}%)</p>
                          <p class="text-xs">Precio ${formatARS(p.price)} · Costo ${formatARS(p.cost)}</p>
                        </div>
                      </div>
                      <button type="button" class="btn btn--sm" data-go="catalog">Ajustar precio</button>
                    </div>
                  `;
                }).join('')}
              </div>`}
        </section>

        <section class="card stack" aria-labelledby="dash-recent-title">
          <div class="card__header" style="margin-block-end: 0;">
            <div>
              <h2 id="dash-recent-title" class="card__title">Actividad reciente de ventas</h2>
              <p class="card__desc">Últimas operaciones registradas en la sesión actual.</p>
            </div>
            <button type="button" class="btn btn--sm" data-go="sales-history">Ver historial completo</button>
          </div>

          ${todaySales.length === 0
            ? emptyState({
                iconName: 'receipt',
                title: 'Todavía no hay ventas en esta sesión',
                description: 'Cuando registres operaciones desde el POS aparecerán acá en tiempo real.',
                actionHtml: `<button type="button" class="btn btn--collect" data-go="pos">Ir al Punto de Venta</button>`,
              })
            : `<div class="table-wrapper" tabindex="0" role="region" aria-labelledby="dash-recent-title">
                <table class="data-table data-table--stack">
                  <thead>
                    <tr>
                      <th scope="col">Venta</th>
                      <th scope="col">Operador</th>
                      <th scope="col">Estado</th>
                      <th scope="col" class="col-num">Total</th>
                    </tr>
                  </thead>
                  <tbody>
                    ${todaySales.slice(0, 5).map((s) => {
                      const st = getSaleDisplayStatus(s);
                      return `
                        <tr>
                          <th scope="row">#${s.id} <span class="text-xs text-muted fw-600">· ${formatTime(s.date)}</span></th>
                          <td data-label="Operador">${escapeHtml(s.operator)}</td>
                          <td data-label="Estado">${badge(st.label, st.variant)}</td>
                          <td data-label="Total" class="col-num fw-700">${formatARS(s.total)}</td>
                        </tr>
                      `;
                    }).join('')}
                  </tbody>
                </table>
              </div>`}
        </section>
      </div>

      <!-- Direct Admin Shortcuts -->
      <section class="stack stack--sm" aria-labelledby="dash-shortcuts-title">
        <h2 id="dash-shortcuts-title" class="card__title">Accesos rápidos</h2>
        <div class="quick-links">
          <a href="#catalog" class="quick-link" data-go="catalog">
            <span class="quick-link__icon">${icon('products', 20)}</span>
            <div>
              <p>Productos y categorías</p>
              <p class="text-xs text-muted">${state.products.filter((p) => p.isActive).length} activos</p>
            </div>
          </a>
          <a href="#inventory" class="quick-link" data-go="inventory">
            <span class="quick-link__icon">${icon('ingredients', 20)}</span>
            <div>
              <p>Ingredientes y stock</p>
              <p class="text-xs text-muted">${stockAlerts.length} alerta(s) activa(s)</p>
            </div>
          </a>
          <a href="#recipes" class="quick-link" data-go="recipes">
            <span class="quick-link__icon">${icon('recipes', 20)}</span>
            <div>
              <p>Recetas y costos</p>
              <p class="text-xs text-muted">${state.recipes.length} recetas estandarizadas</p>
            </div>
          </a>
          <a href="#summary" class="quick-link" data-go="summary">
            <span class="quick-link__icon">${icon('summary', 20)}</span>
            <div>
              <p>Resumen del día</p>
              <p class="text-xs text-muted">Descuentos, anulaciones y neto</p>
            </div>
          </a>
        </div>
      </section>
    </div>
  `;

  container.querySelectorAll('[data-go]').forEach((el) => {
    el.addEventListener('click', (e) => {
      e.preventDefault();
      navigate(el.dataset.go);
    });
  });
}
