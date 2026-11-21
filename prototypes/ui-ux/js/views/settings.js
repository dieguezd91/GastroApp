import { getState, updateBusinessSettings, saveDemoUser } from '../state/store.js';
import { PAYMENT_METHODS } from '../data/seed.js';
import { escapeHtml } from '../utils/format.js';
import { icon } from '../utils/icons.js';
import { badge, banner, loadingSkeleton, proposalBanner, openModal } from '../utils/ui.js';
import { showToast } from '../utils/a11y.js';

export function renderSettings(container) {
  const state = getState();
  if (state.demo.simulateLoading) {
    container.innerHTML = `
      <div class="page-header"><h1 id="page-heading" tabindex="-1">Configuración del negocio</h1></div>
      ${loadingSkeleton(4)}
    `;
    return;
  }
  const s = state.businessSettings;

  container.innerHTML = `
    <div class="page-header">
      <div>
        <div class="page-header__title-row">
          <h1 id="page-heading" tabindex="-1">Configuración del negocio</h1>
          ${badge('Propuesta · No implementado', 'proposal', 'sparkles')}
        </div>
        <p class="page-header__subtitle">Propuesta de configuración centralizada (M01 / M18 / M21) respetando únicamente los dos roles existentes: Administrador y Empleado.</p>
      </div>
    </div>

    <div class="stack stack--lg">
      ${proposalBanner(
        'M01 / M18 / M21',
        'El sistema actual no posee pantalla de configuración comercial ni interfaz CRUD de usuarios (aunque existe UserService en backend). Los cambios acá actualizan solo el prototipo en memoria.'
      )}

      <div class="grid-2">
        <form id="settings-form" class="card stack">
          <h2 class="card__title">Datos del establecimiento y reglas</h2>

          <div class="field">
            <label class="field__label" for="set-trade">Nombre comercial</label>
            <input id="set-trade" name="tradeName" type="text" class="input" value="${escapeHtml(s.tradeName)}" required>
          </div>

          <div class="form-grid">
            <div class="field">
              <label class="field__label" for="set-cuit">CUIT</label>
              <input id="set-cuit" name="cuit" type="text" class="input" value="${escapeHtml(s.cuit)}">
            </div>
            <div class="field">
              <label class="field__label" for="set-iva">Condición IVA</label>
              <select id="set-iva" name="ivaCondition" class="select">
                <option ${s.ivaCondition === 'Responsable Inscripto' ? 'selected' : ''}>Responsable Inscripto</option>
                <option ${s.ivaCondition === 'Monotributista' ? 'selected' : ''}>Monotributista</option>
              </select>
            </div>
          </div>

          <div class="field">
            <label class="field__label" for="set-addr">Dirección</label>
            <input id="set-addr" name="address" type="text" class="input" value="${escapeHtml(s.address)}">
          </div>

          <div class="form-grid">
            <div class="field">
              <label class="field__label" for="set-margin">Umbral alerta de margen (%)</label>
              <input id="set-margin" name="lowMarginThresholdPct" type="number" min="5" max="90" class="input tnum" value="${s.lowMarginThresholdPct}">
            </div>
            <div class="field">
              <label class="field__label" for="set-disc">Tope descuento Empleado (%)</label>
              <input id="set-disc" name="maxEmployeeDiscountPct" type="number" min="0" max="100" class="input tnum" value="${s.maxEmployeeDiscountPct}">
            </div>
          </div>

          <fieldset class="fieldset stack stack--sm">
            <legend>Medios de pago visibles en POS</legend>
            <div class="form-grid">
              ${PAYMENT_METHODS.map((pm) => `
                <label class="check-field">
                  <input type="checkbox" name="pm" value="${pm.id}" ${s.enabledPayments.includes(pm.id) ? 'checked' : ''}>
                  <span>${escapeHtml(pm.label)}</span>
                </label>
              `).join('')}
            </div>
          </fieldset>

          <div>
            <button type="submit" class="btn btn--primary">Guardar configuración (demo)</button>
          </div>
        </form>

        <section class="card stack" aria-labelledby="team-heading">
          <div class="row-between">
            <div>
              <h2 id="team-heading" class="card__title">Equipo y roles existentes</h2>
              <p class="card__desc">Únicamente dos roles: Administrador y Empleado (propuesta UI sobre UserService).</p>
            </div>
            <button type="button" class="btn btn--sm btn--primary" id="btn-new-user">${icon('plus', 15)} Nuevo usuario</button>
          </div>

          <div class="table-wrapper" tabindex="0" role="region" aria-labelledby="team-heading">
            <table class="data-table data-table--stack">
              <thead>
                <tr>
                  <th scope="col">Usuario</th>
                  <th scope="col">Rol</th>
                  <th scope="col">Estado</th>
                  <th scope="col" class="col-actions">Acciones</th>
                </tr>
              </thead>
              <tbody>
                ${state.users.map((u) => `
                  <tr>
                    <th scope="row">
                      <div>${escapeHtml(u.fullName)}</div>
                      <div class="text-xs text-muted fw-600">@${escapeHtml(u.username)}</div>
                    </th>
                    <td data-label="Rol">${badge(u.role === 'Admin' ? 'Administrador' : 'Empleado', u.role === 'Admin' ? 'info' : 'neutral')}</td>
                    <td data-label="Estado">${badge(u.active ? 'Activo' : 'Inactivo', u.active ? 'ok' : 'neutral')}</td>
                    <td class="col-actions">
                      <button type="button" class="btn btn--sm" data-edit-user="${u.id}">Editar</button>
                    </td>
                  </tr>
                `).join('')}
              </tbody>
            </table>
          </div>
        </section>
      </div>
    </div>
  `;

  container.querySelector('#settings-form').addEventListener('submit', (e) => {
    e.preventDefault();
    const form = e.currentTarget;
    const enabledPayments = [...form.querySelectorAll('input[name="pm"]:checked')].map((el) => el.value);
    updateBusinessSettings({
      tradeName: form.querySelector('#set-trade').value.trim(),
      cuit: form.querySelector('#set-cuit').value.trim(),
      ivaCondition: form.querySelector('#set-iva').value,
      address: form.querySelector('#set-addr').value.trim(),
      lowMarginThresholdPct: Number(form.querySelector('#set-margin').value || 30),
      maxEmployeeDiscountPct: Number(form.querySelector('#set-disc').value || 10),
      enabledPayments: enabledPayments.length ? enabledPayments : ['Cash'],
    });
    showToast('Configuración de demostración actualizada.', 'ok');
  });

  container.querySelector('#btn-new-user')?.addEventListener('click', () => openUserModal(null));
  container.querySelectorAll('[data-edit-user]').forEach((btn) => {
    btn.addEventListener('click', () => {
      const user = state.users.find((u) => u.id === Number(btn.dataset.editUser));
      if (user) openUserModal(user);
    });
  });
}

function openUserModal(user) {
  openModal({
    title: user ? `Editar usuario · ${user.fullName}` : 'Nuevo usuario (propuesta M18)',
    bodyHtml: `
      <form id="usr-form" class="stack" novalidate>
        <div id="usr-err"></div>
        <div class="form-grid">
          <div class="field">
            <label class="field__label" for="usr-name">Nombre completo <span class="field__req" aria-hidden="true">*</span></label>
            <input id="usr-name" type="text" class="input" value="${escapeHtml(user?.fullName || '')}" required autofocus>
          </div>
          <div class="field">
            <label class="field__label" for="usr-username">Usuario de acceso <span class="field__req" aria-hidden="true">*</span></label>
            <input id="usr-username" type="text" class="input" value="${escapeHtml(user?.username || '')}" autocorrect="off" autocapitalize="none" required>
          </div>
        </div>
        <div class="field">
          <label class="field__label" for="usr-role">Rol</label>
          <select id="usr-role" class="select">
            <option value="Employee" ${user?.role === 'Employee' || !user ? 'selected' : ''}>Empleado (POS e Inicio)</option>
            <option value="Admin" ${user?.role === 'Admin' ? 'selected' : ''}>Administrador (acceso completo)</option>
          </select>
        </div>
        <label class="check-field">
          <input type="checkbox" id="usr-active" ${user ? (user.active ? 'checked' : '') : 'checked'}>
          <span>Usuario activo</span>
        </label>
        ${!user ? '<p class="text-xs text-muted">En el prototipo, los usuarios nuevos inician sesión con contraseña <code>1234</code> o su propio nombre de usuario.</p>' : ''}
      </form>
    `,
    footerHtml: `
      <button type="button" class="btn" data-modal-close>Cancelar</button>
      <button type="submit" form="usr-form" class="btn btn--primary">${user ? 'Guardar cambios' : 'Crear usuario'}</button>
    `,
    onMount(dlg) {
      dlg.querySelector('#usr-form').addEventListener('submit', (e) => {
        e.preventDefault();
        const res = saveDemoUser({
          id: user?.id,
          fullName: dlg.querySelector('#usr-name').value,
          username: dlg.querySelector('#usr-username').value,
          role: dlg.querySelector('#usr-role').value,
          active: dlg.querySelector('#usr-active').checked,
        });
        if (!res.ok) {
          dlg.querySelector('#usr-err').innerHTML = banner({ variant: 'danger', body: res.error });
          return;
        }
        dlg.close('ok');
        showToast(user ? 'Usuario actualizado (demo).' : 'Usuario creado (demo).', 'ok');
      });
    },
  });
}
