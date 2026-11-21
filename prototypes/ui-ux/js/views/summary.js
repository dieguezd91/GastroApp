import { getState, getCanonicalCashRegister, cancelSale } from '../state/store.js';
import { formatARS, escapeHtml, roundMoney } from '../utils/format.js';
import { icon } from '../utils/icons.js';
import { badge, banner, kpiCard, loadingSkeleton, openConfirmModal } from '../utils/ui.js';
import { showToast } from '../utils/a11y.js';

export function renderSummary(container, navigate) {
  const state = getState();

  if (state.demo.simulateLoading) {
    container.innerHTML = `
      <div class="page-header"><h1 id="page-heading" tabindex="-1">Resumen del día</h1></div>
      ${loadingSkeleton(4)}
    `;
    return;
  }

  const reg = getCanonicalCashRegister();
  const todaySales = state.demo.simulateEmpty ? [] : state.sales.filter((s) => s.cashRegisterId === reg?.id);
  const activeSales = todaySales.filter((s) => s.status !== 'Cancelled');
  const cancelledSales = todaySales.filter((s) => s.status === 'Cancelled');

  const gross = roundMoney(activeSales.reduce((a, s) => a + s.items.reduce((ia, i) => ia + i.lineGross, 0), 0));
  const discounts = roundMoney(
    activeSales.reduce(
      (a, s) => a + s.saleDiscountAmount + s.items.reduce((ia, i) => ia + i.lineDiscount, 0),
      0
    )
  );
  const totalSold = roundMoney(gross - discounts);
  const cancelledAmt = roundMoney(cancelledSales.reduce((a, s) => a + s.total, 0));
  const refundsAmt = roundMoney(
    activeSales.reduce((a, s) => a + (s.refunds || []).reduce((ra, r) => ra + r.total, 0), 0)
  );
  const net = roundMoney(totalSold - refundsAmt);

  // Top product calculation
  const prodCounts = new Map();
  for (const s of activeSales) {
    for (const it of s.items) {
      prodCounts.set(it.productName, (prodCounts.get(it.productName) || 0) + it.quantity);
    }
  }
  const topEntry = [...prodCounts.entries()].sort((a, b) => b[1] - a[1])[0];
  const cancellableSales = activeSales.filter((s) => !(s.refunds || []).length);

  container.innerHTML = `
    <div class="page-header">
      <div>
        <h1 id="page-heading" tabindex="-1">Resumen del día</h1>
        <p class="page-header__subtitle">Cierre operativo de ventas, descuentos, anulaciones, devoluciones y estado de caja de la jornada actual.</p>
      </div>
      <div class="page-header__actions">
        <button type="button" class="btn" id="sum-go-cash">${icon('cash', 17)} Ir a caja</button>
        <button type="button" class="btn" id="sum-go-history">${icon('receipt', 17)} Ver historial completo</button>
      </div>
    </div>

    <div class="stack stack--lg">
      <section class="grid-kpi" aria-label="Indicadores diarios">
        ${kpiCard({ label: 'Total vendido (tras desc.)', value: formatARS(totalSold), meta: `Importe neto tras devoluciones: ${formatARS(net)}` })}
        ${kpiCard({ label: 'Cantidad de ventas', value: String(activeSales.length), meta: `${cancelledSales.length} anulada(s) aparte` })}
        ${kpiCard({ label: 'Producto más vendido', value: topEntry ? topEntry[0] : 'Sin ventas', meta: topEntry ? `${topEntry[1]} unidades vendidas hoy` : '—' })}
        ${kpiCard({
          label: 'Estado de caja',
          value: reg?.status === 'Open' ? 'Abierta' : 'Cerrada',
          meta: reg ? `Sesión #${reg.id}${reg.status === 'Closed' && reg.differenceSnapshot != null ? ` · Dif.: ${reg.differenceSnapshot === 0 ? 'Exacto' : formatARS(reg.differenceSnapshot)}` : ''}` : 'Sin sesión',
          badgeHtml: reg?.status === 'Open' ? badge('En curso', 'ok') : badge('Cerrada', 'neutral'),
        })}
      </section>

      ${reg?.status === 'Closed' ? `
        <section class="card stack" aria-labelledby="sum-cash-close-title">
          <div class="row-between">
            <div>
              <h2 id="sum-cash-close-title" class="card__title">Resultado del cierre de caja · Sesión #${reg.id}</h2>
              <p class="card__desc">Comparación final entre efectivo esperado y arqueo contado al cerrar.</p>
            </div>
            ${badge(
              reg.differenceSnapshot === 0 ? 'Exacto' : reg.differenceSnapshot > 0 ? `Sobrante +${formatARS(reg.differenceSnapshot)}` : `Faltante ${formatARS(reg.differenceSnapshot)}`,
              reg.differenceSnapshot === 0 ? 'ok' : reg.differenceSnapshot > 0 ? 'info' : 'danger'
            )}
          </div>
          <div class="grid-kpi">
            ${kpiCard({ label: 'Fondo inicial', value: formatARS(reg.initialAmount) })}
            ${kpiCard({ label: 'Esperado en caja', value: formatARS(reg.expectedAmountSnapshot) })}
            ${kpiCard({ label: 'Efectivo contado', value: formatARS(reg.countedAmount) })}
            ${kpiCard({ label: 'Diferencia del cierre', value: reg.differenceSnapshot === 0 ? 'Exacto ($ 0)' : formatARS(reg.differenceSnapshot) })}
          </div>
        </section>
      ` : ''}

      <section class="card stack" aria-labelledby="sum-table-title">
        <h2 id="sum-table-title" class="card__title">Ventas, descuentos, anulaciones y devoluciones de hoy</h2>
        <div class="table-wrapper" tabindex="0" role="region" aria-labelledby="sum-table-title">
          <table class="data-table data-table--stack">
            <thead>
              <tr>
                <th scope="col">Concepto</th>
                <th scope="col">Qué incluye</th>
                <th scope="col" class="col-num">Importe</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <th scope="row">Ventas brutas</th>
                <td data-label="Qué incluye" class="text-secondary">Ventas cobradas antes de descuentos (excluye anuladas)</td>
                <td data-label="Importe" class="col-num">${formatARS(gross)}</td>
              </tr>
              <tr>
                <th scope="row">Descuentos</th>
                <td data-label="Qué incluye" class="text-secondary">Descuentos de línea y generales en ventas cobradas</td>
                <td data-label="Importe" class="col-num text-warn">−${formatARS(discounts)}</td>
              </tr>
              <tr>
                <th scope="row">Devoluciones</th>
                <td data-label="Qué incluye" class="text-secondary">Reintegros parciales o totales registrados hoy</td>
                <td data-label="Importe" class="col-num text-danger">−${formatARS(refundsAmt)}</td>
              </tr>
              <tr style="background-color: var(--stone-50);">
                <th scope="row">Importe neto del día</th>
                <td data-label="Qué incluye" class="text-secondary">Ventas brutas − descuentos − devoluciones</td>
                <td data-label="Importe" class="col-num fw-700">${formatARS(net)}</td>
              </tr>
              <tr>
                <th scope="row">Anulaciones (referencia)</th>
                <td data-label="Qué incluye" class="text-secondary">${cancelledSales.length} venta(s) anulada(s), ya excluidas del bruto</td>
                <td data-label="Importe" class="col-num text-muted">${formatARS(cancelledAmt)}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <section class="card stack" aria-labelledby="quick-cancel-title">
        <div>
          <h2 id="quick-cancel-title" class="card__title">Anular venta de hoy</h2>
          <p class="card__desc">Solo disponible para ventas cobradas del turno sin devoluciones previas.</p>
        </div>

        ${cancellableSales.length === 0
          ? banner({ variant: 'info', body: 'No hay ventas elegibles para anular en esta sesión.' })
          : `<div class="toolbar">
              <div class="field" style="flex: 1 1 18rem;">
                <label class="field__label" for="sum-cancel-sel">Seleccionar venta</label>
                <select id="sum-cancel-sel" class="select">
                  ${cancellableSales.map((s) => `<option value="${s.id}">Venta #${s.id} · ${formatARS(s.total)} · ${escapeHtml(s.operator)}</option>`).join('')}
                </select>
              </div>
              <button type="button" class="btn btn--danger-outline" id="sum-cancel-btn">Anular venta seleccionada</button>
            </div>`}
      </section>
    </div>
  `;

  container.querySelector('#sum-go-cash')?.addEventListener('click', () => navigate('cash'));
  container.querySelector('#sum-go-history')?.addEventListener('click', () => navigate('sales-history'));
  container.querySelector('#sum-cancel-btn')?.addEventListener('click', () => {
    const id = Number(container.querySelector('#sum-cancel-sel').value);
    openConfirmModal({
      title: `Anular Venta #${id}`,
      message: 'La venta quedará marcada como anulada y se repondrá el stock consumido.',
      confirmLabel: 'Confirmar anulación',
      requireReason: true,
      reasonLabel: 'Motivo de cancelación',
      onConfirm: (reason) => {
        const res = cancelSale(id, reason);
        if (!res.ok) return res.error;
        showToast(`Venta #${id} anulada.`, 'ok');
      },
    });
  });
}
