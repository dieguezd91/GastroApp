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

  // ADMIN DASHBOARD: 3-tier operational hierarchy (Primary Cash+Sales -> Priority Actions -> Secondary Context)
  const prioritizedAlerts = [
    ...stockAlerts.map((ing) => ({
      severity: ing.currentStock <= 0 ? 1 : 2,
      variant: ing.currentStock <= 0 ? 'danger' : 'warn',
      iconName: ing.currentStock <= 0 ? 'alertOctagon' : 'alertTriangle',
      title: `${ing.name} (${ing.currentStock <= 0 ? 'Agotado' : 'Bajo mínimo'})`,
      meta: `Actual: ${ing.currentStock} ${ing.unit} · mín. ${ing.minStock} ${ing.unit}`,
      cta: 'Ajustar stock',
      route: 'inventory',
    })),
    ...costSpikeRecipes.map((r) => {
      const calc = getRecipeCalculation(r);
      return {
        severity: 2,
        variant: 'danger',
        iconName: 'recipes',
        title: `Costo de ${r.name} (+${calc.variationPct}%)`,
        meta: `${formatARS(r.lastCalculatedCost)} → ${formatARS(calc.unitCost)} por porción`,
        cta: 'Recalcular',
        route: 'recipes',
      };
    }),
    ...lowMarginProducts.map((p) => ({
      severity: 3,
      variant: 'warn',
      iconName: 'tag',
      title: `Margen bajo en ${p.name} (${getProductMargin(p)}%)`,
      meta: `Precio ${formatARS(p.price)} · costo ${formatARS(p.cost)}`,
      cta: 'Revisar precio',
      route: 'catalog',
    })),
  ].sort((a, b) => a.severity - b.severity);

  const totalAttention = prioritizedAlerts.length;

  container.innerHTML = `
    <div class="page-header">
      <div>
        <h1 id="page-heading" tabindex="-1">Panel operativo</h1>
        <p class="page-header__subtitle">${escapeHtml(state.businessSettings.tradeName)} · Estado del turno y prioridades del día</p>
      </div>
      <div class="page-header__actions">
        <button type="button" class="btn" data-go="cash">
          ${icon('cash', 18)}
          <span>${openReg ? 'Caja y arqueo' : 'Abrir caja'}</span>
        </button>
        <button type="button" class="btn btn--collect" data-go="pos">
          ${icon('pos', 18)}
          <span>Vender (POS)</span>
        </button>
      </div>
    </div>

    <div class="stack stack--lg">
      <!-- TIER 1: Primary Operational Focus (Cash state + 2 core numbers) -->
      <section class="cash-hero ${openReg ? '' : 'cash-hero--closed'}" aria-label="Estado operativo principal">
        <div class="stack stack--sm">
          <div class="flex-wrap-gap">
            ${openReg ? badge(`Caja abierta · Sesión #${openReg.id}`, 'ok', 'checkCircle') : badge('Caja cerrada', 'danger', 'alertOctagon')}
            ${openReg
              ? `<span class="text-xs text-secondary">Desde ${formatTime(openReg.openedAt)} · Fondo inicial ${formatARS(openReg.initialAmount)}</span>`
              : `<span class="text-xs text-secondary">Abrí la caja para habilitar ventas en el POS.</span>`}
          </div>
          <div class="hero-metrics">
            <div>
              <p class="hero-metric__label">${openReg ? 'Esperado en caja' : 'Estado de cobro'}</p>
              <p class="hero-metric__value">${openReg ? formatARS(expectedCash) : 'Bloqueado'}</p>
            </div>
            <div>
              <p class="hero-metric__label">Ventas netas hoy</p>
              <p class="hero-metric__value">${formatARS(netToday)}</p>
            </div>
            <div>
              <p class="hero-metric__label">Operaciones</p>
              <p class="hero-metric__value">${collectedSales.length}</p>
            </div>
          </div>
        </div>
        <div class="flex-wrap-gap">
          ${openReg
            ? `<button type="button" class="btn btn--primary" data-go="cash">Ir a arqueo y cierre</button>`
            : `<button type="button" class="btn btn--collect btn--lg" data-go="cash">Abrir caja ahora</button>`}
        </div>
      </section>

      <!-- TIER 2: Actionable Priorities + Recent Activity -->
      <div class="grid-2">
        <section class="card stack" aria-labelledby="dash-alerts-title">
          <div class="row-between">
            <div>
              <h2 id="dash-alerts-title" class="card__title">Requiere atención (${totalAttention})</h2>
              <p class="card__desc">${stockAlerts.length} stock · ${costSpikeRecipes.length} receta(s) · ${lowMarginProducts.length} margen &lt; ${state.businessSettings.lowMarginThresholdPct}%</p>
            </div>
            ${totalAttention > 3 ? `<button type="button" class="btn btn--ghost btn--sm" data-go="inventory">Ver todo</button>` : ''}
          </div>

          ${totalAttention === 0
            ? emptyState({
                iconName: 'checkCircle',
                title: 'Sin desvíos operativos',
                description: 'Stock, costos de recetas y márgenes están dentro de lo esperado.',
              })
            : `<ul class="alert-list">
                ${prioritizedAlerts.slice(0, 4).map((a) => `
                  <li class="alert-row">
                    <div class="alert-row__main">
                      <span class="${a.variant === 'danger' ? 'text-danger' : 'text-warn'}" style="margin-block-start: 2px;">${icon(a.iconName, 17)}</span>
                      <div>
                        <p class="text-sm fw-700">${escapeHtml(a.title)}</p>
                        <p class="text-xs text-muted">${escapeHtml(a.meta)}</p>
                      </div>
                    </div>
                    <button type="button" class="btn btn--sm" data-go="${a.route}">${escapeHtml(a.cta)}</button>
                  </li>
                `).join('')}
              </ul>`}
        </section>

        <section class="card stack" aria-labelledby="dash-recent-title">
          <div class="row-between">
            <div>
              <h2 id="dash-recent-title" class="card__title">Últimas ventas del turno</h2>
              <p class="card__desc">Ticket promedio: <strong class="tnum">${collectedSales.length ? formatARS(netToday / collectedSales.length) : formatARS(0)}</strong>${refundedTotal > 0 ? ` · Devuelto: ${formatARS(refundedTotal)}` : ''}</p>
            </div>
            <button type="button" class="btn btn--ghost btn--sm" data-go="sales-history">Historial completo</button>
          </div>

          ${todaySales.length === 0
            ? emptyState({
                iconName: 'receipt',
                title: 'Sin ventas en esta sesión',
                description: 'Las ventas registradas en el POS aparecerán acá.',
                actionHtml: `<button type="button" class="btn btn--collect btn--sm" data-go="pos">Ir al POS</button>`,
              })
            : `<div class="table-wrapper" tabindex="0" role="region" aria-labelledby="dash-recent-title">
                <table class="data-table data-table--stack">
                  <thead>
                    <tr>
                      <th scope="col">Venta</th>
                      <th scope="col">Estado</th>
                      <th scope="col" class="col-num">Total</th>
                    </tr>
                  </thead>
                  <tbody>
                    ${todaySales.slice(0, 4).map((s) => {
                      const st = getSaleDisplayStatus(s);
                      return `
                        <tr>
                          <th scope="row">#${s.id} <span class="text-xs text-muted fw-600">· ${formatTime(s.date)} · ${escapeHtml(s.operator.split(' ')[0])}</span></th>
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

      <!-- TIER 3: Compact Secondary Shortcuts -->
      <section class="secondary-strip" aria-label="Accesos directos secundarios">
        <span class="text-xs fw-700 text-muted" style="text-transform: uppercase;">Accesos rápidos:</span>
        <div class="flex-wrap-gap">
          <button type="button" class="btn btn--sm" data-go="catalog">${icon('products', 15)} Productos (${state.products.filter((p) => p.isActive).length})</button>
          <button type="button" class="btn btn--sm" data-go="inventory">${icon('ingredients', 15)} Stock (${stockAlerts.length} alertas)</button>
          <button type="button" class="btn btn--sm" data-go="recipes">${icon('recipes', 15)} Recetas (${state.recipes.length})</button>
          <button type="button" class="btn btn--sm" data-go="summary">${icon('summary', 15)} Resumen del día</button>
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
