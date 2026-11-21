import { getState, loginAs } from '../state/store.js';
import { escapeHtml } from '../utils/format.js';
import { icon } from '../utils/icons.js';
import { banner } from '../utils/ui.js';
import { showToast } from '../utils/a11y.js';

export function renderLogin(container, navigate) {
  const tradeName = getState().businessSettings.tradeName;
  container.innerHTML = `
    <main class="login-stage">
      <section class="login-card" aria-labelledby="page-heading">
        <div class="stack stack--sm">
          <div class="flex-wrap-gap">
            <span class="brand__mark" aria-hidden="true">${icon('utensils', 20)}</span>
            <div>
              <p class="text-xs fw-700 text-muted" style="text-transform: uppercase; letter-spacing: 0.06em;">${escapeHtml(tradeName)}</p>
              <h1 id="page-heading" tabindex="-1">Ingresá a GastroApp</h1>
            </div>
          </div>
          <p class="text-sm text-secondary">Usá tu usuario del local para acceder al punto de venta o al panel de administración.</p>
        </div>

        <div id="login-error-slot"></div>

        <form id="login-form" class="stack" novalidate>
          <div class="field">
            <label class="field__label" for="login-user">Usuario <span class="field__req" aria-hidden="true">*</span></label>
            <input
              id="login-user"
              name="username"
              type="text"
              class="input"
              autocomplete="username"
              autocorrect="off"
              autocapitalize="none"
              spellcheck="false"
              enterkeyhint="next"
              required
              data-error="login-user-err"
              placeholder="Ej.: admin o empleado"
            >
            <span id="login-user-err" class="field__error">${icon('alertOctagon', 14)} Ingresá tu nombre de usuario.</span>
          </div>

          <div class="field">
            <label class="field__label" for="login-pass">Contraseña <span class="field__req" aria-hidden="true">*</span></label>
            <div class="password-wrap">
              <input
                id="login-pass"
                name="password"
                type="password"
                class="input"
                autocomplete="current-password"
                enterkeyhint="done"
                required
                data-error="login-pass-err"
                placeholder="Ingresá tu contraseña"
              >
              <button
                type="button"
                id="toggle-pass"
                class="password-wrap__toggle"
                aria-pressed="false"
                aria-label="Mostrar contraseña"
              >
                ${icon('eye', 18)}
              </button>
            </div>
            <span id="login-pass-err" class="field__error">${icon('alertOctagon', 14)} Ingresá tu contraseña.</span>
          </div>

          <button type="submit" class="btn btn--primary btn--lg btn--block">
            ${icon('lock', 18)}
            <span>Iniciar sesión</span>
          </button>
        </form>

        <div class="card card--compact card--subtle stack stack--sm">
          <p class="text-xs fw-700 text-muted" style="text-transform: uppercase; letter-spacing: 0.04em;">Accesos rápidos de demostración</p>
          <div class="flex-wrap-gap">
            <button type="button" class="btn btn--sm" data-quick-login="admin">Entrar como Administrador (admin)</button>
            <button type="button" class="btn btn--sm" data-quick-login="empleado">Entrar como Empleado (empleado)</button>
          </div>
          <p class="text-xs text-muted">Credenciales demo: <code>admin / admin</code> o <code>empleado / 1234</code>. Sin conexión al backend.</p>
        </div>
      </section>
    </main>
  `;

  const form = container.querySelector('#login-form');
  const userInput = container.querySelector('#login-user');
  const passInput = container.querySelector('#login-pass');
  const toggleBtn = container.querySelector('#toggle-pass');
  const errSlot = container.querySelector('#login-error-slot');

  toggleBtn.addEventListener('click', () => {
    const showing = passInput.type === 'text';
    passInput.type = showing ? 'password' : 'text';
    toggleBtn.setAttribute('aria-pressed', String(!showing));
    toggleBtn.setAttribute('aria-label', showing ? 'Mostrar contraseña' : 'Ocultar contraseña');
    toggleBtn.innerHTML = icon(showing ? 'eye' : 'eyeOff', 18);
  });

  form.addEventListener('submit', (e) => {
    e.preventDefault();
    errSlot.innerHTML = '';
    if (!form.checkValidity()) {
      form.querySelectorAll('input').forEach((inp) => {
        if (!inp.validity.valid) {
          inp.classList.add('user-invalid-fallback');
          inp.setAttribute('aria-invalid', 'true');
        }
      });
      const firstInvalid = form.querySelector(':invalid');
      firstInvalid?.focus();
      return;
    }
    const res = loginAs(userInput.value, passInput.value);
    if (!res.ok) {
      errSlot.innerHTML = banner({ variant: 'danger', title: 'No pudimos iniciar sesión', body: res.error });
      userInput.focus();
      return;
    }
    showToast(`Bienvenido/a, ${res.user.fullName}.`, 'ok');
    navigate(res.user.role === 'Employee' ? 'pos' : 'dashboard');
  });

  container.querySelectorAll('[data-quick-login]').forEach((btn) => {
    btn.addEventListener('click', () => {
      const u = btn.dataset.quickLogin;
      const res = loginAs(u, u === 'admin' ? 'admin' : '1234');
      if (!res.ok) {
        errSlot.innerHTML = banner({ variant: 'danger', title: 'Usuario no disponible', body: `${res.error} (Revisá si fue desactivado o renombrado en Configuración).` });
        return;
      }
      showToast(`Sesión iniciada como ${res.user.fullName} (${res.user.role === 'Admin' ? 'Administrador' : 'Empleado'}).`, 'ok');
      navigate(res.user.role === 'Employee' ? 'pos' : 'dashboard');
    });
  });
}
