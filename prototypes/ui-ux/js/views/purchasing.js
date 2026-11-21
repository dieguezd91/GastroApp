import {
  getState,
  addSupplier,
  updateSupplier,
  deleteSupplier,
  addInvoice,
  deleteInvoice,
} from '../state/store.js';
import { formatARS, formatDate, formatNum, formatQtyUnit, escapeHtml, convertUnit, roundMoney, getCompatibleUnits } from '../utils/format.js';
import { icon } from '../utils/icons.js';
import { badge, banner, emptyState, loadingSkeleton, openModal, openConfirmModal } from '../utils/ui.js';
import { showToast } from '../utils/a11y.js';

let activeTab = 'invoices';

export function renderPurchasing(container) {
  const state = getState();
  if (state.demo.simulateLoading) {
    container.innerHTML = `
      <div class="page-header"><h1 id="page-heading" tabindex="-1">Proveedores y facturas</h1></div>
      ${loadingSkeleton(4)}
    `;
    return;
  }
  const invoices = state.demo.simulateEmpty ? [] : state.invoices;

  container.innerHTML = `
    <div class="page-header">
      <div>
        <h1 id="page-heading" tabindex="-1">Proveedores y facturas</h1>
        <p class="page-header__subtitle">Al registrar una factura de compra se suma stock automáticamente en unidad base y se actualiza el último precio para el costeo de recetas.</p>
      </div>
      <div class="page-header__actions">
        ${activeTab === 'invoices'
          ? `<button type="button" class="btn btn--primary" id="btn-new-inv">${icon('plus', 17)} Nueva factura</button>`
          : `<button type="button" class="btn btn--primary" id="btn-new-sup">${icon('plus', 17)} Nuevo proveedor</button>`}
      </div>
    </div>

    <div class="tablist" role="tablist" aria-label="Secciones de compras">
      <button type="button" class="tab" role="tab" id="tab-inv" aria-selected="${activeTab === 'invoices'}" data-pur-tab="invoices">
        ${icon('receipt', 16)}
        <span>Facturas (${invoices.length})</span>
      </button>
      <button type="button" class="tab" role="tab" id="tab-sup" aria-selected="${activeTab === 'suppliers'}" data-pur-tab="suppliers">
        ${icon('suppliers', 16)}
        <span>Proveedores (${state.suppliers.length})</span>
      </button>
    </div>

    ${activeTab === 'invoices' ? `
      <div class="stack" role="tabpanel" aria-labelledby="tab-inv">
        ${invoices.length === 0
          ? emptyState({
              iconName: 'receipt',
              title: 'Sin facturas registradas',
              description: 'Cargá tu primera factura de proveedor con uno o varios insumos para ingresar stock y precios.',
              actionHtml: `<button type="button" class="btn btn--primary" id="btn-empty-new-inv">Registrar factura</button>`,
            })
          : `<div class="table-wrapper" tabindex="0" role="region" aria-label="Facturas de proveedores">
              <table class="data-table data-table--stack">
                <thead>
                  <tr>
                    <th scope="col">Comprobante</th>
                    <th scope="col">Fecha</th>
                    <th scope="col">Proveedor</th>
                    <th scope="col">Ítems ingresados</th>
                    <th scope="col" class="col-num">Total factura</th>
                    <th scope="col" class="col-actions">Acciones</th>
                  </tr>
                </thead>
                <tbody>
                  ${invoices.map((inv) => {
                    const sup = state.suppliers.find((s) => s.id === inv.supplierId);
                    const total = inv.items.reduce((a, it) => a + it.quantity * it.unitPrice, 0);
                    return `
                      <tr>
                        <th scope="row">
                          <div>${escapeHtml(inv.invoiceNumber)}</div>
                          ${inv.notes ? `<div class="text-xs text-muted fw-600">${escapeHtml(inv.notes)}</div>` : ''}
                        </th>
                        <td data-label="Fecha">${formatDate(inv.date)}</td>
                        <td data-label="Proveedor">${escapeHtml(sup?.name || 'Proveedor')}</td>
                        <td data-label="Ítems">
                          ${inv.items.map((it) => {
                            const ing = state.ingredients.find((i) => i.id === it.ingredientId);
                            return `<div class="text-xs">${escapeHtml(ing?.name || 'Ingrediente')}: <strong>${formatQtyUnit(it.quantity, it.unit)}</strong> × ${formatARS(it.unitPrice)}</div>`;
                          }).join('')}
                        </td>
                        <td data-label="Total" class="col-num fw-700">${formatARS(total)}</td>
                        <td class="col-actions">
                          <button type="button" class="btn btn--ghost btn--icon" data-del-inv="${inv.id}" aria-label="Eliminar factura ${escapeHtml(inv.invoiceNumber)}">
                            ${icon('trash', 15)}
                          </button>
                        </td>
                      </tr>
                    `;
                  }).join('')}
                </tbody>
              </table>
            </div>`}
      </div>
    ` : `
      <div class="stack" role="tabpanel" aria-labelledby="tab-sup">
        ${banner({
          variant: 'info',
          title: 'Modelo actual simplificado',
          body: 'En la versión actual de GastroApp, los proveedores registran únicamente su nombre. Campos como CUIT, teléfono y condiciones comerciales quedan para futuras iteraciones.',
        })}
        <div class="table-wrapper" tabindex="0" role="region" aria-label="Listado de proveedores">
          <table class="data-table data-table--stack">
            <thead>
              <tr>
                <th scope="col">Proveedor</th>
                <th scope="col" class="col-num">Facturas registradas</th>
                <th scope="col" class="col-actions">Acciones</th>
              </tr>
            </thead>
            <tbody>
              ${state.suppliers.map((s) => `
                <tr>
                  <th scope="row">${escapeHtml(s.name)}</th>
                  <td data-label="Facturas" class="col-num">${state.invoices.filter((i) => i.supplierId === s.id).length}</td>
                  <td class="col-actions">
                    <div class="flex-wrap-gap" style="justify-content: flex-end;">
                      <button type="button" class="btn btn--sm" data-edit-sup="${s.id}">Editar</button>
                      <button type="button" class="btn btn--danger-outline btn--sm" data-del-sup="${s.id}">Eliminar</button>
                    </div>
                  </td>
                </tr>
              `).join('')}
            </tbody>
          </table>
        </div>
      </div>
    `}
  `;

  container.querySelectorAll('[data-pur-tab]').forEach((t) => {
    t.addEventListener('click', () => {
      activeTab = t.dataset.purTab;
      renderPurchasing(container);
    });
  });
  container.querySelector('#btn-new-inv')?.addEventListener('click', () => openInvoiceModal());
  container.querySelector('#btn-empty-new-inv')?.addEventListener('click', () => openInvoiceModal());
  container.querySelector('#btn-new-sup')?.addEventListener('click', () => openSupplierModal(null));

  container.querySelectorAll('[data-del-inv]').forEach((btn) => {
    btn.addEventListener('click', () => {
      const inv = state.invoices.find((i) => i.id === Number(btn.dataset.delInv));
      if (!inv) return;
      openConfirmModal({
        title: `¿Eliminar factura ${inv.invoiceNumber}?`,
        message: 'Atención: al igual que en el contrato actual de GastroApp, eliminar una factura NO revierte automáticamente el stock ingresado previamente.',
        confirmLabel: 'Eliminar factura',
        onConfirm: () => {
          deleteInvoice(inv.id);
          showToast(`Factura ${inv.invoiceNumber} eliminada.`, 'warn');
        },
      });
    });
  });

  container.querySelectorAll('[data-edit-sup]').forEach((btn) => {
    btn.addEventListener('click', () => {
      const sup = state.suppliers.find((s) => s.id === Number(btn.dataset.editSup));
      if (sup) openSupplierModal(sup);
    });
  });

  container.querySelectorAll('[data-del-sup]').forEach((btn) => {
    btn.addEventListener('click', () => {
      const res = deleteSupplier(Number(btn.dataset.delSup));
      if (!res.ok) showToast(res.error, 'danger');
      else showToast('Proveedor eliminado.', 'ok');
    });
  });
}

function openSupplierModal(sup) {
  openModal({
    title: sup ? `Editar proveedor · ${sup.name}` : 'Nuevo proveedor',
    bodyHtml: `
      <form id="sup-form" class="stack" novalidate>
        <div id="sup-err"></div>
        <div class="field">
          <label class="field__label" for="sup-name">Nombre del proveedor <span class="field__req" aria-hidden="true">*</span></label>
          <input id="sup-name" type="text" class="input" required value="${escapeHtml(sup?.name || '')}" placeholder="Ej.: Molino Harinero del Oeste" autofocus>
        </div>
      </form>
    `,
    footerHtml: `
      <button type="button" class="btn" data-modal-close>Cancelar</button>
      <button type="submit" form="sup-form" class="btn btn--primary">${sup ? 'Guardar cambios' : 'Guardar proveedor'}</button>
    `,
    onMount(dlg) {
      dlg.querySelector('#sup-form').addEventListener('submit', (e) => {
        e.preventDefault();
        const val = dlg.querySelector('#sup-name').value;
        const res = sup ? updateSupplier(sup.id, val) : addSupplier(val);
        if (!res.ok) {
          dlg.querySelector('#sup-err').innerHTML = banner({ variant: 'danger', body: res.error });
          return;
        }
        dlg.close('ok');
        showToast(sup ? 'Proveedor actualizado.' : 'Proveedor agregado.', 'ok');
      });
    },
  });
}

function openInvoiceModal() {
  const state = getState();
  const activeIngredients = state.ingredients.filter((i) => i.active);
  const todayIso = new Date().toISOString().slice(0, 10);
  const draft = {
    date: todayIso,
    supplierId: state.suppliers[0]?.id || '',
    invoiceNumber: '',
    notes: '',
    items: [],
  };

  let pickIngId = activeIngredients[0]?.id || '';
  let pickQty = '';
  let pickUnit = activeIngredients[0]?.unit || 'kg';
  let pickPrice = activeIngredients[0]?.lastUnitPrice || '';
  let inlineError = '';

  const getPickedIng = () => activeIngredients.find((i) => i.id === Number(pickIngId)) || activeIngredients[0];

  const computeInvoiceItemPreview = () => {
    const ing = getPickedIng();
    if (!ing) return '';
    const qty = roundMoney(pickQty);
    const price = roundMoney(pickPrice);
    if (Number.isNaN(qty) || qty <= 0) {
      return `Se sumará al stock de ${ing.name} en ${ing.unit}.`;
    }
    const conv = convertUnit(qty, pickUnit, ing.unit);
    const sub = !Number.isNaN(price) && price > 0 ? ` · Subtotal: ${formatARS(roundMoney(qty * price))}` : '';
    return `Impacto en stock: +${formatNum(roundMoney(conv.value))} ${ing.unit}${sub}`;
  };

  openModal({
    title: 'Registrar factura de compra',
    subtitle: 'La unidad se restringe automáticamente a la familia del ingrediente elegido para evitar errores de carga.',
    size: 'lg',
    lightDismiss: false,
    bodyHtml: '<div id="inv-modal-body"></div>',
    footerHtml: `
      <button type="button" class="btn" data-modal-close>Cancelar</button>
      <button type="button" class="btn btn--collect" id="inv-save-btn">Guardar factura e ingresar stock</button>
    `,
    onMount(dlg) {
      const body = dlg.querySelector('#inv-modal-body');
      const saveBtn = dlg.querySelector('#inv-save-btn');

      const renderForm = () => {
        const pickedIng = getPickedIng();
        const compatUnits = getCompatibleUnits(pickedIng?.unit);
        if (!compatUnits.includes(pickUnit)) {
          pickUnit = pickedIng?.unit || compatUnits[0];
        }
        const runningTotal = roundMoney(draft.items.reduce((a, it) => a + it.quantity * it.unitPrice, 0));

        body.innerHTML = `
          <div class="stack">
            ${inlineError ? banner({ variant: 'danger', body: escapeHtml(inlineError) }) : ''}

            <div class="form-grid">
              <div class="field">
                <label class="field__label" for="inv-date">Fecha <span class="field__req" aria-hidden="true">*</span></label>
                <input id="inv-date" type="date" class="input" value="${escapeHtml(draft.date)}" required>
              </div>
              <div class="field">
                <label class="field__label" for="inv-sup">Proveedor <span class="field__req" aria-hidden="true">*</span></label>
                <select id="inv-sup" class="select" required>
                  ${state.suppliers.map((s) => `<option value="${s.id}" ${Number(draft.supplierId) === s.id ? 'selected' : ''}>${escapeHtml(s.name)}</option>`).join('')}
                </select>
              </div>
              <div class="field">
                <label class="field__label" for="inv-num">Número de factura (opcional)</label>
                <input id="inv-num" type="text" class="input" value="${escapeHtml(draft.invoiceNumber)}" placeholder="Ej.: FC-A 0003-00019400">
              </div>
            </div>

            <div class="field">
              <label class="field__label" for="inv-notes">Notas (opcional)</label>
              <input id="inv-notes" type="text" class="input" value="${escapeHtml(draft.notes)}" placeholder="Ej.: Reposición semanal, aumento de lista 12%">
            </div>

            <fieldset class="fieldset stack stack--sm">
              <legend>Ítems de la factura</legend>
              <div class="form-grid" style="align-items: end;">
                <div class="field">
                  <label class="field__label" for="inv-pick-ing">Ingrediente</label>
                  <select id="inv-pick-ing" class="select select--compact">
                    ${activeIngredients.map((i) => `<option value="${i.id}" ${Number(pickIngId) === i.id ? 'selected' : ''}>${escapeHtml(i.name)} (actual: ${i.currentStock} ${i.unit})</option>`).join('')}
                  </select>
                </div>
                <div class="field">
                  <label class="field__label" for="inv-pick-qty">Cantidad</label>
                  <input id="inv-pick-qty" type="number" min="0.01" step="any" class="input input--compact tnum" value="${escapeHtml(pickQty)}" placeholder="Ej.: 5">
                </div>
                <div class="field">
                  <span class="field__label" id="inv-unit-lbl">Unidad (${compatUnits.length === 1 ? 'fija' : 'compatible'})</span>
                  ${compatUnits.length === 1
                    ? `<span class="unit-static" aria-labelledby="inv-unit-lbl">${escapeHtml(compatUnits[0])}</span>`
                    : `<div class="unit-toggle" role="radiogroup" aria-labelledby="inv-unit-lbl">
                        ${compatUnits.map((u) => `
                          <label class="unit-toggle__opt">
                            <input type="radio" name="inv-pick-unit" value="${u}" class="visually-hidden" ${pickUnit === u ? 'checked' : ''}>
                            <span>${u}</span>
                          </label>
                        `).join('')}
                      </div>`}
                </div>
                <div class="field">
                  <label class="field__label" for="inv-pick-price">Precio por ${escapeHtml(pickUnit)} ($)</label>
                  <input id="inv-pick-price" type="number" min="0.01" step="any" class="input input--compact tnum" value="${escapeHtml(pickPrice)}" placeholder="Ej.: 2950">
                </div>
              </div>
              <div class="live-preview-strip" id="inv-line-preview" aria-live="polite">
                <span>${escapeHtml(computeInvoiceItemPreview())}</span>
              </div>
              <div>
                <button type="button" class="btn btn--primary btn--sm" id="inv-add-item-btn">
                  ${icon('plus', 15)}
                  <span>Agregar ítem a la factura</span>
                </button>
              </div>

              ${draft.items.length === 0
                ? `<p class="text-sm text-muted">Todavía no agregaste ítems a esta factura.</p>`
                : `<div class="table-wrapper mt-2" tabindex="0" role="region" aria-label="Ítems agregados a la factura">
                    <table class="data-table data-table--stack">
                      <thead>
                        <tr>
                          <th scope="col">Ingrediente</th>
                          <th scope="col" class="col-num">Cantidad</th>
                          <th scope="col" class="col-num">Precio unit.</th>
                          <th scope="col">Impacto en stock</th>
                          <th scope="col" class="col-num">Subtotal</th>
                          <th scope="col" class="col-actions">Quitar</th>
                        </tr>
                      </thead>
                      <tbody>
                        ${draft.items.map((it, idx) => {
                          const ing = state.ingredients.find((i) => i.id === it.ingredientId);
                          const conv = ing ? convertUnit(it.quantity, it.unit, ing.unit) : { ok: false };
                          return `
                            <tr>
                              <th scope="row">${escapeHtml(ing?.name || 'Ingrediente')}</th>
                              <td data-label="Cantidad" class="col-num">${formatQtyUnit(it.quantity, it.unit)}</td>
                              <td data-label="Precio unit." class="col-num">${formatARS(it.unitPrice)}</td>
                              <td data-label="Stock">
                                ${conv.ok
                                  ? badge(`+${formatQtyUnit(roundMoney(conv.value), ing.unit)}`, 'ok', 'check')
                                  : badge(`Unidad incompatible (base: ${ing?.unit})`, 'danger', 'alertOctagon')}
                              </td>
                              <td data-label="Subtotal" class="col-num fw-700">${formatARS(roundMoney(it.quantity * it.unitPrice))}</td>
                              <td class="col-actions">
                                <button type="button" class="btn btn--ghost btn--icon" data-rem-inv-item="${idx}" aria-label="Quitar ítem">
                                  ${icon('trash', 15)}
                                </button>
                              </td>
                            </tr>
                          `;
                        }).join('')}
                      </tbody>
                    </table>
                  </div>`}
            </fieldset>

            <div class="card card--compact card--subtle row-between">
              <span class="text-sm fw-700">Total factura (${draft.items.length} ítem(s))</span>
              <span class="fw-700 tnum" style="font-size: var(--text-xl);">${formatARS(runningTotal)}</span>
            </div>
          </div>
        `;

        body.querySelector('#inv-date').addEventListener('change', (e) => { draft.date = e.target.value; });
        body.querySelector('#inv-sup').addEventListener('change', (e) => { draft.supplierId = Number(e.target.value); });
        body.querySelector('#inv-num').addEventListener('input', (e) => { draft.invoiceNumber = e.target.value; });
        body.querySelector('#inv-notes').addEventListener('input', (e) => { draft.notes = e.target.value; });

        body.querySelector('#inv-pick-ing').addEventListener('change', (e) => {
          pickIngId = Number(e.target.value);
          const ing = state.ingredients.find((i) => i.id === pickIngId);
          if (ing) {
            pickUnit = ing.unit;
            pickPrice = ing.lastUnitPrice || '';
          }
          renderForm();
        });
        const updateInvPreview = () => {
          const el = body.querySelector('#inv-line-preview span');
          if (el) el.textContent = computeInvoiceItemPreview();
        };
        body.querySelector('#inv-pick-qty').addEventListener('input', (e) => { pickQty = e.target.value; updateInvPreview(); });
        body.querySelectorAll('input[name="inv-pick-unit"]').forEach((rad) => {
          rad.addEventListener('change', (e) => {
            pickUnit = e.target.value;
            renderForm();
          });
        });
        body.querySelector('#inv-pick-price').addEventListener('input', (e) => { pickPrice = e.target.value; updateInvPreview(); });

        body.querySelector('#inv-add-item-btn').addEventListener('click', () => {
          const qty = roundMoney(pickQty);
          const price = roundMoney(pickPrice);
          if (Number.isNaN(qty) || qty <= 0) {
            inlineError = 'Ingresá una cantidad mayor a cero para el ítem.';
            renderForm();
            body.querySelector('#inv-pick-qty')?.focus();
            return;
          }
          if (Number.isNaN(price) || price <= 0) {
            inlineError = 'Ingresá un precio unitario mayor a cero.';
            renderForm();
            body.querySelector('#inv-pick-price')?.focus();
            return;
          }
          draft.items.push({
            ingredientId: Number(pickIngId),
            quantity: qty,
            unit: pickUnit,
            unitPrice: price,
          });
          pickQty = '';
          inlineError = '';
          renderForm();
          body.querySelector('#inv-pick-ing')?.focus();
        });

        body.querySelectorAll('[data-rem-inv-item]').forEach((btn) => {
          btn.addEventListener('click', () => {
            draft.items.splice(Number(btn.dataset.remInvItem), 1);
            inlineError = '';
            renderForm();
          });
        });
      };

      saveBtn.addEventListener('click', () => {
        const res = addInvoice(draft);
        if (!res.ok) {
          inlineError = res.error;
          renderForm();
          return;
        }
        dlg.close('ok');
        showToast(`Factura registrada con ${draft.items.length} ítem(s): stock y costos actualizados.`, 'ok');
      });

      renderForm();
    },
  });
}
