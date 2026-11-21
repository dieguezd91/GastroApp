import { getState, getRecipeCalculation, recalculateRecipe, saveRecipe, deleteRecipe } from '../state/store.js';
import { formatARS, formatDateTime, formatNum, formatQtyUnit, escapeHtml, convertUnit, roundMoney, getCompatibleUnits, getDefaultRecipeUnit } from '../utils/format.js';
import { icon } from '../utils/icons.js';
import { badge, banner, emptyState, loadingSkeleton, openConfirmModal } from '../utils/ui.js';
import { showToast } from '../utils/a11y.js';

let editorState = null; // null | { existingId, name, yield, ingredients, pickerIngId, pickerQty, pickerUnit, error }

function openRecipeEditor(existingRecipe) {
  const activeIngredients = getState().ingredients.filter((i) => i.active);
  const firstIng = activeIngredients[0];
  editorState = {
    existingId: existingRecipe?.id || null,
    existingName: existingRecipe?.name || '',
    lastCalculatedCost: existingRecipe?.lastCalculatedCost || 0,
    name: existingRecipe?.name || '',
    yield: existingRecipe?.yield || 1,
    ingredients: existingRecipe ? existingRecipe.ingredients.map((ri) => ({ ...ri })) : [],
    pickerIngId: firstIng?.id || '',
    pickerQty: '',
    pickerUnit: getDefaultRecipeUnit(firstIng?.unit || 'kg'),
    error: '',
  };
}

export function renderRecipes(container, navigate) {
  const state = getState();

  if (state.demo.simulateLoading) {
    container.innerHTML = `
      <div class="page-header"><h1 id="page-heading" tabindex="-1">Recetas y costos</h1></div>
      ${loadingSkeleton(4)}
    `;
    return;
  }

  if (editorState) {
    renderRecipeWorkspace(container, navigate);
    return;
  }

  const recipes = state.demo.simulateEmpty ? [] : state.recipes;

  container.innerHTML = `
    <div class="page-header">
      <div>
        <h1 id="page-heading" tabindex="-1">Recetas y costos</h1>
        <p class="page-header__subtitle">Costo calculado con el último precio de factura por ingrediente. Variación visual: &lt;10% estable, 10–30% media, &gt;=30% alta.</p>
      </div>
      <div class="page-header__actions">
        <button type="button" class="btn" id="rec-go-catalog">${icon('products', 17)} Ver productos</button>
        <button type="button" class="btn btn--primary" id="btn-new-recipe">${icon('plus', 17)} Nueva receta</button>
      </div>
    </div>

    <div class="stack">
      <p class="proposal-note" role="note" style="background-color: var(--status-info-bg); border-color: color-mix(in oklab, var(--status-info-border) 30%, transparent); color: var(--status-info-ink);">
        <span class="proposal-note__icon">${icon('info', 15)}</span>
        <span><strong>Vínculo actual:</strong> el descuento de stock al vender busca una receta con el mismo nombre exacto que el producto.</span>
      </p>

      ${recipes.length === 0
        ? emptyState({
            iconName: 'recipes',
            title: 'Todavía no hay recetas cargadas',
            description: 'Creá recetas estandarizadas con múltiples ingredientes para calcular costos y descontar stock al vender.',
            actionHtml: `<button type="button" class="btn btn--primary" id="btn-empty-new-recipe">Crear primera receta</button>`,
          })
        : `<div class="grid-2">
            ${recipes.map((r) => {
              const calc = getRecipeCalculation(r);
              const linkedProduct = state.products.find((p) => p.name.toLowerCase() === r.name.toLowerCase());
              return `
                <article class="card stack" aria-label="Receta ${escapeHtml(r.name)}">
                  <div class="row-between">
                    <div>
                      <h2 class="card__title">${escapeHtml(r.name)}</h2>
                      <p class="text-xs text-muted">Rendimiento: ${r.yield} porción(es) · ${r.ingredients.length} ingrediente(s) · ${formatDateTime(r.lastCalculatedAt)}</p>
                    </div>
                    ${badge(calc.variationLevel.label, calc.variationLevel.variant, calc.variationLevel.code === 'danger' ? 'alertOctagon' : calc.variationLevel.code === 'warn' ? 'alertTriangle' : 'checkCircle')}
                  </div>

                  <div class="grid-kpi" style="grid-template-columns: repeat(3, 1fr); gap: var(--space-2);">
                    <div class="card card--compact card--subtle">
                      <p class="text-xs text-muted">Costo total</p>
                      <p class="fw-700 tnum">${formatARS(calc.totalCost)}</p>
                    </div>
                    <div class="card card--compact card--subtle">
                      <p class="text-xs text-muted">Costo / porc.</p>
                      <p class="fw-700 tnum">${formatARS(calc.unitCost)}</p>
                      <p class="text-xs text-muted">Ant.: ${formatARS(r.lastCalculatedCost)}</p>
                    </div>
                    <div class="card card--compact card--subtle">
                      <p class="text-xs text-muted">Precio producto</p>
                      <p class="fw-700 tnum">${linkedProduct ? formatARS(linkedProduct.price) : 'Sin vínculo'}</p>
                    </div>
                  </div>

                  ${calc.warnings.length ? banner({ variant: 'warn', body: calc.warnings.map(escapeHtml).join(' ') }) : ''}

                  <details>
                    <summary class="text-sm fw-600" style="cursor: pointer;">Ver composición de ingredientes (${calc.breakdown.length})</summary>
                    <div class="table-wrapper mt-3" tabindex="0" role="region" aria-label="Ingredientes de ${escapeHtml(r.name)}">
                      <table class="data-table">
                        <thead>
                          <tr>
                            <th scope="col">Ingrediente</th>
                            <th scope="col" class="col-num">Cantidad</th>
                            <th scope="col" class="col-num">Costo línea</th>
                          </tr>
                        </thead>
                        <tbody>
                          ${calc.breakdown.map((b) => `
                            <tr>
                              <th scope="row">${escapeHtml(b.ingredientName)}</th>
                              <td class="col-num">${formatQtyUnit(b.quantity, b.unit)}</td>
                              <td class="col-num fw-700">${b.compatible ? formatARS(b.lineCost) : badge('Incompatible', 'danger')}</td>
                            </tr>
                          `).join('')}
                        </tbody>
                      </table>
                    </div>
                  </details>

                  <div class="flex-wrap-gap">
                    <button type="button" class="btn btn--primary btn--sm" data-recalc-sync="${r.id}">
                      ${icon('refresh', 15)}
                      <span>Recalcular y actualizar producto</span>
                    </button>
                    <button type="button" class="btn btn--sm" data-edit-recipe="${r.id}">${icon('edit', 14)} Editar</button>
                    <button type="button" class="btn btn--ghost btn--sm" data-recalc-only="${r.id}">Solo recalcular</button>
                    <button type="button" class="btn btn--ghost btn--icon" data-del-recipe="${r.id}" aria-label="Eliminar receta ${escapeHtml(r.name)}">${icon('trash', 15)}</button>
                  </div>
                </article>
              `;
            }).join('')}
          </div>`}
    </div>
  `;

  container.querySelector('#rec-go-catalog')?.addEventListener('click', () => navigate('catalog'));
  container.querySelector('#btn-new-recipe')?.addEventListener('click', () => {
    openRecipeEditor(null);
    renderRecipes(container, navigate);
    document.getElementById('page-heading')?.focus();
  });
  container.querySelector('#btn-empty-new-recipe')?.addEventListener('click', () => {
    openRecipeEditor(null);
    renderRecipes(container, navigate);
    document.getElementById('page-heading')?.focus();
  });

  container.querySelectorAll('[data-edit-recipe]').forEach((btn) => {
    btn.addEventListener('click', () => {
      const rec = state.recipes.find((r) => r.id === Number(btn.dataset.editRecipe));
      if (rec) {
        openRecipeEditor(rec);
        renderRecipes(container, navigate);
        document.getElementById('page-heading')?.focus();
      }
    });
  });

  container.querySelectorAll('[data-del-recipe]').forEach((btn) => {
    btn.addEventListener('click', () => {
      const rec = state.recipes.find((r) => r.id === Number(btn.dataset.delRecipe));
      if (!rec) return;
      openConfirmModal({
        title: `¿Eliminar receta "${rec.name}"?`,
        message: 'Se eliminará la receta estandarizada. Los productos con el mismo nombre dejarán de descontar stock automáticamente al vender.',
        confirmLabel: 'Eliminar receta',
        onConfirm: () => {
          deleteRecipe(rec.id);
          showToast(`Receta "${rec.name}" eliminada.`, 'ok');
        },
      });
    });
  });

  container.querySelectorAll('[data-recalc-sync]').forEach((btn) => {
    btn.addEventListener('click', () => {
      const res = recalculateRecipe(Number(btn.dataset.recalcSync), true);
      if (res.ok) showToast(`Receta recalculada (${formatARS(res.unitCost)}) y costo de producto actualizado.`, 'ok');
    });
  });

  container.querySelectorAll('[data-recalc-only]').forEach((btn) => {
    btn.addEventListener('click', () => {
      const res = recalculateRecipe(Number(btn.dataset.recalcOnly), false);
      if (res.ok) showToast(`Receta recalculada: ${formatARS(res.unitCost)} por porción.`, 'ok');
    });
  });
}

function renderRecipeWorkspace(container, navigate) {
  const state = getState();
  const activeIngredients = state.ingredients.filter((i) => i.active);
  const d = editorState;
  const getSelectedIng = () => activeIngredients.find((i) => i.id === Number(d.pickerIngId)) || activeIngredients[0];
  const selectedIng = getSelectedIng();
  const compatUnits = getCompatibleUnits(selectedIng?.unit);
  if (!compatUnits.includes(d.pickerUnit)) {
    d.pickerUnit = getDefaultRecipeUnit(selectedIng?.unit);
  }

  const computeLinePreviewText = () => {
    const ing = getSelectedIng();
    if (!ing) return '';
    const qty = roundMoney(d.pickerQty);
    if (Number.isNaN(qty) || qty <= 0) {
      return `Ingresá la cantidad en ${d.pickerUnit}${d.pickerUnit !== ing.unit ? ` (se convierte automáticamente a ${ing.unit})` : ''}.`;
    }
    const conv = convertUnit(qty, d.pickerUnit, ing.unit);
    if (!conv.ok) return 'Unidad incompatible.';
    const cost = roundMoney(conv.value * (ing.lastUnitPrice || 0));
    const equiv = d.pickerUnit !== ing.unit ? `Equivale a ${formatNum(conv.value)} ${ing.unit} · ` : '';
    return ing.lastUnitPrice
      ? `${equiv}Costo estimado de esta línea: ${formatARS(cost)}`
      : `${equiv}Sin precio de factura cargado aún`;
  };

  const preview = getRecipeCalculation({
    yield: Math.max(1, Number(d.yield || 1)),
    ingredients: d.ingredients,
    lastCalculatedCost: d.lastCalculatedCost,
  });

  container.innerHTML = `
    <div class="page-header">
      <div>
        <h1 id="page-heading" tabindex="-1">${d.existingId ? `Editar receta · ${escapeHtml(d.existingName)}` : 'Nueva receta estandarizada'}</h1>
        <p class="page-header__subtitle">La unidad se adapta automáticamente al ingrediente elegido para evitar errores de carga.</p>
      </div>
      <div class="page-header__actions">
        <button type="button" class="btn" id="rec-cancel-top">← Volver a Recetas</button>
      </div>
    </div>

    <section class="workspace-panel stack" aria-label="Formulario de receta">
      ${d.error ? banner({ variant: 'danger', body: escapeHtml(d.error) }) : ''}

      <div class="form-grid">
        <div class="field">
          <label class="field__label" for="rec-name">Nombre de la receta <span class="field__req" aria-hidden="true">*</span></label>
          <span id="rec-name-hint" class="field__hint">Usá el nombre exacto del producto para vincular el descuento de stock.</span>
          <input id="rec-name" type="text" class="input" value="${escapeHtml(d.name)}" aria-describedby="rec-name-hint" placeholder="Ej.: Brownie tibio con helado" required>
        </div>
        <div class="field">
          <label class="field__label" for="rec-yield">Rendimiento (porciones / pax) <span class="field__req" aria-hidden="true">*</span></label>
          <span id="rec-yield-hint" class="field__hint">Divide el costo total para obtener el costo unitario.</span>
          <input id="rec-yield" type="number" min="1" step="1" class="input tnum" value="${d.yield}" aria-describedby="rec-yield-hint" required>
        </div>
      </div>

      <fieldset class="fieldset stack stack--sm">
        <legend>Agregar ingredientes a la receta</legend>
        <div class="form-grid" style="align-items: end;">
          <div class="field">
            <label class="field__label" for="rec-pick-ing">Ingrediente activo</label>
            <select id="rec-pick-ing" class="select select--compact">
              ${activeIngredients.map((i) => `
                <option value="${i.id}" ${Number(d.pickerIngId) === i.id ? 'selected' : ''}>
                  ${escapeHtml(i.name)} (${i.unit}) — ${i.lastUnitPrice ? `${formatARS(i.lastUnitPrice)}/${i.unit}` : 'Sin precio'}
                </option>
              `).join('')}
            </select>
          </div>
          <div class="field">
            <label class="field__label" for="rec-pick-qty">Cantidad</label>
            <input id="rec-pick-qty" type="number" min="0.01" step="any" class="input input--compact tnum" value="${escapeHtml(d.pickerQty)}" placeholder="${d.pickerUnit === 'unidad' ? 'Ej.: 1' : d.pickerUnit === 'gr' || d.pickerUnit === 'ml' ? 'Ej.: 180' : 'Ej.: 0.5'}">
          </div>
          <div class="field">
            <span class="field__label" id="rec-unit-lbl">Unidad (${compatUnits.length === 1 ? 'fija' : 'compatible'})</span>
            ${compatUnits.length === 1
              ? `<span class="unit-static" aria-labelledby="rec-unit-lbl">${escapeHtml(compatUnits[0])}</span>`
              : `<div class="unit-toggle" role="radiogroup" aria-labelledby="rec-unit-lbl">
                  ${compatUnits.map((u) => `
                    <label class="unit-toggle__opt">
                      <input type="radio" name="rec-pick-unit" value="${u}" class="visually-hidden" ${d.pickerUnit === u ? 'checked' : ''}>
                      <span>${u}</span>
                    </label>
                  `).join('')}
                </div>`}
          </div>
          <div>
            <button type="button" class="btn btn--primary btn--sm btn--block" id="rec-add-ing-btn">
              ${icon('plus', 15)}
              <span>Agregar ingrediente</span>
            </button>
          </div>
        </div>

        <div class="live-preview-strip" id="rec-line-preview" aria-live="polite">
          <span>${escapeHtml(computeLinePreviewText())}</span>
        </div>

        ${d.ingredients.length === 0
          ? `<p class="text-sm text-muted">Todavía no agregaste ingredientes. Sumá al menos uno para costear la receta.</p>`
          : `<div class="table-wrapper mt-2" tabindex="0" role="region" aria-label="Ingredientes agregados a la receta">
              <table class="data-table data-table--stack">
                <thead>
                  <tr>
                    <th scope="col">Ingrediente</th>
                    <th scope="col" class="col-num">Cantidad</th>
                    <th scope="col">Estado</th>
                    <th scope="col" class="col-num">Subtotal</th>
                    <th scope="col" class="col-actions">Quitar</th>
                  </tr>
                </thead>
                <tbody>
                  ${preview.breakdown.map((b, idx) => `
                    <tr>
                      <th scope="row">${escapeHtml(b.ingredientName)}</th>
                      <td data-label="Cantidad" class="col-num">${formatQtyUnit(b.quantity, b.unit)}</td>
                      <td data-label="Estado">
                        ${!b.compatible
                          ? badge(`Unidad incompatible (base: ${b.baseUnit})`, 'danger', 'alertOctagon')
                          : !b.unitCost
                            ? badge('Sin último precio', 'warn', 'alertTriangle')
                            : badge(`OK (${formatARS(b.unitCost)}/${b.baseUnit})`, 'ok', 'check')}
                      </td>
                      <td data-label="Subtotal" class="col-num fw-700">${b.compatible ? formatARS(b.lineCost) : 'Excluido'}</td>
                      <td class="col-actions">
                        <button type="button" class="btn btn--ghost btn--icon" data-rem-rec-ing="${idx}" aria-label="Quitar ${escapeHtml(b.ingredientName)}">
                          ${icon('trash', 15)}
                        </button>
                      </td>
                    </tr>
                  `).join('')}
                </tbody>
              </table>
            </div>`}
      </fieldset>

      <div class="card card--compact card--subtle">
        <div class="grid-kpi" style="grid-template-columns: repeat(2, 1fr); gap: var(--space-3);">
          <div>
            <p class="text-xs fw-700 text-muted" style="text-transform: uppercase;">Costo total estimado</p>
            <p class="fw-700 tnum" id="rec-preview-total" style="font-size: var(--text-xl);">${formatARS(preview.totalCost)}</p>
          </div>
          <div>
            <p class="text-xs fw-700 text-muted" style="text-transform: uppercase;" id="rec-preview-unit-label">Costo por porción (${Math.max(1, Number(d.yield || 1))} u.)</p>
            <p class="fw-700 tnum text-ok" id="rec-preview-unit" style="font-size: var(--text-xl);">${formatARS(preview.unitCost)}</p>
          </div>
        </div>
      </div>

      <div class="workspace-panel__footer">
        <button type="button" class="btn" id="rec-cancel-btn">Cancelar</button>
        <button type="button" class="btn btn--primary btn--lg" id="rec-save-btn">${d.existingId ? 'Guardar cambios' : 'Guardar receta'}</button>
      </div>
    </section>
  `;

  const closeWorkspace = () => {
    editorState = null;
    renderRecipes(container, navigate);
    document.getElementById('page-heading')?.focus();
  };

  container.querySelector('#rec-cancel-top').addEventListener('click', closeWorkspace);
  container.querySelector('#rec-cancel-btn').addEventListener('click', closeWorkspace);

  const updateLinePreview = () => {
    const el = container.querySelector('#rec-line-preview span');
    if (el) el.textContent = computeLinePreviewText();
  };

  container.querySelector('#rec-name').addEventListener('input', (e) => { d.name = e.target.value; });
  container.querySelector('#rec-yield').addEventListener('input', (e) => {
    d.yield = Math.max(1, Math.floor(Number(e.target.value || 1)));
    const nextPreview = getRecipeCalculation({
      yield: d.yield,
      ingredients: d.ingredients,
      lastCalculatedCost: d.lastCalculatedCost,
    });
    const totEl = container.querySelector('#rec-preview-total');
    const unitEl = container.querySelector('#rec-preview-unit');
    const lblEl = container.querySelector('#rec-preview-unit-label');
    if (totEl) totEl.textContent = formatARS(nextPreview.totalCost);
    if (unitEl) unitEl.textContent = formatARS(nextPreview.unitCost);
    if (lblEl) lblEl.textContent = `Costo por porción (${d.yield} u.)`;
  });

  container.querySelector('#rec-pick-ing').addEventListener('change', (e) => {
    d.pickerIngId = Number(e.target.value);
    const ing = getSelectedIng();
    if (ing) d.pickerUnit = getDefaultRecipeUnit(ing.unit);
    renderRecipeWorkspace(container, navigate);
  });

  container.querySelector('#rec-pick-qty').addEventListener('input', (e) => {
    d.pickerQty = e.target.value;
    updateLinePreview();
  });

  container.querySelectorAll('input[name="rec-pick-unit"]').forEach((rad) => {
    rad.addEventListener('change', (e) => {
      d.pickerUnit = e.target.value;
      updateLinePreview();
    });
  });

  container.querySelector('#rec-add-ing-btn').addEventListener('click', () => {
    const ingId = Number(d.pickerIngId);
    const qty = roundMoney(d.pickerQty);
    if (!ingId) { d.error = 'Seleccioná un ingrediente.'; renderRecipeWorkspace(container, navigate); return; }
    if (Number.isNaN(qty) || qty <= 0) {
      d.error = 'Ingresá una cantidad mayor a cero antes de agregar el ingrediente.';
      renderRecipeWorkspace(container, navigate);
      container.querySelector('#rec-pick-qty')?.focus();
      return;
    }
    const existingIdx = d.ingredients.findIndex((x) => x.ingredientId === ingId);
    if (existingIdx >= 0) {
      const conv = convertUnit(qty, d.pickerUnit, d.ingredients[existingIdx].unit);
      if (conv.ok) d.ingredients[existingIdx].quantity = roundMoney(d.ingredients[existingIdx].quantity + conv.value);
      else d.ingredients[existingIdx] = { ingredientId: ingId, quantity: qty, unit: d.pickerUnit };
    } else {
      d.ingredients.push({ ingredientId: ingId, quantity: qty, unit: d.pickerUnit });
    }
    d.pickerQty = '';
    d.error = '';
    renderRecipeWorkspace(container, navigate);
    container.querySelector('#rec-pick-ing')?.focus();
  });

  container.querySelectorAll('[data-rem-rec-ing]').forEach((btn) => {
    btn.addEventListener('click', () => {
      d.ingredients.splice(Number(btn.dataset.remRecIng), 1);
      d.error = '';
      renderRecipeWorkspace(container, navigate);
    });
  });

  container.querySelector('#rec-save-btn').addEventListener('click', () => {
    const wasEdit = Boolean(d.existingId);
    const res = saveRecipe({
      id: d.existingId,
      name: d.name,
      yield: d.yield,
      ingredients: d.ingredients,
    });
    if (!res.ok) {
      d.error = res.error;
      renderRecipeWorkspace(container, navigate);
      return;
    }
    editorState = null;
    showToast(wasEdit ? 'Receta actualizada y recosteada.' : 'Receta creada y costeada.', 'ok');
  });
}
