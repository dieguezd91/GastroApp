import {
  getState,
  getSaleDisplayStatus,
  cancelSale,
  registerSaleRefund,
} from '../state/store.js';
import { PAYMENT_METHODS, PAYMENT_METHOD_MAP } from '../data/seed.js';
import { formatARS, formatDateTime, escapeHtml, roundMoney } from '../utils/format.js';
import { icon } from '../utils/icons.js';
import { badge, banner, emptyState, loadingSkeleton, openModal, openConfirmModal } from '../utils/ui.js';
import { showToast } from '../utils/a11y.js';

let filters = {
  from: '',
  to: '',
  operator: 'all',
  registerId: '',
  status: 'all',
  method: 'all',
  query: '',
};

export function renderSalesHistory(container) {
  const state = getState();
  if (state.demo.simulateLoading) {
    container.innerHTML = `
      <div class="page-header"><h1 id="page-heading" tabindex="-1">Historial de ventas</h1></div>
      ${loadingSkeleton(4)}
    `;
    return;
  }
  const operators = [...new Set(state.sales.map((s) => s.operator).filter(Boolean))];

  const sales = state.demo.simulateEmpty
    ? []
    : state.sales.filter((s) => {
        const st = getSaleDisplayStatus(s);
        const saleDate = s.date.slice(0, 10);
        const matchFrom = !filters.from || saleDate >= filters.from;
        const matchTo = !filters.to || saleDate <= filters.to;
        const matchOp = filters.operator === 'all' || s.operator === filters.operator;
        const matchReg = !filters.registerId || String(s.cashRegisterId) === String(filters.registerId).trim();
        const matchStatus = filters.status === 'all' || st.code === filters.status;
        const matchMethod = filters.method === 'all' || s.payments.some((p) => p.method === filters.method);
        const q = filters.query.trim().toLowerCase();
        const matchQ =
          !q ||
          String(s.id).includes(q) ||
          s.operator.toLowerCase().includes(q) ||
          s.items.some((i) => i.productName.toLowerCase().includes(q));
        return matchFrom && matchTo && matchOp && matchReg && matchStatus && matchMethod && matchQ;
      });

  container.innerHTML = `
    <div class="page-header">
      <div>
        <h1 id="page-heading" tabindex="-1">Historial de ventas</h1>
        <p class="page-header__subtitle">Consultá ventas por fecha, operador, caja, medio de pago o estado, revisá eventos y gestioná anulaciones o devoluciones parciales y totales (M12 — implementado).</p>
      </div>
    </div>

    <div class="stack">
      <search class="card card--compact stack stack--sm">
        <div class="form-grid">
          <div class="field">
            <label class="field__label" for="sh-query">N.º venta o producto</label>
            <input id="sh-query" type="search" class="input input--compact" value="${escapeHtml(filters.query)}" placeholder="Ej.: 1045 o Hamburguesa">
          </div>
          <div class="field">
            <label class="field__label" for="sh-from">Desde</label>
            <input id="sh-from" type="date" class="input input--compact" value="${escapeHtml(filters.from)}">
          </div>
          <div class="field">
            <label class="field__label" for="sh-to">Hasta</label>
            <input id="sh-to" type="date" class="input input--compact" value="${escapeHtml(filters.to)}">
          </div>
          <div class="field">
            <label class="field__label" for="sh-op">Operador</label>
            <select id="sh-op" class="select select--compact">
              <option value="all">Todos</option>
              ${operators.map((op) => `<option value="${escapeHtml(op)}" ${filters.operator === op ? 'selected' : ''}>${escapeHtml(op)}</option>`).join('')}
            </select>
          </div>
          <div class="field">
            <label class="field__label" for="sh-reg">Caja (ID)</label>
            <input id="sh-reg" type="number" min="1" class="input input--compact tnum" value="${escapeHtml(filters.registerId)}" placeholder="Ej.: 18">
          </div>
          <div class="field">
            <label class="field__label" for="sh-status">Estado</label>
            <select id="sh-status" class="select select--compact">
              <option value="all" ${filters.status === 'all' ? 'selected' : ''}>Todas</option>
              <option value="Collected" ${filters.status === 'Collected' ? 'selected' : ''}>Cobradas</option>
              <option value="PartiallyRefunded" ${filters.status === 'PartiallyRefunded' ? 'selected' : ''}>Parcialmente devueltas</option>
              <option value="Refunded" ${filters.status === 'Refunded' ? 'selected' : ''}>Devueltas</option>
              <option value="Cancelled" ${filters.status === 'Cancelled' ? 'selected' : ''}>Anuladas</option>
            </select>
          </div>
          <div class="field">
            <label class="field__label" for="sh-method">Medio de pago</label>
            <select id="sh-method" class="select select--compact">
              <option value="all">Todos</option>
              ${PAYMENT_METHODS.map((m) => `<option value="${m.id}" ${filters.method === m.id ? 'selected' : ''}>${escapeHtml(m.label)}</option>`).join('')}
            </select>
          </div>
        </div>
        <div class="flex-wrap-gap">
          <button type="button" class="btn btn--sm" id="sh-clear-filters">Limpiar filtros</button>
          <span class="text-xs text-muted">${sales.length} venta(s) encontradas</span>
        </div>
      </search>

      ${sales.length === 0
        ? emptyState({ iconName: 'receipt', title: 'No hay ventas que coincidan', description: 'Probá limpiando los filtros de búsqueda.' })
        : `<div class="table-wrapper" tabindex="0" role="region" aria-label="Listado de ventas históricas">
            <table class="data-table data-table--stack">
              <thead>
                <tr>
                  <th scope="col">Venta</th>
                  <th scope="col">Fecha</th>
                  <th scope="col">Operador / Caja</th>
                  <th scope="col">Medios de pago</th>
                  <th scope="col">Estado</th>
                  <th scope="col" class="col-num">Total</th>
                  <th scope="col" class="col-actions">Acciones</th>
                </tr>
              </thead>
              <tbody>
                ${sales.map((s) => {
                  const st = getSaleDisplayStatus(s);
                  const refunded = (s.refunds || []).reduce((a, r) => a + r.total, 0);
                  return `
                    <tr>
                      <th scope="row">#${s.id}</th>
                      <td data-label="Fecha">${formatDateTime(s.date)}</td>
                      <td data-label="Operador">${escapeHtml(s.operator)} <span class="text-xs text-muted">· Caja #${s.cashRegisterId}</span></td>
                      <td data-label="Medios">${s.payments.map((p) => escapeHtml(PAYMENT_METHOD_MAP[p.method]?.short || p.method)).join(' + ')}</td>
                      <td data-label="Estado">${badge(st.label, st.variant)}</td>
                      <td data-label="Total" class="col-num fw-700">
                        <div>${formatARS(s.total)}</div>
                        ${refunded > 0 ? `<div class="text-xs text-danger">Dev. -${formatARS(refunded)}</div>` : ''}
                      </td>
                      <td class="col-actions">
                        <button type="button" class="btn btn--sm" data-sale-detail="${s.id}">Ver detalle</button>
                      </td>
                    </tr>
                  `;
                }).join('')}
              </tbody>
            </table>
          </div>`}
    </div>
  `;

  const bindText = (sel, key) => {
    const el = container.querySelector(sel);
    el?.addEventListener('input', (e) => {
      filters[key] = e.target.value;
      const pos = e.target.selectionStart;
      renderSalesHistory(container);
      const next = document.getElementById(el.id);
      if (next) { next.focus(); try { next.setSelectionRange(pos, pos); } catch { /* ignore */ } }
    });
  };
  bindText('#sh-query', 'query');
  bindText('#sh-reg', 'registerId');

  container.querySelector('#sh-from')?.addEventListener('change', (e) => { filters.from = e.target.value; renderSalesHistory(container); });
  container.querySelector('#sh-to')?.addEventListener('change', (e) => { filters.to = e.target.value; renderSalesHistory(container); });
  container.querySelector('#sh-op')?.addEventListener('change', (e) => { filters.operator = e.target.value; renderSalesHistory(container); });
  container.querySelector('#sh-status')?.addEventListener('change', (e) => { filters.status = e.target.value; renderSalesHistory(container); });
  container.querySelector('#sh-method')?.addEventListener('change', (e) => { filters.method = e.target.value; renderSalesHistory(container); });
  container.querySelector('#sh-clear-filters')?.addEventListener('click', () => {
    filters = { from: '', to: '', operator: 'all', registerId: '', status: 'all', method: 'all', query: '' };
    renderSalesHistory(container);
  });

  container.querySelectorAll('[data-sale-detail]').forEach((btn) => {
    btn.addEventListener('click', () => {
      const sale = state.sales.find((s) => s.id === Number(btn.dataset.saleDetail));
      if (sale) openSaleDetailModal(sale);
    });
  });
}

function openSaleDetailModal(sale) {
  const st = getSaleDisplayStatus(sale);
  const refundedTotal = roundMoney((sale.refunds || []).reduce((a, r) => a + r.total, 0));
  const canCancel = st.code === 'Collected';
  const canRefund = sale.status !== 'Cancelled' && refundedTotal < sale.total - 0.01;

  openModal({
    title: `Venta #${sale.id}`,
    subtitle: `${formatDateTime(sale.date)} · Operador: ${sale.operator} · Caja #${sale.cashRegisterId}`,
    size: 'lg',
    bodyHtml: `
      <div class="stack">
        <div class="row-between">
          ${badge(st.label, st.variant)}
          <div class="flex-wrap-gap">
            ${canRefund ? `<button type="button" class="btn btn--sm" id="btn-start-refund">Registrar devolución</button>` : ''}
            ${canCancel ? `<button type="button" class="btn btn--danger-outline btn--sm" id="btn-start-cancel">Anular venta</button>` : ''}
          </div>
        </div>

        <div class="table-wrapper" tabindex="0" role="region" aria-label="Productos de la venta">
          <table class="data-table">
            <thead>
              <tr><th scope="col">Producto</th><th scope="col" class="col-num">Cant.</th><th scope="col" class="col-num">Desc. línea</th><th scope="col" class="col-num">Subtotal</th></tr>
            </thead>
            <tbody>
              ${sale.items.map((it) => `
                <tr>
                  <th scope="row">
                    ${escapeHtml(it.productName)}
                    ${it.note ? `<div class="text-xs text-muted fw-600">Obs.: ${escapeHtml(it.note)}</div>` : ''}
                  </th>
                  <td class="col-num">${it.quantity}</td>
                  <td class="col-num">${it.lineDiscount ? `-${formatARS(it.lineDiscount)}` : '—'}</td>
                  <td class="col-num fw-700">${formatARS(it.lineSubtotal)}</td>
                </tr>
              `).join('')}
            </tbody>
          </table>
        </div>

        <div class="grid-2">
          <div class="card card--compact card--subtle stack stack--sm">
            <h3 class="card__title">Pagos registrados</h3>
            ${sale.payments.map((p) => `
              <div class="summary-row">
                <span>${escapeHtml(PAYMENT_METHOD_MAP[p.method]?.label || p.method)}${p.method === 'Cash' && p.receivedAmount != null ? ` <span class="text-xs text-muted">(recib. ${formatARS(p.receivedAmount)}${p.changeAmount ? ` · vuelto ${formatARS(p.changeAmount)}` : ''})</span>` : ''}</span>
                <strong class="tnum">${formatARS(p.amount)}</strong>
              </div>
            `).join('')}
            ${sale.saleDiscountAmount > 0 ? `<div class="summary-row text-ok"><span>Descuento general</span><strong class="tnum">-${formatARS(sale.saleDiscountAmount)}</strong></div>` : ''}
            <div class="summary-row summary-row--total" style="font-size: var(--text-base);">
              <span>Total</span><span class="tnum">${formatARS(sale.total)}</span>
            </div>
            ${refundedTotal > 0 ? `<div class="summary-row text-danger"><span>Total devuelto</span><strong class="tnum">-${formatARS(refundedTotal)}</strong></div>` : ''}
          </div>

          <div class="card card--compact stack stack--sm">
            <h3 class="card__title">Eventos de la venta</h3>
            <ol class="timeline text-xs">
              <li class="timeline__item">
                <strong>Venta registrada</strong> · ${formatDateTime(sale.date)}<br>
                <span class="text-muted">Por ${escapeHtml(sale.operator)}</span>
              </li>
              ${(sale.refunds || []).map((r) => `
                <li class="timeline__item">
                  <strong>Devolución #${r.id} (${formatARS(r.total)})</strong> · ${formatDateTime(r.date)}<br>
                  <span class="text-muted">${escapeHtml(r.reason)} · Por ${escapeHtml(r.by)}</span>
                  <div class="text-muted">${(r.lines || []).map((l) => `${l.quantity}× ${escapeHtml(l.productName)} (${l.disposition === 'Restock' ? 'Vuelve a stock' : 'Merma'})`).join(', ')}</div>
                </li>
              `).join('')}
              ${sale.cancellation ? `
                <li class="timeline__item">
                  <strong class="text-danger">Venta anulada</strong> · ${formatDateTime(sale.cancellation.date)}<br>
                  <span class="text-muted">${escapeHtml(sale.cancellation.reason)} · Por ${escapeHtml(sale.cancellation.by)}</span>
                </li>
              ` : ''}
            </ol>
          </div>
        </div>
      </div>
    `,
    footerHtml: `<button type="button" class="btn btn--primary" data-modal-close>Cerrar</button>`,
    onMount(dlg) {
      dlg.querySelector('#btn-start-cancel')?.addEventListener('click', () => {
        dlg.close();
        openConfirmModal({
          title: `Anular Venta #${sale.id}`,
          message: 'Se anulará la venta y se repondrá el stock consumido registrado para sus recetas.',
          confirmLabel: 'Confirmar anulación',
          requireReason: true,
          reasonLabel: 'Motivo de cancelación',
          onConfirm: (reason) => {
            const res = cancelSale(sale.id, reason);
            if (!res.ok) return res.error;
            showToast(`Venta #${sale.id} anulada y stock restaurado.`, 'ok');
          },
        });
      });

      dlg.querySelector('#btn-start-refund')?.addEventListener('click', () => {
        dlg.close();
        openRefundModal(sale);
      });
    },
  });
}

function openRefundModal(sale) {
  const state = getState();
  const hasSnapshot = (sale.stockConsumptions || []).length > 0;
  const lineDrafts = sale.items.map((it) => {
    const alreadyQty = (sale.refunds || []).reduce(
      (acc, r) => acc + (r.lines || []).filter((l) => l.lineId === it.lineId).reduce((a, l) => a + Number(l.quantity || 0), 0),
      0
    );
    const availableQty = Math.max(0, it.quantity - alreadyQty);
    const canRestock = hasSnapshot && state.recipes.some((r) => r.name.toLowerCase() === it.productName.toLowerCase());
    return {
      lineId: it.lineId,
      productName: it.productName,
      soldQty: it.quantity,
      alreadyQty,
      availableQty,
      canRestock,
      unitEffective: roundMoney((it.lineSubtotal / it.quantity) * (sale.subtotal > 0 ? sale.total / sale.subtotal : 1)),
      refundQty: 0,
      disposition: canRestock ? 'Restock' : 'Waste',
    };
  });

  const payDrafts = sale.payments.map((p) => {
    const prevRef = roundMoney(
      (sale.refunds || []).reduce(
        (acc, r) => acc + (r.payments || []).filter((rp) => rp.method === p.method).reduce((a, rp) => a + rp.amount, 0),
        0
      )
    );
    return {
      method: p.method,
      label: PAYMENT_METHOD_MAP[p.method]?.label || p.method,
      paid: p.amount,
      prevRefunded: prevRef,
      available: roundMoney(Math.max(0, p.amount - prevRef)),
      refundAmount: 0,
    };
  });

  let reason = '';
  let confirmed = false;
  let inlineError = '';

  const calculateProportional = () => {
    const target = roundMoney(lineDrafts.reduce((a, l) => a + l.refundQty * l.unitEffective, 0));
    let rem = target;
    for (const pd of payDrafts) {
      const alloc = roundMoney(Math.min(pd.available, rem));
      pd.refundAmount = alloc;
      rem = roundMoney(rem - alloc);
    }
    return target;
  };

  openModal({
    title: `Registrar devolución · Venta #${sale.id}`,
    subtitle: 'Seleccioná cantidades por ítem, destino del stock y cómo se reintegra entre los medios cobrados.',
    size: 'lg',
    lightDismiss: false,
    bodyHtml: '<div id="refund-modal-body"></div>',
    footerHtml: `
      <button type="button" class="btn" data-modal-close>Cancelar</button>
      <button type="button" class="btn btn--danger" id="ref-submit-btn">Confirmar devolución</button>
    `,
    onMount(dlg) {
      const body = dlg.querySelector('#refund-modal-body');
      const submitBtn = dlg.querySelector('#ref-submit-btn');

      const renderRefund = () => {
        const totalLinesCalc = roundMoney(lineDrafts.reduce((a, l) => a + l.refundQty * l.unitEffective, 0));
        const totalPayRefund = roundMoney(payDrafts.reduce((a, p) => a + Number(p.refundAmount || 0), 0));

        body.innerHTML = `
          <div class="stack">
            ${inlineError ? banner({ variant: 'danger', body: escapeHtml(inlineError) }) : ''}

            <div class="stack stack--sm">
              <div class="row-between">
                <h3 class="card__title">1. Ítems a devolver</h3>
                <button type="button" class="btn btn--sm" id="ref-calc-btn">${icon('refresh', 14)} Calcular importe (${formatARS(totalLinesCalc)})</button>
              </div>
              <div class="table-wrapper" tabindex="0" role="region" aria-label="Ítems disponibles para devolver">
                <table class="data-table data-table--stack">
                  <thead>
                    <tr>
                      <th scope="col">Producto</th>
                      <th scope="col" class="col-num">Disp.</th>
                      <th scope="col">Cant. a devolver</th>
                      <th scope="col">Destino de stock</th>
                    </tr>
                  </thead>
                  <tbody>
                    ${lineDrafts.map((l, idx) => `
                      <tr>
                        <th scope="row">
                          <div>${escapeHtml(l.productName)}</div>
                          <div class="text-xs text-muted fw-600">${formatARS(l.unitEffective)} neto c/u · Vendido ${l.soldQty}${l.alreadyQty ? ` · Ya dev. ${l.alreadyQty}` : ''}</div>
                        </th>
                        <td data-label="Disponible" class="col-num fw-700">${l.availableQty}</td>
                        <td data-label="Devolver">
                          <input type="number" min="0" max="${l.availableQty}" step="1" class="input input--compact tnum" style="max-inline-size: 6rem;" data-ref-qty="${idx}" value="${l.refundQty}" ${l.availableQty === 0 ? 'disabled' : ''} aria-label="Cantidad a devolver de ${escapeHtml(l.productName)}">
                        </td>
                        <td data-label="Destino">
                          ${l.canRestock
                            ? `<select class="select select--compact" data-ref-disp="${idx}" ${l.availableQty === 0 ? 'disabled' : ''} aria-label="Destino de stock para ${escapeHtml(l.productName)}">
                                <option value="Restock" ${l.disposition === 'Restock' ? 'selected' : ''}>Vuelve a stock</option>
                                <option value="Waste" ${l.disposition === 'Waste' ? 'selected' : ''}>Merma</option>
                              </select>`
                            : `<span class="text-xs text-muted fw-600">Merma (sin registro de consumo)</span>`}
                        </td>
                      </tr>
                    `).join('')}
                  </tbody>
                </table>
              </div>
            </div>

            <div class="stack stack--sm">
              <h3 class="card__title">2. Reintegro por medio de pago</h3>
              <div class="table-wrapper" tabindex="0" role="region" aria-label="Medios de pago disponibles para reintegro">
                <table class="data-table data-table--stack">
                  <thead>
                    <tr>
                      <th scope="col">Medio</th>
                      <th scope="col" class="col-num">Cobrado</th>
                      <th scope="col" class="col-num">Devuelto</th>
                      <th scope="col" class="col-num">Disponible</th>
                      <th scope="col">Importe a devolver ($)</th>
                    </tr>
                  </thead>
                  <tbody>
                    ${payDrafts.map((p, idx) => `
                      <tr>
                        <th scope="row">${escapeHtml(p.label)}</th>
                        <td data-label="Cobrado" class="col-num">${formatARS(p.paid)}</td>
                        <td data-label="Devuelto" class="col-num">${formatARS(p.prevRefunded)}</td>
                        <td data-label="Disponible" class="col-num fw-700">${formatARS(p.available)}</td>
                        <td data-label="Reintegro">
                          <input type="number" min="0" max="${p.available}" step="any" class="input input--compact tnum" style="max-inline-size: 8.5rem;" data-ref-pay="${idx}" value="${p.refundAmount}" ${p.available <= 0 ? 'disabled' : ''} aria-label="Importe a devolver en ${escapeHtml(p.label)}">
                        </td>
                      </tr>
                    `).join('')}
                  </tbody>
                </table>
              </div>
              <div class="card card--compact card--subtle row-between">
                <span class="text-sm fw-700">Total a reintegrar</span>
                <span class="fw-700 tnum" id="ref-total-pay" style="font-size: var(--text-lg);">${formatARS(totalPayRefund)}</span>
              </div>
            </div>

            <div class="field">
              <label class="field__label" for="ref-reason">Motivo de la devolución (obligatorio) <span class="field__req" aria-hidden="true">*</span></label>
              <input id="ref-reason" type="text" class="input" value="${escapeHtml(reason)}" required placeholder="Ej.: Producto con temperatura incorrecta">
            </div>

            <label class="check-field">
              <input type="checkbox" id="ref-confirm" ${confirmed ? 'checked' : ''}>
              <span>Confirmo registrar esta devolución (el efectivo devuelto impacta automáticamente en la caja abierta).</span>
            </label>
          </div>
        `;

        body.querySelectorAll('[data-ref-qty]').forEach((inp) => {
          const syncQty = (clampInput) => {
            const idx = Number(inp.dataset.refQty);
            const max = lineDrafts[idx].availableQty;
            const parsed = Math.max(0, Math.min(max, Math.floor(Number(inp.value || 0))));
            lineDrafts[idx].refundQty = parsed;
            if (clampInput && String(parsed) !== inp.value) inp.value = String(parsed);
            const nextCalc = roundMoney(lineDrafts.reduce((a, l) => a + l.refundQty * l.unitEffective, 0));
            const calcBtn = body.querySelector('#ref-calc-btn');
            if (calcBtn) calcBtn.innerHTML = `${icon('refresh', 14)} Calcular importe (${formatARS(nextCalc)})`;
          };
          inp.addEventListener('input', () => syncQty(false));
          inp.addEventListener('change', () => syncQty(true));
        });

        body.querySelectorAll('[data-ref-disp]').forEach((sel) => {
          sel.addEventListener('change', (e) => {
            lineDrafts[Number(sel.dataset.refDisp)].disposition = e.target.value;
          });
        });

        body.querySelector('#ref-calc-btn').addEventListener('click', () => {
          calculateProportional();
          inlineError = '';
          renderRefund();
        });

        body.querySelectorAll('[data-ref-pay]').forEach((inp) => {
          inp.addEventListener('input', (e) => {
            payDrafts[Number(inp.dataset.refPay)].refundAmount = Math.max(0, roundMoney(e.target.value || 0));
            const nextSum = roundMoney(payDrafts.reduce((a, p) => a + Number(p.refundAmount || 0), 0));
            const totEl = body.querySelector('#ref-total-pay');
            if (totEl) totEl.textContent = formatARS(nextSum);
          });
        });

        body.querySelector('#ref-reason').addEventListener('input', (e) => { reason = e.target.value; });
        body.querySelector('#ref-confirm').addEventListener('change', (e) => { confirmed = e.target.checked; });
      };

      submitBtn.addEventListener('click', () => {
        if (!confirmed) {
          inlineError = 'Marcá la casilla de confirmación antes de registrar la devolución.';
          renderRefund();
          return;
        }
        const res = registerSaleRefund(sale.id, {
          lines: lineDrafts
            .filter((l) => l.refundQty > 0)
            .map((l) => ({ lineId: l.lineId, productName: l.productName, quantity: l.refundQty, disposition: l.disposition })),
          payments: payDrafts
            .filter((p) => p.refundAmount > 0)
            .map((p) => ({ method: p.method, amount: p.refundAmount })),
          reason,
        });
        if (!res.ok) {
          inlineError = res.error;
          renderRefund();
          return;
        }
        dlg.close('ok');
        showToast(`Devolución #${res.refund.id} registrada en Venta #${sale.id}.`, 'ok');
      });

      renderRefund();
    },
  });
}
