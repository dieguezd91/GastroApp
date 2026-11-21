import {
  getState,
  getOpenCashRegister,
  getProductRecipeAvailability,
  computeCartTotals,
  posAddProduct,
  posUpdateLine,
  posRemoveLine,
  posClearCart,
  posSetSaleDiscount,
  posSetFilter,
  completeSale,
} from '../state/store.js';
import { PAYMENT_METHODS, PAYMENT_METHOD_MAP } from '../data/seed.js';
import { formatARS, formatDateTime, escapeHtml, roundMoney } from '../utils/format.js';
import { icon } from '../utils/icons.js';
import { badge, banner, emptyState, loadingSkeleton, openModal } from '../utils/ui.js';
import { showToast } from '../utils/a11y.js';

export function renderPos(container, navigate) {
  const state = getState();
  const openReg = getOpenCashRegister();
  const isAdmin = state.auth.currentUser?.role === 'Admin';
  const totals = computeCartTotals();

  if (state.demo.simulateLoading) {
    container.innerHTML = `
      <div class="page-header">
        <div>
          <h1 id="page-heading" tabindex="-1">Punto de Venta</h1>
          <p class="page-header__subtitle">Cargando catálogo y disponibilidad…</p>
        </div>
      </div>
      ${loadingSkeleton(6)}
    `;
    return;
  }

  const activeProducts = state.demo.simulateEmpty ? [] : state.products.filter((p) => p.isActive);
  const hasUncategorized = activeProducts.some((p) => p.categoryId == null);

  const filteredProducts = activeProducts.filter((p) => {
    const matchesCat =
      state.pos.categoryFilter === 'all' ||
      (state.pos.categoryFilter === 'uncategorized' && p.categoryId == null) ||
      p.categoryId === Number(state.pos.categoryFilter);
    const q = state.pos.search.trim().toLowerCase();
    const matchesSearch = !q || p.name.toLowerCase().includes(q);
    return matchesCat && matchesSearch;
  });

  const qtyInCart = (productId) =>
    state.pos.cart.filter((c) => c.productId === productId).reduce((a, c) => a + c.quantity, 0);

  container.innerHTML = `
    <div class="page-header" style="margin-block-end: var(--space-4);">
      <div>
        <div class="page-header__title-row">
          <h1 id="page-heading" tabindex="-1">Punto de Venta</h1>
          ${openReg ? badge(`Caja abierta · Sesión #${openReg.id}`, 'ok', 'checkCircle') : badge('Caja cerrada', 'danger', 'alertOctagon')}
        </div>
        <p class="page-header__subtitle">Tocá o hacé clic en los productos para sumarlos al pedido. El stock de recetas se valida al confirmar el cobro.</p>
      </div>
      <div class="page-header__actions">
        ${state.pos.lastReceipt ? `<button type="button" class="btn btn--sm" id="btn-last-receipt">${icon('receipt', 16)} Último comprobante (#${state.pos.lastReceipt.id})</button>` : ''}
      </div>
    </div>

    ${!openReg ? `
      <div class="mb-4">
        ${banner({
          variant: 'danger',
          title: 'La caja está cerrada. Abrí la caja para empezar a vender.',
          body: isAdmin
            ? 'Podés armar el carrito como vista previa, pero el cobro permanecerá deshabilitado hasta realizar la apertura.'
            : 'Solicitá a un Administrador que abra la caja del turno para poder cobrar ventas.',
          actionHtml: isAdmin ? `<button type="button" class="btn btn--primary btn--sm" id="pos-go-cash">Ir a Caja</button>` : '',
        })}
      </div>
    ` : ''}

    ${state.pos.lastError ? `
      <div class="mb-4">
        ${banner({
          variant: 'danger',
          title: 'No se pudo completar la venta',
          body: escapeHtml(state.pos.lastError),
        })}
      </div>
    ` : ''}

    <div class="pos-layout">
      <!-- Left: Catalog, Categories & Search -->
      <section class="stack" aria-label="Catálogo de productos">
        <search class="card card--compact stack stack--sm">
          <div class="toolbar">
            <div class="search-wrap">
              <span class="search-wrap__icon">${icon('search', 18)}</span>
              <label for="pos-search" class="visually-hidden">Buscar producto por nombre</label>
              <input
                id="pos-search"
                type="search"
                class="input"
                value="${escapeHtml(state.pos.search)}"
                placeholder="Buscar por nombre (ej.: café, hamburguesa, limonada…)"
                autocorrect="off"
                spellcheck="false"
              >
            </div>
            ${state.pos.search ? `<button type="button" class="btn btn--sm" id="pos-clear-search">Limpiar</button>` : ''}
          </div>

          <div class="chip-row" role="group" aria-label="Filtrar por categoría">
            <button type="button" class="chip" data-cat="all" aria-pressed="${state.pos.categoryFilter === 'all'}">
              Todos (${activeProducts.length})
            </button>
            ${state.categories.map((cat) => {
              const count = activeProducts.filter((p) => p.categoryId === cat.id).length;
              return `
                <button type="button" class="chip" data-cat="${cat.id}" aria-pressed="${String(state.pos.categoryFilter) === String(cat.id)}">
                  ${escapeHtml(cat.name)} (${count})
                </button>
              `;
            }).join('')}
            ${hasUncategorized ? `
              <button type="button" class="chip" data-cat="uncategorized" aria-pressed="${state.pos.categoryFilter === 'uncategorized'}">
                Sin categoría
              </button>
            ` : ''}
          </div>
        </search>

        ${filteredProducts.length === 0
          ? emptyState({
              iconName: 'products',
              title: activeProducts.length === 0 ? 'No hay productos activos' : 'Sin coincidencias en el catálogo',
              description: activeProducts.length === 0
                ? 'Activá o creá productos en el módulo de Catálogo para comenzar a vender.'
                : 'Probá limpiando la búsqueda o eligiendo otra categoría.',
              actionHtml: state.pos.search || state.pos.categoryFilter !== 'all'
                ? `<button type="button" class="btn" id="pos-reset-filters">Mostrar todos los productos</button>`
                : '',
            })
          : `<div class="pos-catalog-grid" role="list">
              ${filteredProducts.map((p) => {
                const cat = state.categories.find((c) => c.id === p.categoryId);
                const rawAvail = getProductRecipeAvailability(p);
                const remAvail = getProductRecipeAvailability(p, { considerCart: true });
                const inCart = qtyInCart(p.id);
                const isRawOut = rawAvail.hasRecipe && rawAvail.maxUnits <= 0;
                const isRemOut = remAvail.hasRecipe && remAvail.maxUnits <= 0;
                const isLow = remAvail.hasRecipe && remAvail.maxUnits > 0 && remAvail.maxUnits <= 3;
                const tileClass = isRawOut
                  ? 'pos-tile--no-stock'
                  : inCart > 0
                    ? 'pos-tile--in-cart'
                    : isLow
                      ? 'pos-tile--low-stock'
                      : '';
                return `
                  <button
                    type="button"
                    class="pos-tile ${tileClass}"
                    data-add-product="${p.id}"
                    ${isRemOut ? 'aria-disabled="true"' : ''}
                    aria-label="${isRemOut ? 'No disponible' : 'Agregar'} ${escapeHtml(p.name)}, ${formatARS(p.price)}${inCart ? `, ${inCart} en carrito` : ''}${isRawOut ? ', sin stock de receta' : isRemOut ? ', stock máximo ya en carrito' : ''}"
                  >
                    <span class="pos-tile__cat">${escapeHtml(cat ? cat.name : 'Sin categoría')}</span>
                    <span class="pos-tile__name">${escapeHtml(p.name)}</span>
                    <span class="pos-tile__foot">
                      <span class="pos-tile__price">${formatARS(p.price)}</span>
                      <span class="flex-wrap-gap" style="gap: 0.3rem;">
                        ${inCart > 0 ? `<span class="pos-tile__qty-pill" aria-hidden="true">${inCart}</span>` : ''}
                        ${isRawOut
                          ? badge('Sin stock', 'danger', 'alertOctagon')
                          : isRemOut
                            ? badge('Tope stock', 'warn', 'alertTriangle')
                            : isLow
                              ? badge(`Quedan ${remAvail.maxUnits}`, 'warn')
                              : ''}
                      </span>
                    </span>
                  </button>
                `;
              }).join('')}
            </div>`}
      </section>

      <!-- Right: Cart & Totals -->
      <aside class="pos-cart" id="pos-cart-panel" aria-label="Carrito de venta actual">
        <div class="pos-cart__header">
          <div class="flex-wrap-gap">
            ${icon('cart', 18)}
            <h2 class="card__title">Carrito (${totals.itemCount})</h2>
          </div>
          ${totals.lines.length > 0
            ? `<button type="button" class="btn btn--ghost btn--sm" id="pos-clear-cart">Vaciar</button>`
            : ''}
        </div>

        ${totals.lines.length === 0
          ? `<div style="padding: var(--space-6) var(--space-4); text-align: center;" class="stack stack--sm">
              <p class="fw-700">El carrito está vacío</p>
              <p class="text-sm text-muted">Seleccioná productos del catálogo para armar el pedido.</p>
            </div>`
          : `<div class="pos-cart__items">
              ${totals.lines.map((line) => {
                const prod = state.products.find((p) => p.id === line.productId);
                const maxForLine = prod ? getProductRecipeAvailability(prod, { considerCart: true, excludeLineId: line.lineId }) : { hasRecipe: false, maxUnits: Infinity };
                const atStockLimit = maxForLine.hasRecipe && line.quantity >= maxForLine.maxUnits;
                return `
                <article class="cart-line" aria-label="${escapeHtml(line.productName)}">
                  <div class="cart-line__top">
                    <div>
                      <p class="fw-700 text-sm">${escapeHtml(line.productName)}</p>
                      <p class="text-xs text-muted tnum">${formatARS(line.unitPrice)} c/u${line.lineDiscount > 0 ? ` · Desc. -${formatARS(line.lineDiscount)}` : ''}${atStockLimit ? ' · Máximo de stock alcanzado' : ''}</p>
                      ${line.note ? `<p class="text-xs text-secondary mt-2"><strong>Obs.:</strong> ${escapeHtml(line.note)}</p>` : ''}
                    </div>
                    <p class="fw-700 tnum">${formatARS(line.lineSubtotal)}</p>
                  </div>

                  <div class="cart-line__controls">
                    <div class="qty-stepper" role="group" aria-label="Cantidad de ${escapeHtml(line.productName)}">
                      <button type="button" class="qty-stepper__btn" data-dec-line="${line.lineId}" aria-label="Restar uno a ${escapeHtml(line.productName)}">${icon('minus', 14)}</button>
                      <input type="number" min="1" ${maxForLine.hasRecipe && Number.isFinite(maxForLine.maxUnits) ? `max="${maxForLine.maxUnits}"` : ''} step="1" class="qty-stepper__val" style="border: 0; width: 2.75rem; background: transparent;" data-qty-input="${line.lineId}" value="${line.quantity}" aria-label="Cantidad exacta de ${escapeHtml(line.productName)}">
                      <button type="button" class="qty-stepper__btn" data-inc-line="${line.lineId}" ${atStockLimit ? 'aria-disabled="true"' : ''} aria-label="Sumar uno a ${escapeHtml(line.productName)}${atStockLimit ? ' (límite de stock alcanzado)' : ''}">${icon('plus', 14)}</button>
                    </div>

                    <div class="flex-wrap-gap">
                      <button type="button" class="btn btn--ghost btn--sm" data-edit-line="${line.lineId}">
                        ${icon('edit', 14)}
                        <span>${line.note || line.discountType !== 'None' ? 'Editar obs. / desc.' : 'Obs. / Desc.'}</span>
                      </button>
                      <button type="button" class="btn btn--ghost btn--icon" data-remove-line="${line.lineId}" aria-label="Quitar ${escapeHtml(line.productName)} del carrito">
                        ${icon('trash', 15)}
                      </button>
                    </div>
                  </div>
                </article>
              `;
              }).join('')}
            </div>

            <!-- General Sale Discount & Totals -->
            <div class="pos-cart__summary">
              <div class="row-between">
                <span class="text-xs fw-700 text-muted" style="text-transform: uppercase;">Descuento general de la venta</span>
                <button type="button" class="btn btn--ghost btn--sm" id="pos-sale-discount-btn">
                  ${icon('tag', 14)}
                  <span>${state.pos.saleDiscountType === 'None' ? 'Aplicar descuento' : 'Modificar descuento'}</span>
                </button>
              </div>

              <div class="stack stack--sm">
                <div class="summary-row">
                  <span class="text-secondary">Subtotal tras desc. de línea</span>
                  <span class="tnum fw-600">${formatARS(totals.subtotal)}</span>
                </div>
                ${totals.saleDiscountAmount > 0 ? `
                  <div class="summary-row text-ok">
                    <span>Descuento de venta (${state.pos.saleDiscountType === 'Percentage' ? `${state.pos.saleDiscountValue}%` : 'Importe fijo'})</span>
                    <span class="tnum fw-700">-${formatARS(totals.saleDiscountAmount)}</span>
                  </div>
                ` : ''}
                <div class="summary-row summary-row--total">
                  <span>Total final</span>
                  <span class="tnum">${formatARS(totals.total)}</span>
                </div>
              </div>

              <button
                type="button"
                id="pos-checkout-btn"
                class="btn btn--collect btn--lg btn--block"
                ${!openReg ? 'disabled' : ''}
              >
                ${icon('checkCircle', 20)}
                <span>Cobrar ${formatARS(totals.total)}</span>
              </button>
            </div>`}
      </aside>
    </div>

    ${totals.lines.length > 0 ? `
      <div class="pos-mobile-bar" role="region" aria-label="Resumen rápido del carrito">
        <div>
          <p class="text-xs" style="color: var(--text-inverse-muted);">${totals.itemCount} ítem(s) en carrito</p>
          <p class="fw-700 tnum" style="font-size: var(--text-lg);">${formatARS(totals.total)}</p>
        </div>
        <button type="button" class="btn btn--collect" id="pos-mobile-checkout" ${!openReg ? 'disabled' : ''}>
          Cobrar ahora
        </button>
      </div>
    ` : ''}
  `;

  // Wire catalog & cart events
  container.querySelector('#pos-go-cash')?.addEventListener('click', () => navigate('cash'));

  const searchInput = container.querySelector('#pos-search');
  searchInput?.addEventListener('input', (e) => {
    const val = e.target.value;
    const pos = e.target.selectionStart;
    posSetFilter(undefined, val);
    const fresh = document.getElementById('pos-search');
    if (fresh) {
      fresh.focus();
      fresh.setSelectionRange(pos, pos);
    }
  });

  container.querySelector('#pos-clear-search')?.addEventListener('click', () => posSetFilter(undefined, ''));
  container.querySelector('#pos-reset-filters')?.addEventListener('click', () => posSetFilter('all', ''));

  container.querySelectorAll('[data-cat]').forEach((btn) => {
    btn.addEventListener('click', () => posSetFilter(btn.dataset.cat, undefined));
  });

  container.querySelectorAll('[data-add-product]').forEach((btn) => {
    btn.addEventListener('click', () => {
      const res = posAddProduct(Number(btn.dataset.addProduct));
      if (!res?.ok && res?.error) {
        showToast(res.error, 'danger');
      }
    });
  });

  container.querySelectorAll('[data-inc-line]').forEach((btn) => {
    btn.addEventListener('click', () => {
      const id = Number(btn.dataset.incLine);
      const line = state.pos.cart.find((l) => l.lineId === id);
      if (line) {
        const res = posUpdateLine(id, { quantity: line.quantity + 1 });
        if (!res?.ok && res?.error) showToast(res.error, 'warn');
      }
    });
  });

  container.querySelectorAll('[data-qty-input]').forEach((inp) => {
    inp.addEventListener('change', () => {
      const id = Number(inp.dataset.qtyInput);
      const val = Math.max(1, Math.floor(Number(inp.value || 1)));
      const res = posUpdateLine(id, { quantity: val });
      if (!res?.ok && res?.error) {
        showToast(res.error, 'warn');
        renderPos(container, navigate);
      }
    });
  });

  container.querySelectorAll('[data-dec-line]').forEach((btn) => {
    btn.addEventListener('click', () => {
      const id = Number(btn.dataset.decLine);
      const line = state.pos.cart.find((l) => l.lineId === id);
      if (line) posUpdateLine(id, { quantity: line.quantity - 1 });
    });
  });

  container.querySelectorAll('[data-remove-line]').forEach((btn) => {
    btn.addEventListener('click', () => posRemoveLine(Number(btn.dataset.removeLine)));
  });

  container.querySelector('#pos-clear-cart')?.addEventListener('click', () => {
    posClearCart();
    showToast('Se vació el carrito.', 'ok');
  });

  container.querySelectorAll('[data-edit-line]').forEach((btn) => {
    btn.addEventListener('click', () => {
      const line = computeCartTotals().lines.find((l) => l.lineId === Number(btn.dataset.editLine));
      if (line) openLineOptionsModal(line);
    });
  });

  container.querySelector('#pos-sale-discount-btn')?.addEventListener('click', () => openSaleDiscountModal());
  container.querySelector('#pos-checkout-btn')?.addEventListener('click', () => openCheckoutModal());
  container.querySelector('#pos-mobile-checkout')?.addEventListener('click', () => openCheckoutModal());
  container.querySelector('#btn-last-receipt')?.addEventListener('click', () => {
    if (state.pos.lastReceipt) openReceiptModal(state.pos.lastReceipt);
  });
}

function openLineOptionsModal(line) {
  const state = getState();
  const isEmployee = state.auth.currentUser?.role === 'Employee';
  const empCap = Number(state.businessSettings.maxEmployeeDiscountPct ?? 100);
  openModal({
    title: line.productName,
    subtitle: `Línea de ${line.quantity} u. · Bruto ${formatARS(line.lineGross)}`,
    bodyHtml: `
      <form id="line-opt-form" class="stack">
        <div id="line-opt-err"></div>
        <div class="field">
          <label class="field__label" for="line-note">Observación (opcional)</label>
          <span id="line-note-hint" class="field__hint">Aplica a toda la cantidad de esta línea (ej.: sin cebolla, punto jugoso).</span>
          <input id="line-note" name="note" type="text" class="input" maxlength="120" value="${escapeHtml(line.note)}" aria-describedby="line-note-hint" placeholder="Ej.: Sin sal, para llevar">
        </div>

        <fieldset class="fieldset stack stack--sm">
          <legend>Descuento de línea</legend>
          <div class="form-grid">
            <div class="field">
              <label class="field__label" for="line-disc-type">Tipo</label>
              <select id="line-disc-type" name="discountType" class="select">
                <option value="None" ${line.discountType === 'None' ? 'selected' : ''}>Sin descuento</option>
                <option value="Percentage" ${line.discountType === 'Percentage' ? 'selected' : ''}>Porcentaje (%)</option>
                <option value="Fixed" ${line.discountType === 'Fixed' ? 'selected' : ''}>Importe fijo ($ por línea)</option>
              </select>
            </div>
            <div class="field">
              <label class="field__label" for="line-disc-val">Valor</label>
              <input id="line-disc-val" name="discountValue" type="number" min="0" step="any" class="input tnum" value="${line.discountValue || ''}" ${line.discountType === 'None' ? 'disabled' : ''} placeholder="0">
            </div>
          </div>
          <p class="text-xs text-muted">El importe fijo se descuenta una vez sobre el bruto total de esta línea (máximo ${formatARS(line.lineGross)}).${isEmployee ? ` Tope rol Empleado: ${empCap}%.` : ''}</p>
        </fieldset>
      </form>
    `,
    footerHtml: `
      <button type="button" class="btn" data-modal-close>Cancelar</button>
      <button type="submit" form="line-opt-form" class="btn btn--primary">Guardar en línea</button>
    `,
    onMount(dialog) {
      const form = dialog.querySelector('#line-opt-form');
      const typeSel = form.querySelector('#line-disc-type');
      const valInp = form.querySelector('#line-disc-val');
      const errSlot = form.querySelector('#line-opt-err');
      typeSel.addEventListener('change', () => {
        valInp.disabled = typeSel.value === 'None';
        if (valInp.disabled) valInp.value = '';
      });
      form.addEventListener('submit', (e) => {
        e.preventDefault();
        errSlot.innerHTML = '';
        const type = typeSel.value;
        const val = type === 'None' ? 0 : Number(valInp.value || 0);
        if (type === 'Percentage' && (val < 0 || val > 100)) {
          errSlot.innerHTML = banner({ variant: 'danger', body: 'El porcentaje debe estar entre 0% y 100%.' });
          return;
        }
        if (type === 'Fixed' && (val < 0 || val > line.lineGross)) {
          errSlot.innerHTML = banner({ variant: 'danger', body: `El importe fijo no puede superar el bruto de línea (${formatARS(line.lineGross)}).` });
          return;
        }
        const effectivePct = type === 'Percentage' ? val : type === 'Fixed' && line.lineGross > 0 ? (val / line.lineGross) * 100 : 0;
        if (isEmployee && effectivePct > empCap + 0.01) {
          errSlot.innerHTML = banner({ variant: 'danger', body: `Tu rol Empleado tiene un tope máximo de descuento del ${empCap}% (definido en Configuración).` });
          return;
        }
        posUpdateLine(line.lineId, {
          note: String(form.querySelector('#line-note').value || '').trim(),
          discountType: type,
          discountValue: val,
        });
        dialog.close('save');
      });
    },
  });
}

function openSaleDiscountModal() {
  const state = getState();
  const totals = computeCartTotals();
  const isEmployee = state.auth.currentUser?.role === 'Employee';
  const empCap = Number(state.businessSettings.maxEmployeeDiscountPct ?? 100);
  const quickPcts = [5, 10, 15, 100].filter((pct) => !isEmployee || pct <= empCap);

  openModal({
    title: 'Descuento de toda la venta',
    subtitle: `Se aplica sobre el subtotal tras descuentos de línea (${formatARS(totals.subtotal)}).${isEmployee ? ` Tope rol Empleado: ${empCap}%.` : ''}`,
    bodyHtml: `
      <form id="sale-disc-form" class="stack">
        <div id="sale-disc-err"></div>
        <div class="form-grid">
          <div class="field">
            <label class="field__label" for="sale-disc-type">Tipo de descuento</label>
            <select id="sale-disc-type" name="type" class="select">
              <option value="None" ${state.pos.saleDiscountType === 'None' ? 'selected' : ''}>Sin descuento</option>
              <option value="Percentage" ${state.pos.saleDiscountType === 'Percentage' ? 'selected' : ''}>Porcentaje (%)</option>
              <option value="Fixed" ${state.pos.saleDiscountType === 'Fixed' ? 'selected' : ''}>Importe fijo ($)</option>
            </select>
          </div>
          <div class="field">
            <label class="field__label" for="sale-disc-val">Valor</label>
            <input id="sale-disc-val" name="value" type="number" min="0" step="any" class="input tnum" value="${state.pos.saleDiscountValue || ''}" ${state.pos.saleDiscountType === 'None' ? 'disabled' : ''} placeholder="Ej.: 10">
          </div>
        </div>
        ${quickPcts.length ? `
          <div class="flex-wrap-gap">
            <span class="text-xs text-muted">Atajos rápidos:</span>
            ${quickPcts.map((pct) => `<button type="button" class="btn btn--sm" data-quick-pct="${pct}">${pct === 100 ? '100% (Cortesía)' : `${pct}%`}</button>`).join('')}
          </div>
        ` : ''}
      </form>
    `,
    footerHtml: `
      <button type="button" class="btn" data-modal-close>Cancelar</button>
      <button type="submit" form="sale-disc-form" class="btn btn--primary">Aplicar</button>
    `,
    onMount(dialog) {
      const form = dialog.querySelector('#sale-disc-form');
      const typeSel = form.querySelector('#sale-disc-type');
      const valInp = form.querySelector('#sale-disc-val');
      const errSlot = form.querySelector('#sale-disc-err');
      typeSel.addEventListener('change', () => {
        valInp.disabled = typeSel.value === 'None';
        if (valInp.disabled) valInp.value = '';
      });
      dialog.querySelectorAll('[data-quick-pct]').forEach((btn) => {
        btn.addEventListener('click', () => {
          typeSel.value = 'Percentage';
          valInp.disabled = false;
          valInp.value = btn.dataset.quickPct;
        });
      });
      form.addEventListener('submit', (e) => {
        e.preventDefault();
        errSlot.innerHTML = '';
        const type = typeSel.value;
        const value = type === 'None' ? 0 : Number(valInp.value || 0);
        const res = posSetSaleDiscount(type, value);
        if (!res.ok) {
          errSlot.innerHTML = banner({ variant: 'danger', body: res.error });
          return;
        }
        dialog.close('save');
      });
    },
  });
}

function openCheckoutModal() {
  const state = getState();
  const totals = computeCartTotals();
  const enabledIds = state.businessSettings.enabledPayments?.length
    ? state.businessSettings.enabledPayments
    : ['Cash'];
  const allowedMethods = PAYMENT_METHODS.filter((m) => enabledIds.includes(m.id));
  const defaultMethod = allowedMethods[0]?.id || 'Cash';

  let payments = totals.total > 0
    ? [{ method: defaultMethod, amount: totals.total, receivedAmount: defaultMethod === 'Cash' ? totals.total : null }]
    : [];
  let inlineError = '';

  const dialog = openModal({
    title: 'Cobrar venta',
    subtitle: `${totals.itemCount} ítem(s) · Total final ${formatARS(totals.total)}`,
    size: 'lg',
    lightDismiss: false,
    bodyHtml: '<div id="checkout-body"></div>',
    footerHtml: `
      <button type="button" class="btn" data-modal-close>Volver al carrito</button>
      <button type="button" class="btn btn--collect btn--lg" id="checkout-confirm-btn">
        ${icon('checkCircle', 18)}
        <span>Confirmar cobro · ${formatARS(totals.total)}</span>
      </button>
    `,
    onMount(dlg) {
      const body = dlg.querySelector('#checkout-body');
      const confirmBtn = dlg.querySelector('#checkout-confirm-btn');

      const renderCheckout = () => {
        const assigned = roundMoney(payments.reduce((a, p) => a + Number(p.amount || 0), 0));
        const remaining = roundMoney(totals.total - assigned);
        const usedMethods = new Set(payments.map((p) => p.method));
        const availableMethods = allowedMethods.filter((m) => !usedMethods.has(m.id));
        const cashRow = payments.find((p) => p.method === 'Cash');
        const cashChange = cashRow ? roundMoney(Number(cashRow.receivedAmount || 0) - Number(cashRow.amount || 0)) : 0;

        body.innerHTML = `
          <div class="stack">
            ${inlineError ? banner({ variant: 'danger', title: 'No se pudo confirmar el cobro', body: escapeHtml(inlineError) }) : ''}

            ${totals.total === 0
              ? banner({
                  variant: 'info',
                  title: 'Total cero: no requiere pagos ni registra un pago.',
                  body: 'El descuento cubre el 100% de la operación. Al confirmar se descontará el stock de las recetas asociadas.',
                })
              : `
                <!-- Quick single-method selector -->
                <div class="stack stack--sm">
                  <p class="text-xs fw-700 text-muted" style="text-transform: uppercase;">Atajo de cobro en un solo medio (${allowedMethods.length} habilitado(s))</p>
                  <div class="flex-wrap-gap">
                    ${allowedMethods.map((m) => `
                      <button type="button" class="chip" data-single-method="${m.id}" aria-pressed="${payments.length === 1 && payments[0].method === m.id}">
                        ${escapeHtml(m.short)}
                      </button>
                    `).join('')}
                  </div>
                </div>

                <!-- Payment lines (supports mixed payments) -->
                <div class="stack stack--sm">
                  <div class="row-between">
                    <h3 class="card__title">Medios de pago (${payments.length})</h3>
                    ${availableMethods.length > 0 ? `
                      <button type="button" class="btn btn--sm" id="add-payment-row">
                        ${icon('plus', 15)}
                        <span>Agregar pago mixto</span>
                      </button>
                    ` : ''}
                  </div>

                  ${payments.map((p, idx) => `
                    <div class="payment-line" data-pay-idx="${idx}">
                      <div class="field">
                        <label class="field__label" for="pay-method-${idx}">Medio de pago</label>
                        <select id="pay-method-${idx}" class="select select--compact" data-pay-method="${idx}">
                          ${allowedMethods.map((m) => {
                            const disabled = usedMethods.has(m.id) && m.id !== p.method;
                            return `<option value="${m.id}" ${m.id === p.method ? 'selected' : ''} ${disabled ? 'disabled' : ''}>${escapeHtml(m.label)}</option>`;
                          }).join('')}
                        </select>
                      </div>

                      <div class="field">
                        <label class="field__label" for="pay-amt-${idx}">Importe aplicado ($)</label>
                        <input id="pay-amt-${idx}" type="number" min="0" step="any" class="input input--compact tnum" data-pay-amount="${idx}" value="${p.amount}">
                      </div>

                      <div>
                        ${payments.length > 1
                          ? `<button type="button" class="btn btn--ghost btn--sm" data-remove-pay="${idx}" aria-label="Quitar ${escapeHtml(PAYMENT_METHOD_MAP[p.method]?.label || '')}">${icon('trash', 15)} Quitar</button>`
                          : `<span class="text-xs text-muted">Pago único</span>`}
                      </div>

                      ${p.method === 'Cash' ? `
                        <div style="grid-column: 1 / -1;" class="stack stack--sm">
                          <div class="form-grid">
                            <div class="field">
                              <label class="field__label" for="pay-received-${idx}">Efectivo recibido (obligatorio) <span class="field__req" aria-hidden="true">*</span></label>
                              <input id="pay-received-${idx}" type="number" min="0" step="any" class="input input--compact tnum" data-pay-received="${idx}" value="${p.receivedAmount ?? ''}" placeholder="Ej.: 20000">
                            </div>
                            <div class="field">
                              <span class="field__label">Billetes rápidos</span>
                              <div class="flex-wrap-gap">
                                <button type="button" class="btn btn--sm" data-bill-exact="${idx}">Exacto</button>
                                <button type="button" class="btn btn--sm" data-bill-val="${idx}" data-bill="10000">$10.000</button>
                                <button type="button" class="btn btn--sm" data-bill-val="${idx}" data-bill="20000">$20.000</button>
                                <button type="button" class="btn btn--sm" data-bill-val="${idx}" data-bill="50000">$50.000</button>
                              </div>
                            </div>
                          </div>
                          <div id="cash-change-slot">
                            ${cashChange >= 0
                              ? `<div class="change-box"><span>Vuelto a entregar</span><span class="tnum" style="font-size: var(--text-lg);">${formatARS(cashChange)}</span></div>`
                              : banner({ variant: 'danger', body: `Faltan ${formatARS(Math.abs(cashChange))} para cubrir el importe en efectivo.` })}
                          </div>
                        </div>
                      ` : ''}
                    </div>
                  `).join('')}
                </div>

                <!-- Allocation balance strip -->
                <div class="card card--compact card--subtle">
                  <div class="grid-kpi" style="grid-template-columns: repeat(3, 1fr); gap: var(--space-2);">
                    <div>
                      <p class="text-xs text-muted fw-700">Asignado</p>
                      <p class="fw-700 tnum" id="checkout-assigned">${formatARS(assigned)}</p>
                    </div>
                    <div>
                      <p class="text-xs text-muted fw-700">Total venta</p>
                      <p class="fw-700 tnum">${formatARS(totals.total)}</p>
                    </div>
                    <div>
                      <p class="text-xs text-muted fw-700">Restante</p>
                      <p class="fw-700 tnum ${Math.abs(remaining) > 0.01 ? 'text-danger' : 'text-ok'}" id="checkout-remaining">${formatARS(remaining)}</p>
                    </div>
                  </div>
                </div>
              `}
          </div>
        `;

        // Bind checkout controls
        body.querySelectorAll('[data-single-method]').forEach((btn) => {
          btn.addEventListener('click', () => {
            const m = btn.dataset.singleMethod;
            payments = [{ method: m, amount: totals.total, receivedAmount: m === 'Cash' ? totals.total : null }];
            inlineError = '';
            renderCheckout();
          });
        });

        body.querySelector('#add-payment-row')?.addEventListener('click', () => {
          const next = availableMethods[0];
          if (!next) return;
          let nextAmt = remaining > 0 ? remaining : roundMoney(totals.total / 2);
          if (remaining <= 0 && payments.length === 1) {
            payments[0].amount = roundMoney(totals.total - nextAmt);
            if (payments[0].method === 'Cash') payments[0].receivedAmount = payments[0].amount;
          }
          payments.push({
            method: next.id,
            amount: nextAmt,
            receivedAmount: next.id === 'Cash' ? nextAmt : null,
          });
          inlineError = '';
          renderCheckout();
        });

        body.querySelectorAll('[data-pay-method]').forEach((sel) => {
          sel.addEventListener('change', (e) => {
            const idx = Number(sel.dataset.payMethod);
            payments[idx].method = e.target.value;
            payments[idx].receivedAmount = e.target.value === 'Cash' ? payments[idx].amount : null;
            renderCheckout();
          });
        });

        const syncCheckoutLiveSummary = () => {
          const nextAssigned = roundMoney(payments.reduce((a, p) => a + Number(p.amount || 0), 0));
          const nextRemaining = roundMoney(totals.total - nextAssigned);
          const assignedEl = body.querySelector('#checkout-assigned');
          const remEl = body.querySelector('#checkout-remaining');
          if (assignedEl) assignedEl.textContent = formatARS(nextAssigned);
          if (remEl) {
            remEl.textContent = formatARS(nextRemaining);
            remEl.className = `fw-700 tnum ${Math.abs(nextRemaining) > 0.01 ? 'text-danger' : 'text-ok'}`;
          }
          const cashItem = payments.find((p) => p.method === 'Cash');
          const slot = body.querySelector('#cash-change-slot');
          if (cashItem && slot) {
            const diffCash = roundMoney(Number(cashItem.receivedAmount || 0) - Number(cashItem.amount || 0));
            slot.innerHTML = diffCash >= 0
              ? `<div class="change-box"><span>Vuelto a entregar</span><span class="tnum" style="font-size: var(--text-lg);">${formatARS(diffCash)}</span></div>`
              : banner({ variant: 'danger', body: `Faltan ${formatARS(Math.abs(diffCash))} para cubrir el importe en efectivo.` });
          }
        };

        body.querySelectorAll('[data-pay-amount]').forEach((inp) => {
          inp.addEventListener('input', (e) => {
            const idx = Number(inp.dataset.payAmount);
            payments[idx].amount = Math.max(0, roundMoney(e.target.value || 0));
            syncCheckoutLiveSummary();
          });
          inp.addEventListener('change', (e) => {
            const idx = Number(inp.dataset.payAmount);
            payments[idx].amount = Math.max(0, roundMoney(e.target.value || 0));
            if (payments[idx].method === 'Cash' && payments[idx].receivedAmount < payments[idx].amount) {
              payments[idx].receivedAmount = payments[idx].amount;
            }
            renderCheckout();
          });
        });

        body.querySelectorAll('[data-pay-received]').forEach((inp) => {
          inp.addEventListener('input', (e) => {
            const idx = Number(inp.dataset.payReceived);
            payments[idx].receivedAmount = roundMoney(e.target.value || 0);
            syncCheckoutLiveSummary();
          });
          inp.addEventListener('change', (e) => {
            const idx = Number(inp.dataset.payReceived);
            payments[idx].receivedAmount = roundMoney(e.target.value || 0);
            renderCheckout();
          });
        });

        body.querySelectorAll('[data-bill-exact]').forEach((btn) => {
          btn.addEventListener('click', () => {
            const idx = Number(btn.dataset.billExact);
            payments[idx].receivedAmount = payments[idx].amount;
            renderCheckout();
          });
        });

        body.querySelectorAll('[data-bill-val]').forEach((btn) => {
          btn.addEventListener('click', () => {
            const idx = Number(btn.dataset.billVal);
            payments[idx].receivedAmount = Number(btn.dataset.bill);
            renderCheckout();
          });
        });

        body.querySelectorAll('[data-remove-pay]').forEach((btn) => {
          btn.addEventListener('click', () => {
            payments.splice(Number(btn.dataset.removePay), 1);
            renderCheckout();
          });
        });
      };

      confirmBtn.addEventListener('click', () => {
        const res = completeSale(payments);
        if (!res.ok) {
          inlineError = res.error;
          renderCheckout();
          return;
        }
        dlg.close('confirmed');
        openReceiptModal(res.sale);
      });

      renderCheckout();
    },
  });

  return dialog;
}

function openReceiptModal(sale) {
  const cashPay = sale.payments.find((p) => p.method === 'Cash');
  openModal({
    title: `Venta #${sale.id} registrada`,
    subtitle: `${formatDateTime(sale.date)} · Operador: ${sale.operator}`,
    bodyHtml: `
      <div class="stack">
        ${banner({
          variant: 'ok',
          title: 'Cobro confirmado correctamente',
          body: sale.stockConsumptions.length
            ? `Se descontó automáticamente el stock de ${sale.stockConsumptions.length} ingrediente(s) de recetas asociadas.`
            : 'Venta registrada en la sesión de caja actual.',
        })}

        <div class="table-wrapper" tabindex="0" role="region" aria-label="Detalle de productos vendidos">
          <table class="data-table">
            <thead>
              <tr>
                <th scope="col">Producto</th>
                <th scope="col" class="col-num">Cant.</th>
                <th scope="col" class="col-num">Subtotal</th>
              </tr>
            </thead>
            <tbody>
              ${sale.items.map((it) => `
                <tr>
                  <th scope="row">
                    ${escapeHtml(it.productName)}
                    ${it.note ? `<div class="text-xs text-muted fw-600">Obs.: ${escapeHtml(it.note)}</div>` : ''}
                  </th>
                  <td class="col-num">${it.quantity}</td>
                  <td class="col-num fw-700">${formatARS(it.lineSubtotal)}</td>
                </tr>
              `).join('')}
            </tbody>
          </table>
        </div>

        <div class="card card--compact card--subtle stack stack--sm">
          ${sale.saleDiscountAmount > 0 ? `<div class="summary-row"><span>Descuento general</span><span class="tnum text-ok">-${formatARS(sale.saleDiscountAmount)}</span></div>` : ''}
          <div class="summary-row fw-700" style="font-size: var(--text-lg);">
            <span>Total cobrado</span>
            <span class="tnum">${formatARS(sale.total)}</span>
          </div>
          ${sale.payments.map((p) => `
            <div class="summary-row text-sm text-secondary">
              <span>${escapeHtml(PAYMENT_METHOD_MAP[p.method]?.label || p.method)}${p.method === 'Cash' && p.receivedAmount != null ? ` (recibido ${formatARS(p.receivedAmount)})` : ''}</span>
              <span class="tnum">${formatARS(p.amount)}</span>
            </div>
          `).join('')}
          ${cashPay && cashPay.changeAmount > 0 ? `
            <div class="change-box">
              <span>Vuelto entregado</span>
              <span class="tnum">${formatARS(cashPay.changeAmount)}</span>
            </div>
          ` : ''}
        </div>

        <p class="text-xs text-muted">Nota: la impresión o emisión de ticket/comprobante fiscal (M13) es una mejora futura propuesta; hoy GastroApp registra la venta internamente.</p>
      </div>
    `,
    footerHtml: `
      <button type="button" class="btn btn--primary" data-modal-close autofocus>Nueva venta</button>
    `,
  });
}
