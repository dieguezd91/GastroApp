import {
  getState,
  getProductMargin,
  getMarginHealth,
  getRecipeCalculation,
  saveProduct,
  toggleProductActive,
  deleteProduct,
  saveCategory,
  deleteCategory,
  recalculateRecipe,
} from '../state/store.js';
import { formatARS, escapeHtml } from '../utils/format.js';
import { icon } from '../utils/icons.js';
import { badge, banner, emptyState, loadingSkeleton, openModal, openConfirmModal } from '../utils/ui.js';
import { showToast } from '../utils/a11y.js';

let activeTab = 'products'; // products | categories
let filterText = '';
let filterStatus = 'all'; // all | active | inactive | low-margin

export function renderCatalog(container, navigate) {
  const state = getState();

  if (state.demo.simulateLoading) {
    container.innerHTML = `
      <div class="page-header"><h1 id="page-heading" tabindex="-1">Productos y categorías</h1></div>
      ${loadingSkeleton(4)}
    `;
    return;
  }

  const products = state.demo.simulateEmpty ? [] : state.products;
  const lowMarginCount = products.filter((p) => {
    const m = getProductMargin(p);
    return p.isActive && m != null && m < state.businessSettings.lowMarginThresholdPct;
  }).length;

  const filtered = products.filter((p) => {
    const q = filterText.trim().toLowerCase();
    const matchesQ = !q || p.name.toLowerCase().includes(q);
    const m = getProductMargin(p);
    const matchesStatus =
      filterStatus === 'all' ||
      (filterStatus === 'active' && p.isActive) ||
      (filterStatus === 'inactive' && !p.isActive) ||
      (filterStatus === 'low-margin' && m != null && m < state.businessSettings.lowMarginThresholdPct);
    return matchesQ && matchesStatus;
  });

  container.innerHTML = `
    <div class="page-header">
      <div>
        <h1 id="page-heading" tabindex="-1">Productos y categorías</h1>
        <p class="page-header__subtitle">Controlá precios de venta, márgenes, disponibilidad en POS y alertas frente a costos de recetas.</p>
      </div>
      <div class="page-header__actions">
        ${activeTab === 'products'
          ? `<button type="button" class="btn btn--primary" id="btn-new-product">${icon('plus', 17)} Nuevo producto</button>`
          : `<button type="button" class="btn btn--primary" id="btn-new-category">${icon('plus', 17)} Nueva categoría</button>`}
      </div>
    </div>

    <div class="tablist" role="tablist" aria-label="Secciones del catálogo">
      <button type="button" class="tab" role="tab" id="tab-products" aria-selected="${activeTab === 'products'}" data-tab="products">
        ${icon('products', 16)}
        <span>Productos (${products.length})</span>
      </button>
      <button type="button" class="tab" role="tab" id="tab-categories" aria-selected="${activeTab === 'categories'}" data-tab="categories">
        ${icon('tag', 16)}
        <span>Categorías (${state.categories.length})</span>
      </button>
    </div>

    ${activeTab === 'products' ? `
      <div class="stack" role="tabpanel" aria-labelledby="tab-products">
        ${lowMarginCount > 0 ? banner({
          variant: 'warn',
          title: `${lowMarginCount} producto(s) activo(s) con margen menor al ${state.businessSettings.lowMarginThresholdPct}%`,
          body: 'Revisá los costos actualizados desde recetas o ajustá el precio de venta para sostener la rentabilidad.',
          actionHtml: `
            <button type="button" class="btn btn--sm" id="btn-filter-low-margin">Ver solo margen bajo</button>
            <button type="button" class="btn btn--sm" id="btn-go-recipes">Revisar recetas</button>
          `,
        }) : ''}

        <search class="card card--compact toolbar">
          <div class="search-wrap">
            <span class="search-wrap__icon">${icon('search', 17)}</span>
            <label for="cat-search" class="visually-hidden">Buscar producto</label>
            <input id="cat-search" type="search" class="input input--compact" value="${escapeHtml(filterText)}" placeholder="Buscar producto por nombre…">
          </div>
          <div class="field" style="flex: 0 1 13rem;">
            <label class="field__label" for="cat-status">Estado / Margen</label>
            <select id="cat-status" class="select select--compact">
              <option value="all" ${filterStatus === 'all' ? 'selected' : ''}>Todos</option>
              <option value="active" ${filterStatus === 'active' ? 'selected' : ''}>Solo activos</option>
              <option value="inactive" ${filterStatus === 'inactive' ? 'selected' : ''}>Solo inactivos</option>
              <option value="low-margin" ${filterStatus === 'low-margin' ? 'selected' : ''}>Margen bajo (&lt; ${state.businessSettings.lowMarginThresholdPct}%)</option>
            </select>
          </div>
        </search>

        ${filtered.length === 0
          ? emptyState({
              iconName: 'products',
              title: 'No encontramos productos',
              description: 'Probá limpiando los filtros o creá un nuevo producto para el catálogo.',
              actionHtml: `<button type="button" class="btn btn--primary" id="btn-empty-new-prod">Crear producto</button>`,
            })
          : `<div class="table-wrapper" tabindex="0" role="region" aria-label="Tabla de productos">
              <table class="data-table data-table--stack">
                <thead>
                  <tr>
                    <th scope="col">Producto</th>
                    <th scope="col">Categoría</th>
                    <th scope="col">Estado POS</th>
                    <th scope="col" class="col-num">Precio</th>
                    <th scope="col" class="col-num">Costo</th>
                    <th scope="col">Margen</th>
                    <th scope="col" class="col-actions">Acciones</th>
                  </tr>
                </thead>
                <tbody>
                  ${filtered.map((p) => {
                    const cat = state.categories.find((c) => c.id === p.categoryId);
                    const margin = getProductMargin(p);
                    const health = getMarginHealth(margin);
                    const recipe = state.recipes.find((r) => r.name.toLowerCase() === p.name.toLowerCase());
                    const recCalc = recipe ? getRecipeCalculation(recipe) : null;
                    const costDrift = recCalc && p.cost != null && Math.abs(recCalc.unitCost - p.cost) > 100;
                    return `
                      <tr>
                        <th scope="row">
                          <div>${escapeHtml(p.name)}</div>
                          ${costDrift ? `<div class="text-xs text-warn mt-2">Costo receta actual: <strong>${formatARS(recCalc.unitCost)}</strong> (desfasado)</div>` : ''}
                        </th>
                        <td data-label="Categoría">${escapeHtml(cat ? cat.name : 'Sin categoría')}</td>
                        <td data-label="Estado POS">
                          ${badge(p.isActive ? 'Activo' : 'Inactivo', p.isActive ? 'ok' : 'neutral')}
                        </td>
                        <td data-label="Precio" class="col-num fw-700">${formatARS(p.price)}</td>
                        <td data-label="Costo" class="col-num">${p.cost != null ? formatARS(p.cost) : '—'}</td>
                        <td data-label="Margen">
                          ${badge(margin != null ? `${margin}% · ${health.label}` : 'Sin costo', health.variant)}
                        </td>
                        <td class="col-actions">
                          <div class="flex-wrap-gap" style="justify-content: flex-end;">
                            ${costDrift ? `<button type="button" class="btn btn--sm" data-sync-recipe="${recipe.id}" title="Actualizar costo del producto con receta">Sincronizar costo</button>` : ''}
                            <button type="button" class="btn btn--sm" data-edit-prod="${p.id}">Editar</button>
                            <button type="button" class="btn btn--ghost btn--sm" data-toggle-prod="${p.id}">${p.isActive ? 'Desactivar' : 'Activar'}</button>
                            <button type="button" class="btn btn--ghost btn--icon" data-del-prod="${p.id}" aria-label="Eliminar ${escapeHtml(p.name)}">${icon('trash', 15)}</button>
                          </div>
                        </td>
                      </tr>
                    `;
                  }).join('')}
                </tbody>
              </table>
            </div>`}
      </div>
    ` : `
      <div class="stack" role="tabpanel" aria-labelledby="tab-categories">
        <div class="table-wrapper" tabindex="0" role="region" aria-label="Tabla de categorías">
          <table class="data-table data-table--stack">
            <thead>
              <tr>
                <th scope="col">Categoría</th>
                <th scope="col" class="col-num">Productos asignados</th>
                <th scope="col" class="col-actions">Acciones</th>
              </tr>
            </thead>
            <tbody>
              ${state.categories.map((c) => {
                const count = state.products.filter((p) => p.categoryId === c.id).length;
                return `
                  <tr>
                    <th scope="row">${escapeHtml(c.name)}</th>
                    <td data-label="Productos" class="col-num">${count}</td>
                    <td class="col-actions">
                      <div class="flex-wrap-gap" style="justify-content: flex-end;">
                        <button type="button" class="btn btn--sm" data-edit-cat="${c.id}">Editar</button>
                        <button type="button" class="btn btn--danger-outline btn--sm" data-del-cat="${c.id}">Eliminar</button>
                      </div>
                    </td>
                  </tr>
                `;
              }).join('')}
            </tbody>
          </table>
        </div>
      </div>
    `}
  `;

  container.querySelectorAll('[data-tab]').forEach((t) => {
    t.addEventListener('click', () => {
      activeTab = t.dataset.tab;
      renderCatalog(container, navigate);
    });
  });

  container.querySelector('#btn-go-recipes')?.addEventListener('click', () => navigate('recipes'));
  container.querySelector('#btn-filter-low-margin')?.addEventListener('click', () => {
    filterStatus = 'low-margin';
    renderCatalog(container, navigate);
  });

  const searchInp = container.querySelector('#cat-search');
  searchInp?.addEventListener('input', (e) => {
    filterText = e.target.value;
    const pos = e.target.selectionStart;
    renderCatalog(container, navigate);
    const next = document.getElementById('cat-search');
    if (next) { next.focus(); next.setSelectionRange(pos, pos); }
  });

  container.querySelector('#cat-status')?.addEventListener('change', (e) => {
    filterStatus = e.target.value;
    renderCatalog(container, navigate);
  });

  container.querySelector('#btn-new-product')?.addEventListener('click', () => openProductModal(null));
  container.querySelector('#btn-empty-new-prod')?.addEventListener('click', () => openProductModal(null));

  container.querySelectorAll('[data-edit-prod]').forEach((btn) => {
    btn.addEventListener('click', () => {
      const prod = state.products.find((p) => p.id === Number(btn.dataset.editProd));
      if (prod) openProductModal(prod);
    });
  });

  container.querySelectorAll('[data-toggle-prod]').forEach((btn) => {
    btn.addEventListener('click', () => {
      toggleProductActive(Number(btn.dataset.toggleProd));
      showToast('Disponibilidad en POS actualizada.', 'ok');
    });
  });

  container.querySelectorAll('[data-sync-recipe]').forEach((btn) => {
    btn.addEventListener('click', () => {
      const res = recalculateRecipe(Number(btn.dataset.syncRecipe), true);
      if (res.ok) showToast(`Costo actualizado desde receta (${formatARS(res.unitCost)}).`, 'ok');
    });
  });

  container.querySelectorAll('[data-del-prod]').forEach((btn) => {
    btn.addEventListener('click', () => {
      const prod = state.products.find((p) => p.id === Number(btn.dataset.delProd));
      if (!prod) return;
      openConfirmModal({
        title: `¿Eliminar "${prod.name}"?`,
        message: 'El producto desaparecerá del catálogo actual. Las ventas históricas conservan su nombre y precio.',
        confirmLabel: 'Eliminar producto',
        onConfirm: () => {
          deleteProduct(prod.id);
          showToast(`Producto "${prod.name}" eliminado.`, 'ok');
        },
      });
    });
  });

  container.querySelector('#btn-new-category')?.addEventListener('click', () => openCategoryModal(null));
  container.querySelectorAll('[data-edit-cat]').forEach((btn) => {
    btn.addEventListener('click', () => {
      const cat = state.categories.find((c) => c.id === Number(btn.dataset.editCat));
      if (cat) openCategoryModal(cat);
    });
  });
  container.querySelectorAll('[data-del-cat]').forEach((btn) => {
    btn.addEventListener('click', () => {
      const res = deleteCategory(Number(btn.dataset.delCat));
      if (!res.ok) showToast(res.error, 'danger');
      else showToast('Categoría eliminada.', 'ok');
    });
  });
}

function openProductModal(prod) {
  const state = getState();
  openModal({
    title: prod ? `Editar producto · ${prod.name}` : 'Nuevo producto',
    subtitle: 'El margen se calcula automáticamente como (precio − costo) / precio × 100.',
    bodyHtml: `
      <form id="prod-form" class="stack" novalidate>
        <div id="prod-form-err"></div>
        <div class="field">
          <label class="field__label" for="prod-name">Nombre <span class="field__req" aria-hidden="true">*</span></label>
          <input id="prod-name" name="name" type="text" class="input" required value="${escapeHtml(prod?.name || '')}" data-error="prod-name-err" placeholder="Ej.: Sándwich de pollo grillado">
          <span id="prod-name-err" class="field__error">${icon('alertOctagon', 14)} Ingresá un nombre para el producto.</span>
        </div>

        <div class="form-grid">
          <div class="field">
            <label class="field__label" for="prod-price">Precio de venta ($) <span class="field__req" aria-hidden="true">*</span></label>
            <input id="prod-price" name="price" type="number" min="1" step="any" class="input tnum" required value="${prod?.price ?? ''}" data-error="prod-price-err">
            <span id="prod-price-err" class="field__error">${icon('alertOctagon', 14)} Ingresá un precio mayor a cero.</span>
          </div>
          <div class="field">
            <label class="field__label" for="prod-cost">Costo unitario (opcional)</label>
            <input id="prod-cost" name="cost" type="number" min="0" step="any" class="input tnum" value="${prod?.cost ?? ''}">
          </div>
        </div>

        <div class="field">
          <label class="field__label" for="prod-cat">Categoría (opcional)</label>
          <select id="prod-cat" name="categoryId" class="select">
            <option value="">Sin categoría</option>
            ${state.categories.map((c) => `<option value="${c.id}" ${prod?.categoryId === c.id ? 'selected' : ''}>${escapeHtml(c.name)}</option>`).join('')}
          </select>
        </div>

        <label class="check-field">
          <input type="checkbox" name="isActive" ${prod ? (prod.isActive ? 'checked' : '') : 'checked'}>
          <span>Activo (disponible para la venta en el POS)</span>
        </label>
      </form>
    `,
    footerHtml: `
      <button type="button" class="btn" data-modal-close>Cancelar</button>
      <button type="submit" form="prod-form" class="btn btn--primary">${prod ? 'Guardar cambios' : 'Crear producto'}</button>
    `,
    onMount(dlg) {
      const form = dlg.querySelector('#prod-form');
      form.addEventListener('submit', (e) => {
        e.preventDefault();
        const fd = new FormData(form);
        const res = saveProduct({
          id: prod?.id,
          name: fd.get('name'),
          price: fd.get('price'),
          cost: fd.get('cost'),
          categoryId: fd.get('categoryId') || null,
          isActive: form.querySelector('[name="isActive"]').checked,
        });
        if (!res.ok) {
          dlg.querySelector('#prod-form-err').innerHTML = banner({ variant: 'danger', body: res.error });
          return;
        }
        dlg.close('save');
        showToast(prod ? 'Producto actualizado.' : 'Producto creado.', 'ok');
      });
    },
  });
}

function openCategoryModal(cat) {
  openModal({
    title: cat ? 'Editar categoría' : 'Nueva categoría',
    bodyHtml: `
      <form id="cat-form" class="stack" novalidate>
        <div id="cat-form-err"></div>
        <div class="field">
          <label class="field__label" for="cat-name">Nombre de categoría <span class="field__req" aria-hidden="true">*</span></label>
          <input id="cat-name" name="name" type="text" class="input" required value="${escapeHtml(cat?.name || '')}" autofocus>
        </div>
      </form>
    `,
    footerHtml: `
      <button type="button" class="btn" data-modal-close>Cancelar</button>
      <button type="submit" form="cat-form" class="btn btn--primary">Guardar</button>
    `,
    onMount(dlg) {
      dlg.querySelector('#cat-form').addEventListener('submit', (e) => {
        e.preventDefault();
        const res = saveCategory({ id: cat?.id, name: dlg.querySelector('#cat-name').value });
        if (!res.ok) {
          dlg.querySelector('#cat-form-err').innerHTML = banner({ variant: 'danger', body: res.error });
          return;
        }
        dlg.close('save');
        showToast(cat ? 'Categoría actualizada.' : 'Categoría creada.', 'ok');
      });
    },
  });
}
