import {
  getState,
  getExpectedCash,
  getCashMovementsFor,
  getCashPaymentSummary,
} from '../state/store.js';
import { CASH_MOVEMENT_LABELS } from '../data/seed.js';
import { formatARS, formatDateTime, escapeHtml, roundMoney } from '../utils/format.js';
import { icon } from '../utils/icons.js';
import { badge, emptyState, loadingSkeleton, openModal } from '../utils/ui.js';

let filters = { status: 'all', from: '', to: '' };

export function renderCashHistory(container, navigate) {
  const state = getState();
  if (state.demo.simulateLoading) {
    container.innerHTML = `
      <div class="page-header"><h1 id="page-heading" tabindex="-1">Historial de cajas</h1></div>
      ${loadingSkeleton(4)}
    `;
    return;
  }
  const registers = state.demo.simulateEmpty
    ? []
    : state.cashRegisters.filter((r) => {
        const d = r.openedAt.slice(0, 10);
        const matchStatus = filters.status === 'all' || r.status === filters.status;
        const matchFrom = !filters.from || d >= filters.from;
        const matchTo = !filters.to || d <= filters.to;
        return matchStatus && matchFrom && matchTo;
      });

  container.innerHTML = `
    <div class="page-header">
      <div>
        <h1 id="page-heading" tabindex="-1">Historial de cajas</h1>
        <p class="page-header__subtitle">Consulta de solo lectura de sesiones anteriores, arqueos, movimientos, cobros por medio de pago y resumen diario asociado.</p>
      </div>
      <div class="page-header__actions">
        <button type="button" class="btn" id="ch-back-cash">${icon('cash', 17)} Ir a caja actual</button>
      </div>
    </div>

    <div class="stack">
      <search class="card card--compact stack stack--sm">
        <div class="form-grid">
          <div class="field">
            <label class="field__label" for="ch-from">Apertura desde</label>
            <input id="ch-from" type="date" class="input input--compact" value="${escapeHtml(filters.from)}">
          </div>
          <div class="field">
            <label class="field__label" for="ch-to">Apertura hasta</label>
            <input id="ch-to" type="date" class="input input--compact" value="${escapeHtml(filters.to)}">
          </div>
          <div class="field">
            <label class="field__label" for="ch-status">Estado de sesión</label>
            <select id="ch-status" class="select select--compact">
              <option value="all" ${filters.status === 'all' ? 'selected' : ''}>Todas</option>
              <option value="Open" ${filters.status === 'Open' ? 'selected' : ''}>Abiertas</option>
              <option value="Closed" ${filters.status === 'Closed' ? 'selected' : ''}>Cerradas</option>
            </select>
          </div>
        </div>
        <div class="flex-wrap-gap">
          <button type="button" class="btn btn--sm" id="ch-clear">Limpiar filtros</button>
          <span class="text-xs text-muted">${registers.length} sesión(es)</span>
        </div>
      </search>

      ${registers.length === 0
        ? emptyState({ iconName: 'history', title: 'Sin sesiones para mostrar', description: 'Ajustá los filtros para consultar otras cajas.' })
        : `<div class="table-wrapper" tabindex="0" role="region" aria-label="Listado de sesiones de caja">
            <table class="data-table data-table--stack">
              <thead>
                <tr>
                  <th scope="col">Sesión</th>
                  <th scope="col">Apertura</th>
                  <th scope="col">Cierre</th>
                  <th scope="col">Estado</th>
                  <th scope="col" class="col-num">Fondo inicial</th>
                  <th scope="col" class="col-num">Esperado</th>
                  <th scope="col" class="col-num">Contado</th>
                  <th scope="col" class="col-num">Diferencia</th>
                  <th scope="col" class="col-actions">Acciones</th>
                </tr>
              </thead>
              <tbody>
                ${registers.map((r) => {
                  const exp = r.status === 'Open' ? getExpectedCash(r.id) : r.expectedAmountSnapshot;
                  const diff = r.differenceSnapshot;
                  return `
                    <tr>
                      <th scope="row">Caja #${r.id}</th>
                      <td data-label="Apertura">${formatDateTime(r.openedAt)}</td>
                      <td data-label="Cierre">${r.closedAt ? formatDateTime(r.closedAt) : 'En curso'}</td>
                      <td data-label="Estado">${badge(r.status === 'Open' ? 'Abierta' : 'Cerrada', r.status === 'Open' ? 'ok' : 'neutral')}</td>
                      <td data-label="Fondo inicial" class="col-num">${formatARS(r.initialAmount)}</td>
                      <td data-label="Esperado" class="col-num">${formatARS(exp)}</td>
                      <td data-label="Contado" class="col-num">${r.countedAmount != null ? formatARS(r.countedAmount) : '—'}</td>
                      <td data-label="Diferencia" class="col-num fw-700 ${diff == null ? '' : diff === 0 ? 'text-ok' : diff < 0 ? 'text-danger' : ''}">
                        ${diff == null ? '—' : diff === 0 ? 'Exacto' : formatARS(diff)}
                      </td>
                      <td class="col-actions">
                        <button type="button" class="btn btn--sm" data-view-reg="${r.id}">Ver detalle</button>
                      </td>
                    </tr>
                  `;
                }).join('')}
              </tbody>
            </table>
          </div>`}
    </div>
  `;

  container.querySelector('#ch-back-cash')?.addEventListener('click', () => navigate('cash'));
  container.querySelector('#ch-from')?.addEventListener('change', (e) => { filters.from = e.target.value; renderCashHistory(container, navigate); });
  container.querySelector('#ch-to')?.addEventListener('change', (e) => { filters.to = e.target.value; renderCashHistory(container, navigate); });
  container.querySelector('#ch-status')?.addEventListener('change', (e) => { filters.status = e.target.value; renderCashHistory(container, navigate); });
  container.querySelector('#ch-clear')?.addEventListener('click', () => {
    filters = { status: 'all', from: '', to: '' };
    renderCashHistory(container, navigate);
  });

  container.querySelectorAll('[data-view-reg]').forEach((btn) => {
    btn.addEventListener('click', () => {
      const reg = state.cashRegisters.find((r) => r.id === Number(btn.dataset.viewReg));
      if (reg) openCashDetailModal(reg);
    });
  });
}

function openCashDetailModal(reg) {
  const state = getState();
  const moves = getCashMovementsFor(reg.id);
  const pay = getCashPaymentSummary(reg.id);
  const sessionSales = state.sales.filter((s) => s.cashRegisterId === reg.id && s.status !== 'Cancelled');
  const totalSold = roundMoney(sessionSales.reduce((a, s) => a + s.total, 0));
  const prodCounts = new Map();
  for (const s of sessionSales) {
    for (const it of s.items) {
      prodCounts.set(it.productName, (prodCounts.get(it.productName) || 0) + it.quantity);
    }
  }
  const topProd = [...prodCounts.entries()].sort((a, b) => b[1] - a[1])[0];

  openModal({
    title: `Detalle de Caja #${reg.id}`,
    subtitle: `Apertura: ${formatDateTime(reg.openedAt)} · ${reg.closedAt ? `Cierre: ${formatDateTime(reg.closedAt)}` : 'Sesión abierta'}`,
    size: 'lg',
    bodyHtml: `
      <div class="stack">
        <div class="grid-kpi" style="grid-template-columns: repeat(auto-fit, minmax(10rem, 1fr));">
          <div class="card card--compact card--subtle"><p class="text-xs text-muted">Fondo inicial</p><p class="fw-700 tnum">${formatARS(reg.initialAmount)}</p></div>
          <div class="card card--compact card--subtle"><p class="text-xs text-muted">Esperado</p><p class="fw-700 tnum">${formatARS(reg.status === 'Open' ? getExpectedCash(reg.id) : reg.expectedAmountSnapshot)}</p></div>
          <div class="card card--compact card--subtle"><p class="text-xs text-muted">Contado</p><p class="fw-700 tnum">${reg.countedAmount != null ? formatARS(reg.countedAmount) : 'Pendiente'}</p></div>
          <div class="card card--compact card--subtle"><p class="text-xs text-muted">Diferencia</p><p class="fw-700 tnum">${reg.differenceSnapshot != null ? formatARS(reg.differenceSnapshot) : '—'}</p></div>
        </div>

        <div class="card card--compact stack stack--sm">
          <h3 class="card__title">Resumen asociado</h3>
          <div class="grid-kpi" style="grid-template-columns: repeat(auto-fit, minmax(11rem, 1fr));">
            <div><p class="text-xs text-muted">Ventas cobradas</p><p class="fw-700 tnum">${sessionSales.length} (${formatARS(totalSold)})</p></div>
            <div><p class="text-xs text-muted">Producto más vendido</p><p class="fw-700">${topProd ? `${escapeHtml(topProd[0])} (${topProd[1]} u.)` : 'Sin ventas'}</p></div>
            <div><p class="text-xs text-muted">Responsables</p><p class="text-sm">${escapeHtml(reg.openedBy)}${reg.closedBy ? ` / ${escapeHtml(reg.closedBy)}` : ''}</p></div>
          </div>
        </div>

        ${reg.countRecord ? `
          <div class="card card--compact stack stack--sm">
            <h3 class="card__title">Arqueo registrado</h3>
            <p class="text-xs text-secondary">Contado por ${escapeHtml(reg.countRecord.countedBy)} el ${formatDateTime(reg.countRecord.countedAt)}</p>
            <div class="flex-wrap-gap">
              ${reg.countRecord.denominations.map((d) => badge(`${d.qty} × ${formatARS(d.value)}`, 'neutral')).join('')}
            </div>
            ${reg.countRecord.differenceReason ? `<p class="text-sm"><strong>Motivo diferencia:</strong> ${escapeHtml(reg.countRecord.differenceReason)}</p>` : ''}
          </div>
        ` : ''}

        <div class="stack stack--sm">
          <h3 class="card__title">Cobros por medio de pago</h3>
          <div class="table-wrapper" tabindex="0" role="region" aria-label="Cobros por medio de pago de caja">
            <table class="data-table">
              <thead><tr><th scope="col">Medio</th><th scope="col" class="col-num">Registrado</th><th scope="col" class="col-num">Devuelto</th><th scope="col" class="col-num">Neto</th></tr></thead>
              <tbody>
                ${pay.rows.map((r) => `<tr><th scope="row">${escapeHtml(r.label)}</th><td class="col-num">${formatARS(r.registered)}</td><td class="col-num">${formatARS(r.refunded)}</td><td class="col-num fw-700">${formatARS(r.net)}</td></tr>`).join('')}
              </tbody>
            </table>
          </div>
        </div>

        <div class="stack stack--sm">
          <h3 class="card__title">Movimientos de efectivo (${moves.length})</h3>
          ${moves.length === 0 ? '<p class="text-sm text-muted">Sin movimientos registrados.</p>' : `
            <div class="table-wrapper" tabindex="0" role="region" aria-label="Movimientos de la sesión">
              <table class="data-table">
                <thead><tr><th scope="col">Fecha</th><th scope="col">Tipo</th><th scope="col">Motivo</th><th scope="col" class="col-num">Monto</th></tr></thead>
                <tbody>
                  ${moves.map((m) => `<tr><td>${formatDateTime(m.date)}</td><td>${escapeHtml(CASH_MOVEMENT_LABELS[m.type] || m.type)}</td><td>${escapeHtml(m.reason)}</td><td class="col-num fw-700">${formatARS(m.amount)}</td></tr>`).join('')}
                </tbody>
              </table>
            </div>
          `}
        </div>
      </div>
    `,
    footerHtml: `<button type="button" class="btn btn--primary" data-modal-close>Cerrar</button>`,
  });
}
