import { getState, getProductMargin, getMarginHealth } from '../state/store.js';
import { formatARS, formatPct, escapeHtml } from '../utils/format.js';
import { badge, kpiCard, loadingSkeleton, proposalBanner } from '../utils/ui.js';

let period = '7d';

const MOCK_PERIODS = {
  '7d': {
    label: 'Últimos 7 días',
    revenue: 1482500,
    estimatedCost: 548525,
    avgTicket: 12980,
    salesCount: 114,
    categories: [
      { name: 'Cocina', revenue: 742000, cost: 311640, share: 50 },
      { name: 'Cafetería', revenue: 418500, cost: 117180, share: 28 },
      { name: 'Panadería y Pastelería', revenue: 196000, cost: 72520, share: 13 },
      { name: 'Bebidas', revenue: 126000, cost: 47185, share: 9 },
    ],
  },
  '30d': {
    label: 'Últimos 30 días',
    revenue: 6120400,
    estimatedCost: 2325750,
    avgTicket: 12640,
    salesCount: 484,
    categories: [
      { name: 'Cocina', revenue: 3121400, cost: 1342200, share: 51 },
      { name: 'Cafetería', revenue: 1652500, cost: 462700, share: 27 },
      { name: 'Panadería y Pastelería', revenue: 856800, cost: 317010, share: 14 },
      { name: 'Bebidas', revenue: 489700, cost: 203840, share: 8 },
    ],
  },
};

export function renderReports(container, navigate) {
  const state = getState();
  if (state.demo.simulateLoading) {
    container.innerHTML = `
      <div class="page-header"><h1 id="page-heading" tabindex="-1">Reportes y rentabilidad</h1></div>
      ${loadingSkeleton(4)}
    `;
    return;
  }
  const data = MOCK_PERIODS[period];
  const grossMargin = data.revenue - data.estimatedCost;
  const marginPct = Math.round((grossMargin / data.revenue) * 1000) / 10;

  const productMargins = state.products
    .filter((p) => p.isActive && p.cost != null)
    .map((p) => ({
      ...p,
      margin: getProductMargin(p),
      profitUnit: p.price - p.cost,
    }))
    .sort((a, b) => a.margin - b.margin);

  container.innerHTML = `
    <div class="page-header">
      <div>
        <div class="page-header__title-row">
          <h1 id="page-heading" tabindex="-1">Reportes y rentabilidad</h1>
          ${badge('Propuesta · No implementado', 'proposal', 'sparkles')}
        </div>
        <p class="page-header__subtitle">Visión propuesta (Módulo M20 del documento de diseño) para análisis multidía de ventas, costos y margen real por categoría y producto.</p>
      </div>
      <div class="page-header__actions" role="group" aria-label="Período de análisis">
        <button type="button" class="chip" data-rep-period="7d" aria-pressed="${period === '7d'}">Últimos 7 días</button>
        <button type="button" class="chip" data-rep-period="30d" aria-pressed="${period === '30d'}">Últimos 30 días</button>
      </div>
    </div>

    <div class="stack stack--lg">
      ${proposalBanner(
        'M20',
        'Hoy GastroApp cuenta únicamente con el Resumen del Día (/summary). Esta pantalla muestra la experiencia futura propuesta combinando series ficticias y los márgenes actuales del catálogo.'
      )}

      <section class="grid-kpi" aria-label="Indicadores de rentabilidad (${data.label})">
        ${kpiCard({ label: `Facturación neta (${data.label})`, value: formatARS(data.revenue), meta: `${data.salesCount} ventas cobradas` })}
        ${kpiCard({ label: 'Costo teórico estimado', value: formatARS(data.estimatedCost), meta: 'Según última factura / receta' })}
        ${kpiCard({ label: 'Margen bruto estimado', value: formatARS(grossMargin), meta: `Rentabilidad promedio: ${formatPct(marginPct)}`, badgeHtml: badge(marginPct >= 60 ? 'Óptimo' : 'Revisar', marginPct >= 60 ? 'ok' : 'warn') })}
        ${kpiCard({ label: 'Ticket promedio', value: formatARS(data.avgTicket), meta: data.label })}
      </section>

      <div class="grid-2">
        <section class="card stack" aria-labelledby="rep-cat-chart">
          <div>
            <h2 id="rep-cat-chart" class="card__title">Participación de ventas por categoría</h2>
            <p class="card__desc">Distribución visual acompañada de tabla semántica accesible.</p>
          </div>
          <div class="bar-chart" aria-hidden="true">
            ${data.categories.map((c) => `
              <div class="bar-row">
                <span class="fw-600">${escapeHtml(c.name)}</span>
                <div class="bar-track"><div class="bar-fill" style="inline-size: ${c.share}%"></div></div>
                <span class="tnum fw-700">${c.share}%</span>
              </div>
            `).join('')}
          </div>
        </section>

        <section class="card stack" aria-labelledby="rep-cat-table">
          <div>
            <h2 id="rep-cat-table" class="card__title">Rentabilidad por categoría</h2>
            <p class="card__desc">Cruce propuesto entre ingresos, costo de mercadería y margen resultante.</p>
          </div>
          <div class="table-wrapper" tabindex="0" role="region" aria-labelledby="rep-cat-table">
            <table class="data-table data-table--stack">
              <thead>
                <tr>
                  <th scope="col">Categoría</th>
                  <th scope="col" class="col-num">Ventas</th>
                  <th scope="col" class="col-num">Costo est.</th>
                  <th scope="col" class="col-num">Margen</th>
                </tr>
              </thead>
              <tbody>
                ${data.categories.map((c) => {
                  const mPct = Math.round(((c.revenue - c.cost) / c.revenue) * 1000) / 10;
                  return `
                    <tr>
                      <th scope="row">${escapeHtml(c.name)}</th>
                      <td data-label="Ventas" class="col-num">${formatARS(c.revenue)}</td>
                      <td data-label="Costo" class="col-num">${formatARS(c.cost)}</td>
                      <td data-label="Margen" class="col-num fw-700">${badge(formatPct(mPct), mPct >= 60 ? 'ok' : 'warn')}</td>
                    </tr>
                  `;
                }).join('')}
              </tbody>
            </table>
          </div>
        </section>
      </div>

      <section class="card stack" aria-labelledby="rep-prod-table">
        <div class="row-between">
          <div>
            <h2 id="rep-prod-table" class="card__title">Ranking de margen por producto activo (en vivo)</h2>
            <p class="card__desc">Ordenado de menor a mayor margen para detectar rápidamente qué precios actualizar.</p>
          </div>
          <button type="button" class="btn btn--sm" id="rep-go-catalog">Ajustar en Productos</button>
        </div>
        <div class="table-wrapper" tabindex="0" role="region" aria-labelledby="rep-prod-table">
          <table class="data-table data-table--stack">
            <thead>
              <tr>
                <th scope="col">Producto</th>
                <th scope="col" class="col-num">Precio</th>
                <th scope="col" class="col-num">Costo</th>
                <th scope="col" class="col-num">Contribución unit.</th>
                <th scope="col">Margen</th>
              </tr>
            </thead>
            <tbody>
              ${productMargins.map((p) => {
                const health = getMarginHealth(p.margin);
                return `
                  <tr>
                    <th scope="row">${escapeHtml(p.name)}</th>
                    <td data-label="Precio" class="col-num">${formatARS(p.price)}</td>
                    <td data-label="Costo" class="col-num">${formatARS(p.cost)}</td>
                    <td data-label="Contribución" class="col-num fw-700">${formatARS(p.profitUnit)}</td>
                    <td data-label="Margen">${badge(`${p.margin}% · ${health.label}`, health.variant)}</td>
                  </tr>
                `;
              }).join('')}
            </tbody>
          </table>
        </div>
      </section>
    </div>
  `;

  container.querySelectorAll('[data-rep-period]').forEach((btn) => {
    btn.addEventListener('click', () => {
      period = btn.dataset.repPeriod;
      renderReports(container, navigate);
    });
  });
  container.querySelector('#rep-go-catalog')?.addEventListener('click', () => navigate('catalog'));
}
