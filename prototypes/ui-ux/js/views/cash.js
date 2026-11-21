import {
  getState,
  getOpenCashRegister,
  getCanonicalCashRegister,
  getExpectedCash,
  getCashMovementsFor,
  getCashPaymentSummary,
  openCashRegister,
  addManualCashMovement,
  closeCashRegister,
} from '../state/store.js';
import { AR_DENOMINATIONS, CASH_MOVEMENT_LABELS } from '../data/seed.js';
import { formatARS, formatDateTime, formatTime, escapeHtml, roundMoney } from '../utils/format.js';
import { icon } from '../utils/icons.js';
import { badge, banner, kpiCard, emptyState, loadingSkeleton, openModal } from '../utils/ui.js';
import { showToast } from '../utils/a11y.js';

// Persistent local arqueo draft during session
let arqueoDraft = {
  registerId: null,
  versionSnapshot: null,
  rows: AR_DENOMINATIONS.map((val) => ({ value: val, qty: 0 })),
  differenceReason: '',
  staleWarning: false,
};

function syncArqueoDraft(openReg) {
  if (!openReg) return;
  if (arqueoDraft.registerId !== openReg.id) {
    const isSeedSession = openReg.id === 18;
    arqueoDraft = {
      registerId: openReg.id,
      versionSnapshot: openReg.movementVersion,
      rows: isSeedSession
        ? [
            { value: 20000, qty: 1 },
            { value: 10000, qty: 3 },
            { value: 2000, qty: 3 },
            { value: 1000, qty: 4 },
            { value: 500, qty: 0 },
            { value: 200, qty: 2 },
            { value: 100, qty: 0 },
          ]
        : AR_DENOMINATIONS.map((val) => ({ value: val, qty: 0 })),
      differenceReason: '',
      staleWarning: false,
    };
  }
}

export function renderCash(container, navigate) {
  const state = getState();
  const openReg = getOpenCashRegister();
  const canonicalReg = getCanonicalCashRegister();

  if (state.demo.simulateLoading) {
    container.innerHTML = `
      <div class="page-header">
        <div>
          <h1 id="page-heading" tabindex="-1">Caja diaria</h1>
          <p class="page-header__subtitle">Cargando sesión de caja y movimientos…</p>
        </div>
      </div>
      ${loadingSkeleton(4)}
    `;
    return;
  }

  syncArqueoDraft(openReg);
  const expected = openReg ? getExpectedCash(openReg.id) : (canonicalReg?.expectedAmountSnapshot ?? 0);
  const movements = canonicalReg ? getCashMovementsFor(canonicalReg.id) : [];
  const paymentSummary = getCashPaymentSummary(canonicalReg?.id);
  const cashInflows = movements
    .filter((m) => m.type === 'Sale' || m.type === 'Income')
    .reduce((a, m) => a + m.amount, 0);

  const isStale = Boolean(
    openReg && (state.demo.simulateStaleArqueo || arqueoDraft.staleWarning || arqueoDraft.versionSnapshot !== openReg.movementVersion)
  );
  const countedTotal = roundMoney(arqueoDraft.rows.reduce((a, r) => a + Number(r.value || 0) * Number(r.qty || 0), 0));
  const diff = roundMoney(countedTotal - expected);
  const diffMeta =
    Math.abs(diff) < 0.01
      ? { label: 'Exacto', variant: 'ok' }
      : diff > 0
        ? { label: `Sobrante (+${formatARS(diff)})`, variant: 'info' }
        : { label: `Faltante (${formatARS(diff)})`, variant: 'danger' };

  container.innerHTML = `
    <div class="page-header">
      <div>
        <div class="page-header__title-row">
          <h1 id="page-heading" tabindex="-1">Caja diaria</h1>
          ${openReg ? badge(`Abierta · Sesión #${openReg.id}`, 'ok', 'checkCircle') : badge('Cerrada', 'danger', 'alertOctagon')}
        </div>
        <p class="page-header__subtitle">Controlá el efectivo disponible, registrá movimientos manuales y cerrá la jornada con arqueo por denominación.</p>
      </div>
      <div class="page-header__actions">
        <button type="button" class="btn" id="cash-go-history">
          ${icon('history', 18)}
          <span>Historial de cajas</span>
        </button>
      </div>
    </div>

    <div class="stack stack--lg">
      ${!openReg ? `
        <!-- Open Cash Register Card -->
        <section class="card stack" aria-labelledby="open-cash-title">
          <div>
            <h2 id="open-cash-title" class="card__title">Abrir nueva sesión de caja</h2>
            <p class="card__desc">Ingresá el fondo inicial en efectivo con el que arranca el turno.</p>
          </div>
          <div id="open-cash-err"></div>
          <form id="open-cash-form" class="toolbar" novalidate>
            <div class="field" style="flex: 0 1 18rem;">
              <label class="field__label" for="initial-amount">Monto inicial ($) <span class="field__req" aria-hidden="true">*</span></label>
              <input id="initial-amount" name="initialAmount" type="number" min="0" step="any" class="input tnum" value="45000" required data-error="initial-amount-err">
              <span id="initial-amount-err" class="field__error">${icon('alertOctagon', 14)} Ingresá un monto inicial válido (0 o mayor).</span>
            </div>
            <button type="submit" class="btn btn--collect btn--lg">
              ${icon('checkCircle', 18)}
              <span>Abrir caja</span>
            </button>
          </form>
        </section>

        ${canonicalReg ? `
          <section class="card stack" aria-labelledby="last-closed-title">
            <div class="row-between">
              <div>
                <h2 id="last-closed-title" class="card__title">Última caja cerrada — Sesión #${canonicalReg.id}</h2>
                <p class="card__desc">Cerrada el ${formatDateTime(canonicalReg.closedAt)} por ${escapeHtml(canonicalReg.closedBy || 'Administrador')}</p>
              </div>
              ${badge(
                canonicalReg.differenceSnapshot === 0 ? 'Arqueo exacto' : canonicalReg.differenceSnapshot > 0 ? `Sobrante ${formatARS(canonicalReg.differenceSnapshot)}` : `Faltante ${formatARS(canonicalReg.differenceSnapshot)}`,
                canonicalReg.differenceSnapshot === 0 ? 'ok' : canonicalReg.differenceSnapshot > 0 ? 'info' : 'danger'
              )}
            </div>
            <div class="grid-kpi">
              ${kpiCard({ label: 'Fondo inicial', value: formatARS(canonicalReg.initialAmount) })}
              ${kpiCard({ label: 'Esperado en caja', value: formatARS(canonicalReg.expectedAmountSnapshot) })}
              ${kpiCard({ label: 'Total contado', value: formatARS(canonicalReg.countedAmount) })}
            </div>
            ${canonicalReg.countRecord?.differenceReason ? `<p class="text-sm text-secondary"><strong>Motivo de diferencia:</strong> ${escapeHtml(canonicalReg.countRecord.differenceReason)}</p>` : ''}
            <div>
              <button type="button" class="btn btn--sm" id="cash-go-summary">${icon('summary', 16)} Ver resumen del día</button>
            </div>
          </section>
        ` : ''}
      ` : `
        <!-- Open Session KPI Strip -->
        <section class="grid-kpi" aria-label="Indicadores de la caja abierta">
          ${kpiCard({
            label: 'Apertura',
            value: formatTime(openReg.openedAt),
            meta: `Fondo inicial: ${formatARS(openReg.initialAmount)} · ${openReg.openedBy}`,
          })}
          ${kpiCard({
            label: 'Efectivo ingresado',
            value: formatARS(cashInflows),
            meta: 'Ventas en efectivo + ingresos manuales',
          })}
          ${kpiCard({
            label: 'Esperado en caja',
            value: formatARS(expected),
            meta: 'Inicial + ventas/ingresos − gastos/retiros/devoluciones',
            badgeHtml: badge('En vivo', 'ok'),
          })}
          ${kpiCard({
            label: 'Total cobros netos',
            value: formatARS(paymentSummary.totalNet),
            meta: 'Todos los medios de pago de la sesión',
          })}
        </section>

        <!-- Primary Workspace: Manual Movements + Arqueo & Close -->
        <div class="grid-2">
          <!-- Manual Cash Movement Form -->
          <section class="card stack" aria-labelledby="cash-move-title">
            <div>
              <h2 id="cash-move-title" class="card__title">Registrar movimiento de efectivo</h2>
              <p class="card__desc">Ingresos, gastos menores o retiros auditados sobre la sesión abierta.</p>
            </div>
            <div id="cash-move-err"></div>
            <form id="cash-move-form" class="stack" novalidate>
              <div class="form-grid">
                <div class="field">
                  <label class="field__label" for="move-type">Tipo de movimiento</label>
                  <select id="move-type" name="type" class="select">
                    <option value="Income">Ingreso (+)</option>
                    <option value="Expense">Gasto (−)</option>
                    <option value="Withdrawal">Retiro (−)</option>
                  </select>
                </div>
                <div class="field">
                  <label class="field__label" for="move-amount">Monto ($) <span class="field__req" aria-hidden="true">*</span></label>
                  <input id="move-amount" name="amount" type="number" min="1" step="any" class="input tnum" required data-error="move-amount-err" placeholder="Ej.: 5000">
                  <span id="move-amount-err" class="field__error">${icon('alertOctagon', 14)} Ingresá un monto mayor a cero.</span>
                </div>
              </div>
              <div class="field">
                <label class="field__label" for="move-reason">Motivo (obligatorio) <span class="field__req" aria-hidden="true">*</span></label>
                <input id="move-reason" name="reason" type="text" class="input" required minlength="3" data-error="move-reason-err" placeholder="Ej.: Compra de hielo, refuerzo de cambio, retiro a caja fuerte">
                <span id="move-reason-err" class="field__error">${icon('alertOctagon', 14)} Indicá el motivo del movimiento.</span>
              </div>
              <div class="flex-wrap-gap">
                <button type="submit" class="btn btn--primary">
                  ${icon('plus', 17)}
                  <span>Registrar movimiento</span>
                </button>
              </div>
            </form>
          </section>

          <!-- Arqueo y cierre de caja -->
          <section class="card stack" aria-labelledby="arqueo-title">
            <div class="row-between">
              <div>
                <h2 id="arqueo-title" class="card__title">Arqueo y cierre de caja</h2>
                <p class="card__desc">Contá los billetes físicos por denominación para verificar el saldo antes de cerrar.</p>
              </div>
              ${badge(diffMeta.label, diffMeta.variant)}
            </div>

            ${isStale ? banner({
              variant: 'warn',
              title: 'Saldo esperado desactualizado',
              body: 'Se registraron movimientos nuevos desde que empezaste este arqueo. Actualizá el saldo esperado antes de confirmar el cierre.',
              actionHtml: `<button type="button" class="btn btn--sm" id="btn-refresh-arqueo">${icon('refresh', 14)} Actualizar saldo esperado</button>`,
            }) : ''}

            <div class="stack stack--sm" aria-label="Conteo de billetes por denominación">
              <div class="denom-row text-xs fw-700 text-muted" style="border-block-end: 2px solid var(--border-subtle);">
                <span>Denominación</span>
                <span>Cantidad</span>
                <span style="text-align: end;">Subtotal</span>
                <span></span>
              </div>
              ${arqueoDraft.rows.map((row, idx) => `
                <div class="denom-row">
                  <span class="fw-600 tnum">${formatARS(row.value)}</span>
                  <input
                    type="number"
                    min="0"
                    step="1"
                    class="input input--compact tnum"
                    data-denom-qty="${idx}"
                    value="${row.qty}"
                    aria-label="Cantidad de billetes de ${formatARS(row.value)}"
                  >
                  <span class="denom-row__sub fw-700 tnum" style="text-align: end;">${formatARS(Number(row.value) * Number(row.qty || 0))}</span>
                  <button type="button" class="btn btn--ghost btn--icon" data-remove-denom="${idx}" aria-label="Quitar denominación ${formatARS(row.value)}">
                    ${icon('trash', 14)}
                  </button>
                </div>
              `).join('')}

              <div class="flex-wrap-gap mt-2">
                <button type="button" class="btn btn--sm" id="btn-add-denom">${icon('plus', 14)} Agregar denominación</button>
                <button type="button" class="btn btn--ghost btn--sm" id="btn-fill-exact">Simular conteo exacto</button>
              </div>
            </div>

            <div class="card card--compact card--subtle stack stack--sm">
              <div class="summary-row">
                <span class="text-secondary">Total contado</span>
                <span class="fw-700 tnum">${formatARS(countedTotal)}</span>
              </div>
              <div class="summary-row">
                <span class="text-secondary">Esperado en caja</span>
                <span class="fw-700 tnum">${formatARS(expected)}</span>
              </div>
              <div class="summary-row summary-row--total" style="font-size: var(--text-base);">
                <span>Diferencia</span>
                <span class="tnum ${Math.abs(diff) < 0.01 ? 'text-ok' : diff > 0 ? '' : 'text-danger'}">${diffMeta.label}</span>
              </div>
            </div>

            ${Math.abs(diff) >= 0.01 ? `
              <div class="field">
                <label class="field__label" for="arqueo-diff-reason">Motivo de la diferencia <span class="field__req" aria-hidden="true">*</span></label>
                <input id="arqueo-diff-reason" type="text" class="input" value="${escapeHtml(arqueoDraft.differenceReason)}" placeholder="Ej.: Redondeo de cambio chico durante el almuerzo">
              </div>
            ` : ''}

            <button type="button" class="btn btn--danger btn--lg btn--block" id="btn-review-close">
              ${icon('clipboard', 18)}
              <span>Revisar cierre de caja</span>
            </button>
          </section>
        </div>
      `}

      <!-- Payment Methods Breakdown -->
      <section class="card stack" aria-labelledby="cash-pay-title">
        <div class="row-between">
          <div>
            <h2 id="cash-pay-title" class="card__title">Cobros registrados por medio de pago</h2>
            <p class="card__desc">Desglose de la sesión #${canonicalReg?.id || '—'} separando cobros registrados, devoluciones y neto.</p>
          </div>
          ${badge(paymentSummary.status === 'Complete' ? 'Registro completo' : 'Sin sesión', paymentSummary.status === 'Complete' ? 'ok' : 'neutral', 'checkCircle')}
        </div>

        <div class="table-wrapper" tabindex="0" role="region" aria-labelledby="cash-pay-title">
          <table class="data-table data-table--stack">
            <thead>
              <tr>
                <th scope="col">Medio de pago</th>
                <th scope="col" class="col-num">Importe registrado</th>
                <th scope="col" class="col-num">Devuelto</th>
                <th scope="col" class="col-num">Neto</th>
              </tr>
            </thead>
            <tbody>
              ${paymentSummary.rows.map((r) => `
                <tr>
                  <th scope="row">${escapeHtml(r.label)}</th>
                  <td data-label="Registrado" class="col-num">${formatARS(r.registered)}</td>
                  <td data-label="Devuelto" class="col-num ${r.refunded > 0 ? 'text-danger' : 'text-muted'}">${r.refunded > 0 ? `-${formatARS(r.refunded)}` : formatARS(0)}</td>
                  <td data-label="Neto" class="col-num fw-700">${formatARS(r.net)}</td>
                </tr>
              `).join('')}
              <tr style="background-color: var(--stone-50);">
                <th scope="row">Total sesión</th>
                <td data-label="Registrado" class="col-num fw-700">${formatARS(paymentSummary.totalRegistered)}</td>
                <td data-label="Devuelto" class="col-num fw-700 text-danger">${paymentSummary.totalRefunded > 0 ? `-${formatARS(paymentSummary.totalRefunded)}` : formatARS(0)}</td>
                <td data-label="Neto" class="col-num fw-700">${formatARS(paymentSummary.totalNet)}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <!-- Cash Movements Ledger -->
      <section class="card stack" aria-labelledby="cash-ledger-title">
        <div>
          <h2 id="cash-ledger-title" class="card__title">Movimientos de esta caja (${movements.length})</h2>
          <p class="card__desc">Libro cronológico de entradas y salidas de efectivo en la sesión #${canonicalReg?.id || '—'}.</p>
        </div>

        ${movements.length === 0
          ? emptyState({ iconName: 'cash', title: 'Sin movimientos registrados', description: 'Las ventas en efectivo y los movimientos manuales aparecerán en esta tabla.' })
          : `<div class="table-wrapper" tabindex="0" role="region" aria-labelledby="cash-ledger-title">
              <table class="data-table data-table--stack">
                <thead>
                  <tr>
                    <th scope="col">ID / Hora</th>
                    <th scope="col">Tipo</th>
                    <th scope="col">Motivo</th>
                    <th scope="col">Responsable</th>
                    <th scope="col" class="col-num">Monto</th>
                  </tr>
                </thead>
                <tbody>
                  ${movements.map((m) => {
                    const isPositive = m.type === 'Sale' || m.type === 'Income';
                    return `
                      <tr>
                        <th scope="row">#${m.id} <span class="text-xs text-muted fw-600">· ${formatTime(m.date)}</span></th>
                        <td data-label="Tipo">${badge(CASH_MOVEMENT_LABELS[m.type] || m.type, isPositive ? 'ok' : m.type === 'Refund' ? 'warn' : 'danger')}</td>
                        <td data-label="Motivo">${escapeHtml(m.reason)}</td>
                        <td data-label="Responsable">${escapeHtml(m.responsible)}</td>
                        <td data-label="Monto" class="col-num fw-700 ${isPositive ? 'text-ok' : 'text-danger'}">${isPositive ? '+' : '−'}${formatARS(m.amount)}</td>
                      </tr>
                    `;
                  }).join('')}
                </tbody>
              </table>
            </div>`}
      </section>
    </div>
  `;

  container.querySelector('#cash-go-history')?.addEventListener('click', () => navigate('cash-history'));
  container.querySelector('#cash-go-summary')?.addEventListener('click', () => navigate('summary'));

  // Open Cash Form
  container.querySelector('#open-cash-form')?.addEventListener('submit', (e) => {
    e.preventDefault();
    const form = e.currentTarget;
    const val = form.querySelector('#initial-amount').value;
    const res = openCashRegister(val);
    if (!res.ok) {
      container.querySelector('#open-cash-err').innerHTML = banner({ variant: 'danger', body: res.error });
      return;
    }
    showToast(`Caja #${res.register.id} abierta con ${formatARS(res.register.initialAmount)}.`, 'ok');
  });

  // Manual Cash Movement Form
  container.querySelector('#cash-move-form')?.addEventListener('submit', (e) => {
    e.preventDefault();
    const form = e.currentTarget;
    const errEl = container.querySelector('#cash-move-err');
    errEl.innerHTML = '';
    if (!form.checkValidity()) {
      form.querySelectorAll('input').forEach((inp) => {
        if (!inp.validity.valid) {
          inp.classList.add('user-invalid-fallback');
          inp.setAttribute('aria-invalid', 'true');
        }
      });
      form.querySelector(':invalid')?.focus();
      return;
    }
    const fd = new FormData(form);
    const res = addManualCashMovement({
      type: fd.get('type'),
      amount: fd.get('amount'),
      reason: fd.get('reason'),
    });
    if (!res.ok) {
      errEl.innerHTML = banner({ variant: 'danger', body: res.error });
      return;
    }
    showToast('Movimiento de efectivo registrado.', 'ok');
  });

  // Arqueo controls
  container.querySelector('#btn-refresh-arqueo')?.addEventListener('click', () => {
    if (openReg) {
      arqueoDraft.versionSnapshot = openReg.movementVersion;
      arqueoDraft.staleWarning = false;
      state.demo.simulateStaleArqueo = false;
      renderCash(container, navigate);
      showToast('Saldo esperado actualizado.', 'ok');
    }
  });

  container.querySelectorAll('[data-denom-qty]').forEach((inp) => {
    inp.addEventListener('change', (e) => {
      const idx = Number(inp.dataset.denomQty);
      arqueoDraft.rows[idx].qty = Math.max(0, Math.floor(Number(e.target.value || 0)));
      renderCash(container, navigate);
    });
  });

  container.querySelectorAll('[data-remove-denom]').forEach((btn) => {
    btn.addEventListener('click', () => {
      arqueoDraft.rows.splice(Number(btn.dataset.removeDenom), 1);
      renderCash(container, navigate);
    });
  });

  container.querySelector('#btn-add-denom')?.addEventListener('click', () => {
    openModal({
      title: 'Agregar denominación',
      bodyHtml: `
        <form id="add-denom-form" class="stack">
          <div id="add-denom-err"></div>
          <div class="field">
            <label class="field__label" for="custom-denom">Valor del billete o moneda ($)</label>
            <input id="custom-denom" type="number" min="1" step="any" class="input tnum" value="50" required autofocus>
          </div>
        </form>
      `,
      footerHtml: `
        <button type="button" class="btn" data-modal-close>Cancelar</button>
        <button type="submit" form="add-denom-form" class="btn btn--primary">Agregar</button>
      `,
      onMount(dlg) {
        dlg.querySelector('#add-denom-form').addEventListener('submit', (e) => {
          e.preventDefault();
          const val = roundMoney(dlg.querySelector('#custom-denom').value);
          if (val <= 0) return;
          if (arqueoDraft.rows.some((r) => Math.abs(Number(r.value) - val) < 0.01)) {
            dlg.querySelector('#add-denom-err').innerHTML = banner({ variant: 'warn', body: `La denominación ${formatARS(val)} ya existe en el arqueo.` });
            return;
          }
          arqueoDraft.rows.push({ value: val, qty: 0 });
          arqueoDraft.rows.sort((a, b) => b.value - a.value);
          dlg.close('ok');
          renderCash(container, navigate);
        });
      },
    });
  });

  container.querySelector('#btn-fill-exact')?.addEventListener('click', () => {
    let rem = Math.max(0, Math.round(expected));
    arqueoDraft.rows = AR_DENOMINATIONS.map((val) => {
      const qty = Math.floor(rem / val);
      rem -= qty * val;
      return { value: val, qty };
    });
    if (rem > 0) arqueoDraft.rows.push({ value: rem, qty: 1 });
    arqueoDraft.differenceReason = '';
    renderCash(container, navigate);
  });

  container.querySelector('#arqueo-diff-reason')?.addEventListener('input', (e) => {
    arqueoDraft.differenceReason = e.target.value;
  });

  container.querySelector('#btn-review-close')?.addEventListener('click', () => {
    if (!openReg) return;
    if (isStale) {
      arqueoDraft.staleWarning = true;
      showToast('Actualizá el saldo esperado antes de cerrar la caja.', 'warn');
      return;
    }
    if (Math.abs(diff) >= 0.01 && !arqueoDraft.differenceReason.trim()) {
      const reasonInp = container.querySelector('#arqueo-diff-reason');
      reasonInp?.focus();
      showToast('Indicá el motivo de la diferencia antes de revisar el cierre.', 'warn');
      return;
    }
    openCloseReviewModal(openReg, expected, countedTotal, diff, diffMeta);
  });
}

function openCloseReviewModal(openReg, expected, countedTotal, diff, diffMeta) {
  openModal({
    title: `Confirmá el cierre · Caja #${openReg.id}`,
    subtitle: 'Esta acción cierra la sesión actual, guarda el arqueo y genera el resumen diario.',
    lightDismiss: false,
    bodyHtml: `
      <form id="confirm-close-form" class="stack">
        <div id="close-review-err"></div>
        <div class="card card--compact card--subtle stack stack--sm">
          <div class="summary-row"><span>Esperado en caja</span><strong class="tnum">${formatARS(expected)}</strong></div>
          <div class="summary-row"><span>Total contado en arqueo</span><strong class="tnum">${formatARS(countedTotal)}</strong></div>
          <div class="summary-row"><span>Resultado</span>${badge(diffMeta.label, diffMeta.variant)}</div>
          ${arqueoDraft.differenceReason ? `<div class="text-xs text-secondary mt-2"><strong>Motivo informado:</strong> ${escapeHtml(arqueoDraft.differenceReason)}</div>` : ''}
        </div>

        ${countedTotal === 0 ? `
          <label class="check-field">
            <input type="checkbox" id="confirm-zero-cash" required>
            <span>Confirmo que el arqueo físico resultó en $0 de efectivo en caja.</span>
          </label>
        ` : ''}
      </form>
    `,
    footerHtml: `
      <button type="button" class="btn" data-modal-close autofocus>Volver a editar</button>
      <button type="submit" form="confirm-close-form" class="btn btn--danger">Confirmar cierre definitivo</button>
    `,
    onMount(dlg) {
      dlg.querySelector('#confirm-close-form').addEventListener('submit', (e) => {
        e.preventDefault();
        const zeroChk = dlg.querySelector('#confirm-zero-cash');
        if (zeroChk && !zeroChk.checked) {
          zeroChk.focus();
          return;
        }
        const res = closeCashRegister({
          denominations: arqueoDraft.rows,
          differenceReason: arqueoDraft.differenceReason,
          expectedVersion: arqueoDraft.versionSnapshot,
        });
        if (!res.ok) {
          if (res.stale) arqueoDraft.staleWarning = true;
          dlg.querySelector('#close-review-err').innerHTML = banner({ variant: 'danger', body: res.error });
          return;
        }
        dlg.close('closed');
        showToast(`Caja #${openReg.id} cerrada definitivamente.`, 'ok');
      });
    },
  });
}
