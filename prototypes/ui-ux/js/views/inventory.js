import {
  getState,
  getIngredientStatus,
  getIngredientCoverageDays,
  getStockAlerts,
  saveIngredient,
  deleteIngredient,
  adjustIngredientStock,
  registerIngredientWaste,
  commitStockCount,
} from '../state/store.js';
import { UNITS, WASTE_CATEGORIES, STOCK_MOVEMENT_LABELS } from '../data/seed.js';
import { formatARS, formatDateTime, formatNum, formatQtyUnit, escapeHtml, roundQty } from '../utils/format.js';
import { icon } from '../utils/icons.js';
import { badge, banner, emptyState, loadingSkeleton, openModal, openConfirmModal } from '../utils/ui.js';
import { showToast } from '../utils/a11y.js';

let activeTab = 'stock'; // stock | movements | count
let movementFilters = { ingredientId: 'all', type: 'all', from: '', to: '' };

// 3-step physical stock count wizard state (mirrors StockCount.razor)
let countWizard = {
  step: 1,
  search: '',
  selectedIds: [2, 3, 5],
  countedMap: {},
  expectedSnapshot: null,
  reasonsMap: {},
  notes: '',
  confirmed: false,
};

export function renderInventory(container, navigate) {
  const state = getState();

  if (state.demo.simulateLoading) {
    container.innerHTML = `
      <div class="page-header"><h1 id="page-heading" tabindex="-1">Ingredientes e inventario</h1></div>
      ${loadingSkeleton(4)}
    `;
    return;
  }

  const ingredients = state.demo.simulateEmpty ? [] : state.ingredients;
  const alerts = state.demo.simulateEmpty ? [] : getStockAlerts();

  container.innerHTML = `
    <div class="page-header">
      <div>
        <div class="page-header__title-row">
          <h1 id="page-heading" tabindex="-1">Ingredientes e inventario</h1>
          ${alerts.length ? badge(`${alerts.length} alerta(s)`, 'danger', 'alertTriangle') : badge('Stock saludable', 'ok', 'checkCircle')}
        </div>
        <p class="page-header__subtitle">Gestioná stock actual, alertas con cobertura a 7 días, ajustes auditados, mermas, historial y conteos físicos.</p>
      </div>
      <div class="page-header__actions">
        <button type="button" class="btn" id="inv-go-purchasing">${icon('suppliers', 17)} Cargar factura de compra</button>
        <button type="button" class="btn btn--primary" id="btn-new-ing">${icon('plus', 17)} Nuevo ingrediente</button>
      </div>
    </div>

    <div class="tablist" role="tablist" aria-label="Vistas de inventario">
      <button type="button" class="tab" role="tab" id="tab-stock" aria-selected="${activeTab === 'stock'}" data-inv-tab="stock">
        ${icon('ingredients', 16)}
        <span>Stock y alertas (${ingredients.length})</span>
      </button>
      <button type="button" class="tab" role="tab" id="tab-movements" aria-selected="${activeTab === 'movements'}" data-inv-tab="movements">
        ${icon('history', 16)}
        <span>Movimientos (${state.stockMovements.length})</span>
      </button>
      <button type="button" class="tab" role="tab" id="tab-count" aria-selected="${activeTab === 'count'}" data-inv-tab="count">
        ${icon('clipboard', 16)}
        <span>Conteo físico</span>
      </button>
    </div>

    <div id="inv-panel"></div>
  `;

  container.querySelector('#inv-go-purchasing')?.addEventListener('click', () => navigate('purchasing'));
  container.querySelector('#btn-new-ing')?.addEventListener('click', () => openIngredientModal(null));
  container.querySelectorAll('[data-inv-tab]').forEach((t) => {
    t.addEventListener('click', () => {
      activeTab = t.dataset.invTab;
      renderInventory(container, navigate);
    });
  });

  const panel = container.querySelector('#inv-panel');
  if (activeTab === 'stock') renderStockTab(panel, ingredients, alerts, navigate);
  else if (activeTab === 'movements') renderMovementsTab(panel, navigate);
  else renderStockCountTab(panel);
}

function renderStockTab(panel, ingredients, alerts, navigate) {
  panel.innerHTML = `
    <div class="stack stack--lg" role="tabpanel" aria-labelledby="tab-stock">
      ${alerts.length > 0 ? `
        <section class="card stack" aria-labelledby="stock-alerts-heading">
          <div class="row-between">
            <div>
              <h2 id="stock-alerts-heading" class="card__title">Alertas de stock (${alerts.length})</h2>
              <p class="card__desc">Ingredientes agotados o por debajo del mínimo configurado con cobertura estimada (consumo de 7 días).</p>
            </div>
          </div>
          <div class="table-wrapper" tabindex="0" role="region" aria-labelledby="stock-alerts-heading">
            <table class="data-table data-table--stack">
              <thead>
                <tr>
                  <th scope="col">Ingrediente</th>
                  <th scope="col">Estado</th>
                  <th scope="col" class="col-num">Stock actual</th>
                  <th scope="col" class="col-num">Mínimo</th>
                  <th scope="col" class="col-num">Cobertura estimada</th>
                  <th scope="col" class="col-actions">Acción rápida</th>
                </tr>
              </thead>
              <tbody>
                ${alerts.map((ing) => {
                  const st = getIngredientStatus(ing);
                  const days = getIngredientCoverageDays(ing);
                  return `
                    <tr>
                      <th scope="row">${escapeHtml(ing.name)}</th>
                      <td data-label="Estado">${badge(st.label, st.variant, st.code === 'out' ? 'alertOctagon' : 'alertTriangle')}</td>
                      <td data-label="Actual" class="col-num fw-700">${formatQtyUnit(ing.currentStock, ing.unit)}</td>
                      <td data-label="Mínimo" class="col-num">${formatQtyUnit(ing.minStock, ing.unit)}</td>
                      <td data-label="Cobertura" class="col-num">${days === 0 ? 'Sin cobertura' : days != null ? `${formatNum(days)} días` : '—'}</td>
                      <td class="col-actions">
                        <button type="button" class="btn btn--primary btn--sm" data-adjust-ing="${ing.id}">Ajustar stock</button>
                      </td>
                    </tr>
                  `;
                }).join('')}
              </tbody>
            </table>
          </div>
        </section>
      ` : ''}

      <section class="card stack" aria-labelledby="all-ing-heading">
        <div>
          <h2 id="all-ing-heading" class="card__title">Listado de ingredientes</h2>
          <p class="card__desc">Cada ajuste manual o merma queda auditado en el libro de movimientos.</p>
        </div>

        ${ingredients.length === 0
          ? emptyState({ iconName: 'ingredients', title: 'Sin ingredientes cargados', description: 'Creá tus insumos base para controlar recetas y stock.' })
          : `<div class="table-wrapper" tabindex="0" role="region" aria-labelledby="all-ing-heading">
              <table class="data-table data-table--stack">
                <thead>
                  <tr>
                    <th scope="col">Ingrediente</th>
                    <th scope="col">Estado</th>
                    <th scope="col" class="col-num">Stock actual</th>
                    <th scope="col" class="col-num">Mínimo</th>
                    <th scope="col" class="col-num">Último precio</th>
                    <th scope="col" class="col-actions">Acciones</th>
                  </tr>
                </thead>
                <tbody>
                  ${ingredients.map((ing) => {
                    const st = getIngredientStatus(ing);
                    return `
                      <tr>
                        <th scope="row">
                          <div>${escapeHtml(ing.name)}</div>
                          ${ing.currentStock < 0 ? `<div class="text-xs text-danger fw-700 mt-2">Stock negativo: requiere ajuste</div>` : ''}
                          ${!ing.active ? '<div class="text-xs text-muted fw-600">Inactivo</div>' : ''}
                        </th>
                        <td data-label="Estado">${badge(ing.active ? st.label : 'Inactivo', ing.active ? st.variant : 'neutral')}</td>
                        <td data-label="Stock actual" class="col-num fw-700">${formatQtyUnit(ing.currentStock, ing.unit)}</td>
                        <td data-label="Mínimo" class="col-num">${formatQtyUnit(ing.minStock, ing.unit)}</td>
                        <td data-label="Último precio" class="col-num">${ing.lastUnitPrice ? `${formatARS(ing.lastUnitPrice)} / ${ing.unit}` : 'Sin factura'}</td>
                        <td class="col-actions">
                          <div class="flex-wrap-gap" style="justify-content: flex-end;">
                            <button type="button" class="btn btn--sm" data-adjust-ing="${ing.id}">Ajustar</button>
                            <button type="button" class="btn btn--sm" data-waste-ing="${ing.id}" ${ing.currentStock <= 0 ? 'disabled' : ''}>Merma</button>
                            <button type="button" class="btn btn--ghost btn--sm" data-hist-ing="${ing.id}">Historial</button>
                            <button type="button" class="btn btn--ghost btn--sm" data-edit-ing="${ing.id}">Editar</button>
                            <button type="button" class="btn btn--ghost btn--icon" data-del-ing="${ing.id}" aria-label="Eliminar ${escapeHtml(ing.name)}">${icon('trash', 15)}</button>
                          </div>
                        </td>
                      </tr>
                    `;
                  }).join('')}
                </tbody>
              </table>
            </div>`}
      </section>
    </div>
  `;

  const state = getState();
  panel.querySelectorAll('[data-adjust-ing]').forEach((btn) => {
    btn.addEventListener('click', () => {
      const ing = state.ingredients.find((i) => i.id === Number(btn.dataset.adjustIng));
      if (ing) openAdjustModal(ing);
    });
  });

  panel.querySelectorAll('[data-waste-ing]').forEach((btn) => {
    btn.addEventListener('click', () => {
      const ing = state.ingredients.find((i) => i.id === Number(btn.dataset.wasteIng));
      if (ing) openWasteModal(ing);
    });
  });

  panel.querySelectorAll('[data-hist-ing]').forEach((btn) => {
    btn.addEventListener('click', () => {
      movementFilters.ingredientId = String(btn.dataset.histIng);
      activeTab = 'movements';
      renderInventory(panel.closest('#view-root') || document.getElementById('view-root'), navigate);
    });
  });

  panel.querySelectorAll('[data-edit-ing]').forEach((btn) => {
    btn.addEventListener('click', () => {
      const ing = state.ingredients.find((i) => i.id === Number(btn.dataset.editIng));
      if (ing) openIngredientModal(ing);
    });
  });

  panel.querySelectorAll('[data-del-ing]').forEach((btn) => {
    btn.addEventListener('click', () => {
      const ing = state.ingredients.find((i) => i.id === Number(btn.dataset.delIng));
      if (!ing) return;
      openConfirmModal({
        title: `¿Eliminar "${ing.name}"?`,
        message: 'Solo se pueden eliminar ingredientes sin movimientos, recetas ni facturas asociadas.',
        confirmLabel: 'Eliminar ingrediente',
        onConfirm: () => {
          const res = deleteIngredient(ing.id);
          if (!res.ok) return res.error;
          showToast(`Ingrediente "${ing.name}" eliminado.`, 'ok');
        },
      });
    });
  });
}

function renderMovementsTab(panel, navigate) {
  const state = getState();
  const selectedIng = movementFilters.ingredientId !== 'all'
    ? state.ingredients.find((i) => String(i.id) === String(movementFilters.ingredientId))
    : null;
  const allForSelected = selectedIng
    ? state.stockMovements.filter((m) => m.ingredientId === selectedIng.id)
    : [];
  const ledgerSum = roundQty(allForSelected.reduce((a, m) => a + Number(m.delta || 0), 0));
  const priorUnloggedBalance = selectedIng ? roundQty(selectedIng.currentStock - ledgerSum) : 0;

  const rows = state.demo.simulateEmpty
    ? []
    : state.stockMovements.filter((m) => {
        const d = m.date.slice(0, 10);
        const matchIng = movementFilters.ingredientId === 'all' || String(m.ingredientId) === String(movementFilters.ingredientId);
        const matchType = movementFilters.type === 'all' || m.type === movementFilters.type;
        const matchFrom = !movementFilters.from || d >= movementFilters.from;
        const matchTo = !movementFilters.to || d <= movementFilters.to;
        return matchIng && matchType && matchFrom && matchTo;
      });

  panel.innerHTML = `
    <div class="stack" role="tabpanel" aria-labelledby="tab-movements">
      ${banner({
        variant: 'info',
        title: 'Libro histórico de movimientos (M15 — implementado en el código actual)',
        body: 'Registra cada ingreso por factura, consumo por venta, reposición por anulación/devolución, ajuste manual, merma y conteo físico.',
      })}

      ${selectedIng && Math.abs(priorUnloggedBalance) > 0.0001 ? banner({
        variant: 'warn',
        title: `Saldo previo sin historial: ${formatQtyUnit(priorUnloggedBalance, selectedIng.unit)}`,
        body: `${escapeHtml(selectedIng.name)} tiene stock actual de ${formatQtyUnit(selectedIng.currentStock, selectedIng.unit)}, parte del cual existía antes del libro de movimientos.`,
      }) : ''}

      <search class="card card--compact stack stack--sm">
        <div class="form-grid">
          <div class="field">
            <label class="field__label" for="mov-ing">Ingrediente</label>
            <select id="mov-ing" class="select select--compact">
              <option value="all">Todos los ingredientes</option>
              ${state.ingredients.map((i) => `<option value="${i.id}" ${String(movementFilters.ingredientId) === String(i.id) ? 'selected' : ''}>${escapeHtml(i.name)} (${i.unit})</option>`).join('')}
            </select>
          </div>
          <div class="field">
            <label class="field__label" for="mov-type">Causa / Tipo</label>
            <select id="mov-type" class="select select--compact">
              <option value="all">Todas las causas</option>
              ${Object.entries(STOCK_MOVEMENT_LABELS).map(([k, lbl]) => `<option value="${k}" ${movementFilters.type === k ? 'selected' : ''}>${escapeHtml(lbl)}</option>`).join('')}
            </select>
          </div>
          <div class="field">
            <label class="field__label" for="mov-from">Desde</label>
            <input id="mov-from" type="date" class="input input--compact" value="${escapeHtml(movementFilters.from)}">
          </div>
          <div class="field">
            <label class="field__label" for="mov-to">Hasta</label>
            <input id="mov-to" type="date" class="input input--compact" value="${escapeHtml(movementFilters.to)}">
          </div>
        </div>
        <div class="flex-wrap-gap">
          <button type="button" class="btn btn--sm" id="mov-clear">Limpiar filtros</button>
          <span class="text-xs text-muted">${rows.length} movimiento(s)</span>
        </div>
      </search>

      ${rows.length === 0
        ? emptyState({ iconName: 'history', title: 'Sin movimientos para estos filtros', description: 'Probá seleccionando todos los ingredientes o causas.' })
        : `<div class="table-wrapper" tabindex="0" role="region" aria-label="Movimientos históricos de inventario">
            <table class="data-table data-table--stack">
              <thead>
                <tr>
                  <th scope="col">Fecha</th>
                  <th scope="col">Ingrediente</th>
                  <th scope="col">Tipo</th>
                  <th scope="col" class="col-num">Variación</th>
                  <th scope="col" class="col-num">Anterior → Posterior</th>
                  <th scope="col">Motivo / Origen</th>
                </tr>
              </thead>
              <tbody>
                ${rows.map((m) => {
                  const ing = state.ingredients.find((i) => i.id === m.ingredientId);
                  const unit = ing?.unit || '';
                  const originLink = m.sourceType === 'Sale'
                    ? `<button type="button" class="btn btn--ghost btn--sm" data-mov-nav="sales-history">Venta #${m.sourceId}</button>`
                    : m.sourceType === 'Invoice'
                      ? `<button type="button" class="btn btn--ghost btn--sm" data-mov-nav="purchasing">Factura #${m.sourceId}</button>`
                      : m.sourceType === 'StockCount'
                        ? `<button type="button" class="btn btn--ghost btn--sm" data-mov-count="${m.sourceId}">Conteo #${m.sourceId}</button>`
                        : '';
                  return `
                    <tr>
                      <th scope="row">${formatDateTime(m.date)}</th>
                      <td data-label="Ingrediente" class="fw-600">${escapeHtml(ing?.name || `#${m.ingredientId}`)}</td>
                      <td data-label="Tipo">
                        ${badge(STOCK_MOVEMENT_LABELS[m.type] || m.type, m.delta > 0 ? 'ok' : m.type === 'Waste' ? 'danger' : 'neutral')}
                        ${m.wasteCategory ? `<div class="text-xs text-muted mt-2">${escapeHtml(WASTE_CATEGORIES.find((w) => w.id === m.wasteCategory)?.label || m.wasteCategory)}</div>` : ''}
                      </td>
                      <td data-label="Variación" class="col-num fw-700 ${m.delta > 0 ? 'text-ok' : 'text-danger'}">
                        ${m.delta > 0 ? '+' : ''}${formatQtyUnit(m.delta, unit)}
                      </td>
                      <td data-label="Saldo" class="col-num">${formatNum(m.before)} → <strong>${formatNum(m.after)} ${unit}</strong></td>
                      <td data-label="Motivo">
                        <div>${escapeHtml(m.reason)}</div>
                        <div class="flex-wrap-gap text-xs text-muted">
                          <span>${escapeHtml(m.responsible)}</span>
                          ${originLink}
                        </div>
                      </td>
                    </tr>
                  `;
                }).join('')}
              </tbody>
            </table>
          </div>`}
    </div>
  `;

  panel.querySelector('#mov-ing')?.addEventListener('change', (e) => { movementFilters.ingredientId = e.target.value; renderMovementsTab(panel, navigate); });
  panel.querySelector('#mov-type')?.addEventListener('change', (e) => { movementFilters.type = e.target.value; renderMovementsTab(panel, navigate); });
  panel.querySelector('#mov-from')?.addEventListener('change', (e) => { movementFilters.from = e.target.value; renderMovementsTab(panel, navigate); });
  panel.querySelector('#mov-to')?.addEventListener('change', (e) => { movementFilters.to = e.target.value; renderMovementsTab(panel, navigate); });
  panel.querySelector('#mov-clear')?.addEventListener('click', () => {
    movementFilters = { ingredientId: 'all', type: 'all', from: '', to: '' };
    renderMovementsTab(panel, navigate);
  });
  panel.querySelectorAll('[data-mov-nav]').forEach((b) => {
    b.addEventListener('click', () => navigate(b.dataset.movNav));
  });
  panel.querySelectorAll('[data-mov-count]').forEach((b) => {
    b.addEventListener('click', () => {
      const rec = state.stockCounts.find((c) => c.id === Number(b.dataset.movCount));
      if (rec) openStockCountDetailModal(rec);
    });
  });
}

function renderStockCountTab(panel) {
  const state = getState();
  const filteredPool = state.ingredients.filter((i) =>
    !countWizard.search.trim() || i.name.toLowerCase().includes(countWizard.search.trim().toLowerCase())
  );
  const selectedIngs = state.ingredients.filter((i) => countWizard.selectedIds.includes(i.id));

  panel.innerHTML = `
    <div class="stack stack--lg" role="tabpanel" aria-labelledby="tab-count">
      <section class="card stack" aria-labelledby="count-title">
        <div>
          <h2 id="count-title" class="card__title">Nuevo conteo físico de stock</h2>
          <p class="card__desc">Flujo guiado en 3 pasos para conciliar el stock real contra el teórico del sistema.</p>
        </div>

        <nav aria-label="Progreso del conteo físico">
          <ol class="stepper">
            <li class="stepper__item ${countWizard.step > 1 ? 'stepper__item--done' : ''}" ${countWizard.step === 1 ? 'aria-current="step"' : ''}>1. Elegir ingredientes</li>
            <li class="stepper__item ${countWizard.step > 2 ? 'stepper__item--done' : ''}" ${countWizard.step === 2 ? 'aria-current="step"' : ''}>2. Ingresar lo contado</li>
            <li class="stepper__item" ${countWizard.step === 3 ? 'aria-current="step"' : ''}>3. Revisar diferencias y confirmar</li>
          </ol>
        </nav>

        <div id="count-err"></div>

        ${countWizard.step === 1 ? `
          <div class="stack">
            <div class="toolbar">
              <div class="search-wrap">
                <span class="search-wrap__icon">${icon('search', 16)}</span>
                <label for="cnt-search" class="visually-hidden">Filtrar ingredientes por nombre</label>
                <input id="cnt-search" type="search" class="input input--compact" value="${escapeHtml(countWizard.search)}" placeholder="Filtrar ingredientes por nombre…">
              </div>
              <button type="button" class="btn btn--sm" id="cnt-sel-low">Solo stock bajo</button>
              <button type="button" class="btn btn--sm" id="cnt-sel-all">Seleccionar todos</button>
              <button type="button" class="btn btn--ghost btn--sm" id="cnt-sel-none">Limpiar selección</button>
            </div>

            <div class="form-grid">
              ${filteredPool.map((ing) => `
                <label class="check-field card card--compact" style="padding: var(--space-3);">
                  <input type="checkbox" data-cnt-chk="${ing.id}" ${countWizard.selectedIds.includes(ing.id) ? 'checked' : ''}>
                  <span>
                    <strong>${escapeHtml(ing.name)}</strong>
                    <span class="text-xs text-muted" style="display: block;">Actual: ${formatQtyUnit(ing.currentStock, ing.unit)}</span>
                  </span>
                </label>
              `).join('')}
            </div>
            <div class="flex-wrap-gap">
              <button type="button" class="btn btn--primary" id="cnt-next-2" ${countWizard.selectedIds.length === 0 ? 'disabled' : ''}>Continuar (${countWizard.selectedIds.length} seleccionados)</button>
            </div>
          </div>
        ` : countWizard.step === 2 ? `
          <div class="stack">
            <div class="table-wrapper" tabindex="0" role="region" aria-label="Carga de cantidades contadas">
              <table class="data-table">
                <thead>
                  <tr>
                    <th scope="col">Ingrediente</th>
                    <th scope="col" class="col-num">Teórico en sistema</th>
                    <th scope="col">Cantidad contada</th>
                  </tr>
                </thead>
                <tbody>
                  ${selectedIngs.map((ing) => {
                    const val = countWizard.countedMap[ing.id] ?? ing.currentStock;
                    return `
                      <tr>
                        <th scope="row">${escapeHtml(ing.name)}</th>
                        <td class="col-num">${formatQtyUnit(ing.currentStock, ing.unit)}</td>
                        <td>
                          <div class="flex-wrap-gap">
                            <input type="number" min="0" step="any" class="input input--compact tnum" style="max-inline-size: 9rem;" data-cnt-val="${ing.id}" value="${val}" aria-label="Cantidad contada de ${escapeHtml(ing.name)}">
                            <span class="text-sm text-muted">${ing.unit}</span>
                          </div>
                        </td>
                      </tr>
                    `;
                  }).join('')}
                </tbody>
              </table>
            </div>
            <div class="flex-wrap-gap">
              <button type="button" class="btn" id="cnt-back-1">Volver</button>
              <button type="button" class="btn btn--primary" id="cnt-next-3">Comparar diferencias</button>
            </div>
          </div>
        ` : `
          <div class="stack">
            <div class="table-wrapper" tabindex="0" role="region" aria-label="Revisión de diferencias del conteo">
              <table class="data-table data-table--stack">
                <thead>
                  <tr>
                    <th scope="col">Ingrediente</th>
                    <th scope="col" class="col-num">Teórico</th>
                    <th scope="col" class="col-num">Contado</th>
                    <th scope="col">Diferencia</th>
                    <th scope="col">Motivo (obligatorio si difiere)</th>
                  </tr>
                </thead>
                <tbody>
                  ${selectedIngs.map((ing) => {
                    const counted = roundQty(countWizard.countedMap[ing.id] ?? ing.currentStock);
                    const diff = roundQty(counted - ing.currentStock);
                    const statusBadge = diff === 0 ? badge('Sin diferencia', 'ok') : diff < 0 ? badge(`Faltante ${formatQtyUnit(diff, ing.unit)}`, 'danger') : badge(`Sobrante +${formatQtyUnit(diff, ing.unit)}`, 'info');
                    return `
                      <tr>
                        <th scope="row">${escapeHtml(ing.name)}</th>
                        <td data-label="Teórico" class="col-num">${formatQtyUnit(ing.currentStock, ing.unit)}</td>
                        <td data-label="Contado" class="col-num fw-700">${formatQtyUnit(counted, ing.unit)}</td>
                        <td data-label="Diferencia">${statusBadge}</td>
                        <td data-label="Motivo">
                          ${diff === 0
                            ? '<span class="text-xs text-muted">No requiere motivo</span>'
                            : `<input type="text" class="input input--compact" data-cnt-reason="${ing.id}" value="${escapeHtml(countWizard.reasonsMap[ing.id] || '')}" placeholder="Motivo del ajuste…" aria-label="Motivo para ${escapeHtml(ing.name)}">`}
                        </td>
                      </tr>
                    `;
                  }).join('')}
                </tbody>
              </table>
            </div>

            <div class="field">
              <label class="field__label" for="cnt-notes">Notas generales del conteo (opcional)</label>
              <input id="cnt-notes" type="text" class="input" value="${escapeHtml(countWizard.notes)}" placeholder="Ej.: Control previo al turno noche">
            </div>

            <label class="check-field">
              <input type="checkbox" id="cnt-confirm-chk" ${countWizard.confirmed ? 'checked' : ''}>
              <span>Confirmo que las cantidades contadas fueron verificadas físicamente y deseo aplicar los ajustes.</span>
            </label>

            <div class="flex-wrap-gap">
              <button type="button" class="btn" id="cnt-back-2">Volver a editar cantidades</button>
              <button type="button" class="btn btn--collect" id="cnt-commit">${icon('checkCircle', 17)} Confirmar conteo y aplicar ajustes</button>
            </div>
          </div>
        `}
      </section>

      <section class="card stack" aria-labelledby="past-counts-title">
        <h2 id="past-counts-title" class="card__title">Conteos anteriores (${state.stockCounts.length})</h2>
        <div class="table-wrapper" tabindex="0" role="region" aria-labelledby="past-counts-title">
          <table class="data-table data-table--stack">
            <thead>
              <tr>
                <th scope="col">Conteo</th>
                <th scope="col">Fecha</th>
                <th scope="col">Responsable</th>
                <th scope="col" class="col-num">Ítems revisados</th>
                <th scope="col">Notas</th>
                <th scope="col" class="col-actions">Detalle</th>
              </tr>
            </thead>
            <tbody>
              ${state.stockCounts.map((c) => `
                <tr>
                  <th scope="row">#${c.id}</th>
                  <td data-label="Fecha">${formatDateTime(c.date)}</td>
                  <td data-label="Responsable">${escapeHtml(c.responsible)}</td>
                  <td data-label="Ítems" class="col-num">${c.items.length}</td>
                  <td data-label="Notas">${escapeHtml(c.notes || '—')}</td>
                  <td class="col-actions">
                    <button type="button" class="btn btn--sm" data-view-count="${c.id}">Ver detalle</button>
                  </td>
                </tr>
              `).join('')}
            </tbody>
          </table>
        </div>
      </section>
    </div>
  `;

  const searchEl = panel.querySelector('#cnt-search');
  searchEl?.addEventListener('input', (e) => {
    countWizard.search = e.target.value;
    const pos = e.target.selectionStart;
    renderStockCountTab(panel);
    const next = document.getElementById('cnt-search');
    if (next) { next.focus(); next.setSelectionRange(pos, pos); }
  });

  panel.querySelectorAll('[data-cnt-chk]').forEach((chk) => {
    chk.addEventListener('change', () => {
      const id = Number(chk.dataset.cntChk);
      if (chk.checked && !countWizard.selectedIds.includes(id)) countWizard.selectedIds.push(id);
      if (!chk.checked) countWizard.selectedIds = countWizard.selectedIds.filter((x) => x !== id);
      renderStockCountTab(panel);
    });
  });

  panel.querySelector('#cnt-sel-low')?.addEventListener('click', () => {
    countWizard.selectedIds = getStockAlerts().map((i) => i.id);
    renderStockCountTab(panel);
  });

  panel.querySelector('#cnt-sel-all')?.addEventListener('click', () => {
    countWizard.selectedIds = state.ingredients.map((i) => i.id);
    renderStockCountTab(panel);
  });

  panel.querySelector('#cnt-sel-none')?.addEventListener('click', () => {
    countWizard.selectedIds = [];
    renderStockCountTab(panel);
  });

  panel.querySelector('#cnt-next-2')?.addEventListener('click', () => { countWizard.step = 2; renderStockCountTab(panel); });
  panel.querySelector('#cnt-back-1')?.addEventListener('click', () => { countWizard.step = 1; renderStockCountTab(panel); });

  panel.querySelectorAll('[data-cnt-val]').forEach((inp) => {
    inp.addEventListener('input', () => { countWizard.countedMap[Number(inp.dataset.cntVal)] = Number(inp.value); });
  });

  panel.querySelector('#cnt-next-3')?.addEventListener('click', () => {
    countWizard.expectedSnapshot = Object.fromEntries(selectedIngs.map((i) => [i.id, i.currentStock]));
    countWizard.step = 3;
    renderStockCountTab(panel);
  });
  panel.querySelector('#cnt-back-2')?.addEventListener('click', () => { countWizard.step = 2; renderStockCountTab(panel); });

  panel.querySelectorAll('[data-cnt-reason]').forEach((inp) => {
    inp.addEventListener('input', () => { countWizard.reasonsMap[Number(inp.dataset.cntReason)] = inp.value; });
  });

  panel.querySelector('#cnt-notes')?.addEventListener('input', (e) => { countWizard.notes = e.target.value; });
  panel.querySelector('#cnt-confirm-chk')?.addEventListener('change', (e) => { countWizard.confirmed = e.target.checked; });

  panel.querySelector('#cnt-commit')?.addEventListener('click', () => {
    if (!countWizard.confirmed) {
      panel.querySelector('#count-err').innerHTML = banner({ variant: 'warn', body: 'Marcá la casilla de verificación física antes de confirmar el conteo.' });
      return;
    }
    const items = selectedIngs.map((ing) => ({
      ingredientId: ing.id,
      counted: countWizard.countedMap[ing.id] ?? ing.currentStock,
      reason: countWizard.reasonsMap[ing.id] || '',
    }));
    const res = commitStockCount({ items, notes: countWizard.notes, expectedSnapshot: countWizard.expectedSnapshot });
    if (!res.ok) {
      panel.querySelector('#count-err').innerHTML = banner({ variant: 'danger', body: res.error });
      return;
    }
    countWizard = { step: 1, search: '', selectedIds: [], countedMap: {}, expectedSnapshot: null, reasonsMap: {}, notes: '', confirmed: false };
    showToast(`Conteo físico #${res.record.id} confirmado y aplicado al stock.`, 'ok');
  });

  panel.querySelectorAll('[data-view-count]').forEach((btn) => {
    btn.addEventListener('click', () => {
      const rec = state.stockCounts.find((c) => c.id === Number(btn.dataset.viewCount));
      if (rec) openStockCountDetailModal(rec);
    });
  });
}

function openStockCountDetailModal(rec) {
  openModal({
    title: `Conteo físico #${rec.id}`,
    subtitle: `${formatDateTime(rec.date)} · Responsable: ${rec.responsible}`,
    size: 'lg',
    bodyHtml: `
      <div class="stack">
        ${rec.notes ? `<p class="text-sm"><strong>Notas:</strong> ${escapeHtml(rec.notes)}</p>` : ''}
        <div class="table-wrapper" tabindex="0" role="region" aria-label="Detalle del conteo físico">
          <table class="data-table data-table--stack">
            <thead>
              <tr>
                <th scope="col">Ingrediente</th>
                <th scope="col" class="col-num">Teórico</th>
                <th scope="col" class="col-num">Contado</th>
                <th scope="col">Diferencia</th>
                <th scope="col">Motivo</th>
              </tr>
            </thead>
            <tbody>
              ${rec.items.map((it) => `
                <tr>
                  <th scope="row">${escapeHtml(it.ingredientName)}</th>
                  <td data-label="Teórico" class="col-num">${formatQtyUnit(it.expected, it.unit)}</td>
                  <td data-label="Contado" class="col-num fw-700">${formatQtyUnit(it.counted, it.unit)}</td>
                  <td data-label="Diferencia">${it.diff === 0 ? badge('Sin diferencia', 'ok') : it.diff < 0 ? badge(`Faltante ${formatQtyUnit(it.diff, it.unit)}`, 'danger') : badge(`Sobrante +${formatQtyUnit(it.diff, it.unit)}`, 'info')}</td>
                  <td data-label="Motivo">${escapeHtml(it.reason || '—')}</td>
                </tr>
              `).join('')}
            </tbody>
          </table>
        </div>
      </div>
    `,
    footerHtml: `<button type="button" class="btn btn--primary" data-modal-close>Cerrar</button>`,
  });
}

function openAdjustModal(ing) {
  const initialVal = Math.max(ing.minStock * 2, ing.currentStock + 5);
  openModal({
    title: `Ajustar stock · ${ing.name}`,
    subtitle: `Stock actual: ${formatQtyUnit(ing.currentStock, ing.unit)} · Mínimo: ${formatQtyUnit(ing.minStock, ing.unit)}`,
    lightDismiss: false,
    bodyHtml: `
      <form id="adj-form" class="stack" novalidate>
        <div id="adj-err"></div>
        <div class="field">
          <label class="field__label" for="adj-new">Nuevo stock (${ing.unit}) <span class="field__req" aria-hidden="true">*</span></label>
          <input id="adj-new" name="newStock" type="number" min="0" step="any" class="input tnum" value="${initialVal}" required autofocus>
        </div>
        <div class="card card--compact card--subtle row-between">
          <span class="text-sm text-secondary">Diferencia resultante</span>
          <strong class="tnum text-ok" id="adj-diff-preview">+${formatQtyUnit(roundQty(initialVal - ing.currentStock), ing.unit)}</strong>
        </div>
        <div class="field">
          <label class="field__label" for="adj-reason">Motivo del ajuste (obligatorio) <span class="field__req" aria-hidden="true">*</span></label>
          <input id="adj-reason" name="reason" type="text" class="input" required placeholder="Ej.: Reposición de compra de urgencia / corrección de depósito">
        </div>
        <label class="check-field">
          <input type="checkbox" id="adj-confirm" required>
          <span>Confirmo que el nuevo saldo fue verificado físicamente.</span>
        </label>
      </form>
    `,
    footerHtml: `
      <button type="button" class="btn" data-modal-close>Cancelar</button>
      <button type="submit" form="adj-form" class="btn btn--primary">Confirmar ajuste</button>
    `,
    onMount(dlg) {
      const newInp = dlg.querySelector('#adj-new');
      const diffEl = dlg.querySelector('#adj-diff-preview');
      newInp.addEventListener('input', () => {
        const diff = roundQty(Number(newInp.value || 0) - ing.currentStock);
        diffEl.textContent = `${diff > 0 ? '+' : ''}${formatQtyUnit(diff, ing.unit)}`;
        diffEl.className = `tnum ${diff > 0 ? 'text-ok' : diff < 0 ? 'text-danger' : 'text-muted'}`;
      });

      dlg.querySelector('#adj-form').addEventListener('submit', (e) => {
        e.preventDefault();
        if (!dlg.querySelector('#adj-confirm').checked) {
          dlg.querySelector('#adj-err').innerHTML = banner({ variant: 'warn', body: 'Marcá la casilla de verificación para confirmar.' });
          return;
        }
        const res = adjustIngredientStock(ing.id, newInp.value, dlg.querySelector('#adj-reason').value);
        if (!res.ok) {
          dlg.querySelector('#adj-err').innerHTML = banner({ variant: 'danger', body: res.error });
          return;
        }
        dlg.close('ok');
        showToast(`Stock de ${ing.name} ajustado correctamente.`, 'ok');
      });
    },
  });
}

function openWasteModal(ing) {
  openModal({
    title: `Registrar merma · ${ing.name}`,
    subtitle: `Disponible: ${formatQtyUnit(ing.currentStock, ing.unit)}`,
    lightDismiss: false,
    bodyHtml: `
      <form id="waste-form" class="stack" novalidate>
        <div id="waste-err"></div>
        <div class="form-grid">
          <div class="field">
            <label class="field__label" for="waste-qty">Cantidad perdida (${ing.unit}) <span class="field__req" aria-hidden="true">*</span></label>
            <input id="waste-qty" type="number" min="0.01" max="${ing.currentStock}" step="any" class="input tnum" required autofocus>
          </div>
          <div class="field">
            <label class="field__label" for="waste-cat">Categoría de merma</label>
            <select id="waste-cat" class="select">
              ${WASTE_CATEGORIES.map((w) => `<option value="${w.id}">${escapeHtml(w.label)}</option>`).join('')}
            </select>
          </div>
        </div>
        <div class="field">
          <label class="field__label" for="waste-reason">Motivo (obligatorio) <span class="field__req" aria-hidden="true">*</span></label>
          <input id="waste-reason" type="text" class="input" required placeholder="Ej.: Envase roto al abrir cámara">
        </div>
        <label class="check-field">
          <input type="checkbox" id="waste-confirm" required>
          <span>Confirmo descontar esta merma del stock disponible.</span>
        </label>
      </form>
    `,
    footerHtml: `
      <button type="button" class="btn" data-modal-close>Cancelar</button>
      <button type="submit" form="waste-form" class="btn btn--danger">Registrar merma</button>
    `,
    onMount(dlg) {
      dlg.querySelector('#waste-form').addEventListener('submit', (e) => {
        e.preventDefault();
        if (!dlg.querySelector('#waste-confirm').checked) {
          dlg.querySelector('#waste-err').innerHTML = banner({ variant: 'warn', body: 'Marcá la casilla de confirmación antes de registrar la merma.' });
          return;
        }
        const res = registerIngredientWaste(
          ing.id,
          dlg.querySelector('#waste-qty').value,
          dlg.querySelector('#waste-cat').value,
          dlg.querySelector('#waste-reason').value
        );
        if (!res.ok) {
          dlg.querySelector('#waste-err').innerHTML = banner({ variant: 'danger', body: res.error });
          return;
        }
        dlg.close('ok');
        showToast(`Merma registrada para ${ing.name}.`, 'warn');
      });
    },
  });
}

function openIngredientModal(ing) {
  const state = getState();
  const unitLocked = Boolean(
    ing && (ing.currentStock !== 0 || state.stockMovements.some((m) => m.ingredientId === ing.id))
  );
  openModal({
    title: ing ? `Editar ingrediente · ${ing.name}` : 'Nuevo ingrediente',
    bodyHtml: `
      <form id="ing-form" class="stack" novalidate>
        <div id="ing-err"></div>
        <div class="field">
          <label class="field__label" for="ing-name">Nombre <span class="field__req" aria-hidden="true">*</span></label>
          <input id="ing-name" type="text" class="input" value="${escapeHtml(ing?.name || '')}" required autofocus>
        </div>
        <div class="form-grid">
          <div class="field">
            <label class="field__label" for="ing-unit">Unidad base</label>
            <select id="ing-unit" class="select" ${unitLocked ? 'disabled' : ''}>
              ${UNITS.map((u) => `<option value="${u}" ${ing?.unit === u ? 'selected' : ''}>${u}</option>`).join('')}
            </select>
            ${unitLocked ? '<span class="field__hint">No se puede cambiar si el ingrediente tiene stock o movimientos.</span>' : ''}
          </div>
          <div class="field">
            <label class="field__label" for="ing-min">Stock mínimo (alerta)</label>
            <input id="ing-min" type="number" min="0" step="any" class="input tnum" value="${ing?.minStock ?? 1}">
          </div>
        </div>
        ${!ing ? `
          <div class="form-grid">
            <div class="field">
              <label class="field__label" for="ing-init">Stock inicial</label>
              <input id="ing-init" type="number" min="0" step="any" class="input tnum" value="0">
            </div>
            <div class="field">
              <label class="field__label" for="ing-price">Precio referencia ($ / unidad)</label>
              <input id="ing-price" type="number" min="0" step="any" class="input tnum" value="0">
            </div>
          </div>
        ` : `
          <label class="check-field">
            <input type="checkbox" id="ing-active" ${ing.active ? 'checked' : ''}>
            <span>Ingrediente activo (disponible para nuevas recetas y alertas)</span>
          </label>
        `}
      </form>
    `,
    footerHtml: `
      <button type="button" class="btn" data-modal-close>Cancelar</button>
      <button type="submit" form="ing-form" class="btn btn--primary">Guardar ingrediente</button>
    `,
    onMount(dlg) {
      dlg.querySelector('#ing-form').addEventListener('submit', (e) => {
        e.preventDefault();
        const res = saveIngredient({
          id: ing?.id,
          name: dlg.querySelector('#ing-name').value,
          unit: dlg.querySelector('#ing-unit').value,
          minStock: dlg.querySelector('#ing-min').value,
          initialStock: dlg.querySelector('#ing-init')?.value || 0,
          lastUnitPrice: dlg.querySelector('#ing-price')?.value || 0,
          active: ing ? dlg.querySelector('#ing-active').checked : true,
        });
        if (!res.ok) {
          dlg.querySelector('#ing-err').innerHTML = banner({ variant: 'danger', body: res.error });
          return;
        }
        dlg.close('ok');
        showToast(ing ? 'Ingrediente actualizado.' : 'Ingrediente creado.', 'ok');
      });
    },
  });
}
