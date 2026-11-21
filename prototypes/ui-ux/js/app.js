import {
  getState,
  subscribe,
  logout,
  switchDemoRole,
  applyDemoScenario,
  resetAllData,
  getOpenCashRegister,
  getStockAlerts,
} from './state/store.js';
import { escapeHtml } from './utils/format.js';
import { icon } from './utils/icons.js';
import { badge, banner } from './utils/ui.js';
import { initValidationSync, initNavigationDrawer, showToast } from './utils/a11y.js';

import { renderLogin } from './views/login.js';
import { renderDashboard } from './views/dashboard.js';
import { renderPos } from './views/pos.js';
import { renderCash } from './views/cash.js';
import { renderCashHistory } from './views/cashHistory.js';
import { renderSalesHistory } from './views/salesHistory.js';
import { renderSummary } from './views/summary.js';
import { renderCatalog } from './views/catalog.js';
import { renderInventory } from './views/inventory.js';
import { renderRecipes } from './views/recipes.js';
import { renderPurchasing } from './views/purchasing.js';
import { renderReports } from './views/reports.js';
import { renderSettings } from './views/settings.js';

const ROUTES = {
  login: { title: 'Iniciar sesión', crumb: 'Acceso', adminOnly: false, render: renderLogin },
  dashboard: { title: 'Inicio', crumb: 'Operación diaria', adminOnly: false, render: renderDashboard },
  pos: { title: 'Punto de Venta', crumb: 'Operación diaria', adminOnly: false, render: renderPos },
  cash: { title: 'Caja diaria', crumb: 'Caja y ventas', adminOnly: true, render: renderCash },
  'cash-history': { title: 'Historial de cajas', crumb: 'Caja y ventas', adminOnly: true, render: renderCashHistory },
  'sales-history': { title: 'Historial de ventas', crumb: 'Caja y ventas', adminOnly: true, render: renderSalesHistory },
  summary: { title: 'Resumen del día', crumb: 'Caja y ventas', adminOnly: true, render: renderSummary },
  catalog: { title: 'Productos y categorías', crumb: 'Catálogo e inventario', adminOnly: true, render: renderCatalog },
  inventory: { title: 'Ingredientes y stock', crumb: 'Catálogo e inventario', adminOnly: true, render: renderInventory },
  recipes: { title: 'Recetas y costos', crumb: 'Catálogo e inventario', adminOnly: true, render: renderRecipes },
  purchasing: { title: 'Proveedores y facturas', crumb: 'Catálogo e inventario', adminOnly: true, render: renderPurchasing },
  reports: { title: 'Reportes y rentabilidad', crumb: 'Propuesta de evolución', adminOnly: true, proposal: true, render: renderReports },
  settings: { title: 'Configuración', crumb: 'Propuesta de evolución', adminOnly: true, proposal: true, render: renderSettings },
};

let currentRoute = getRouteFromHash();
let validationSync = null;
let drawerController = null;

function getRouteFromHash() {
  const hash = window.location.hash.replace(/^#\/?/, '').trim();
  return ROUTES[hash] ? hash : 'dashboard';
}

function navigate(route) {
  if (!ROUTES[route]) route = 'dashboard';
  currentRoute = route;
  if (window.location.hash !== `#${route}`) {
    window.history.replaceState(null, '', `#${route}`);
  }
  drawerController?.close();
  renderApp(true);
}

function getNavGroups(role, stockAlertCount) {
  if (role === 'Employee') {
    return [
      {
        title: 'Operación diaria',
        items: [
          { route: 'dashboard', label: 'Inicio', icon: 'dashboard' },
          { route: 'pos', label: 'Vender (POS)', icon: 'pos' },
        ],
      },
    ];
  }

  return [
    {
      title: 'Operación diaria',
      items: [
        { route: 'dashboard', label: 'Panel operativo', icon: 'dashboard' },
        { route: 'pos', label: 'Vender (POS)', icon: 'pos' },
      ],
    },
    {
      title: 'Caja y ventas',
      items: [
        { route: 'cash', label: 'Caja diaria', icon: 'cash' },
        { route: 'cash-history', label: 'Historial de cajas', icon: 'history' },
        { route: 'sales-history', label: 'Historial de ventas', icon: 'receipt' },
        { route: 'summary', label: 'Resumen del día', icon: 'summary' },
      ],
    },
    {
      title: 'Catálogo e inventario',
      items: [
        { route: 'catalog', label: 'Productos y categorías', icon: 'products' },
        {
          route: 'inventory',
          label: 'Ingredientes y stock',
          icon: 'ingredients',
          badgeText: stockAlertCount > 0 ? String(stockAlertCount) : '',
          badgeType: 'alert',
        },
        { route: 'recipes', label: 'Recetas y costos', icon: 'recipes' },
        { route: 'purchasing', label: 'Proveedores y facturas', icon: 'suppliers' },
      ],
    },
    {
      title: 'Evolución (Propuestas)',
      items: [
        { route: 'reports', label: 'Reportes y rentabilidad', icon: 'reports', badgeText: 'Propuesta', badgeType: 'proposal' },
        { route: 'settings', label: 'Configuración', icon: 'settings', badgeText: 'Propuesta', badgeType: 'proposal' },
      ],
    },
  ];
}

function buildNavMarkup(role, activeRoute, stockAlertCount) {
  const groups = getNavGroups(role, stockAlertCount);
  const state = getState();
  const user = state.auth.currentUser;

  return `
    ${groups.map((g) => `
      <div class="nav-group">
        <p class="nav-group__title">${escapeHtml(g.title)}</p>
        <ul class="nav-list">
          ${g.items.map((item) => `
            <li>
              <a
                href="#${item.route}"
                class="nav-link"
                data-nav-route="${item.route}"
                ${activeRoute === item.route ? 'aria-current="page"' : ''}
              >
                <span class="nav-link__main">
                  ${icon(item.icon, 18)}
                  <span>${escapeHtml(item.label)}</span>
                </span>
                ${item.badgeText ? `<span class="nav-badge nav-badge--${item.badgeType}">${escapeHtml(item.badgeText)}</span>` : ''}
              </a>
            </li>
          `).join('')}
        </ul>
      </div>
    `).join('')}

    <div class="sidebar__footer">
      <div class="user-pill">
        <span class="user-pill__avatar" aria-hidden="true">${escapeHtml(user?.initials || 'US')}</span>
        <span class="user-pill__meta">
          <span class="user-pill__name">${escapeHtml(user?.fullName || 'Usuario')}</span>
          <span class="user-pill__role">${user?.role === 'Admin' ? 'Administrador' : 'Empleado'}</span>
        </span>
      </div>
      <button type="button" class="nav-link" style="background: transparent; cursor: pointer;" data-logout-btn>
        <span class="nav-link__main">
          ${icon('logout', 18)}
          <span>Cerrar sesión</span>
        </span>
      </button>
    </div>
  `;
}

function renderUnauthorized(container) {
  const user = getState().auth.currentUser;
  container.innerHTML = `
    <div class="stack" style="max-inline-size: 38rem; margin-inline: auto; padding-block-start: var(--space-6);">
      <h1 id="page-heading" tabindex="-1">Acceso denegado</h1>
      ${banner({
        variant: 'danger',
        title: 'No tenés permisos para ver esta pantalla',
        body: `Tu sesión actual corresponde a <strong>${escapeHtml(user?.fullName || '')}</strong> con rol <strong>Empleado</strong>. Esta sección es exclusiva del rol Administrador.`,
      })}
      <div class="flex-wrap-gap">
        <button type="button" class="btn btn--collect" data-unauth-go="pos">Ir al Punto de Venta</button>
        <button type="button" class="btn" data-unauth-go="dashboard">Volver al inicio</button>
      </div>
    </div>
  `;
  container.querySelectorAll('[data-unauth-go]').forEach((b) => {
    b.addEventListener('click', () => navigate(b.dataset.unauthGo));
  });
}

function syncDemoControls() {
  const state = getState();
  const role = state.auth.currentUser?.role || 'Admin';
  document.querySelectorAll('[data-demo-role]').forEach((btn) => {
    btn.setAttribute('aria-pressed', String(state.auth.isAuthenticated && btn.dataset.demoRole === role));
  });
  const sel = document.getElementById('demo-scenario');
  if (sel && sel.value !== state.demo.scenario) {
    sel.value = state.demo.scenario;
  }
}

function renderApp(moveFocusToHeading = false) {
  const state = getState();
  const root = document.getElementById('app-root');
  syncDemoControls();

  if (!state.auth.isAuthenticated || currentRoute === 'login') {
    document.title = 'Iniciar sesión | GastroApp';
    root.className = 'app-shell--auth';
    renderLogin(root, navigate);
    validationSync?.primeFields(root);
    if (moveFocusToHeading) document.getElementById('page-heading')?.focus();
    return;
  }

  const user = state.auth.currentUser;
  const routeDef = ROUTES[currentRoute] || ROUTES.dashboard;
  const openReg = getOpenCashRegister();
  const stockAlerts = getStockAlerts();
  const navHtml = buildNavMarkup(user.role, currentRoute, stockAlerts.length);

  document.title = `${routeDef.title} | GastroApp`;
  root.className = 'app-shell';
  root.innerHTML = `
    <aside class="sidebar" aria-label="Navegación principal">
      <div class="sidebar__inner">
        <div class="brand">
          <span class="brand__mark" aria-hidden="true">${icon('utensils', 20)}</span>
          <span class="brand__text">
            <span class="brand__name">GastroApp</span>
            <span class="brand__venue">${escapeHtml(state.businessSettings.tradeName.split('—')[0].trim())}</span>
          </span>
        </div>
        <nav aria-label="Menú principal">
          ${navHtml}
        </nav>
      </div>
    </aside>

    <div class="app-workspace">
      <header class="topbar">
        <div class="topbar__left">
          <button
            type="button"
            id="drawer-open"
            class="topbar__menu-btn"
            aria-label="Abrir menú de navegación"
            aria-expanded="false"
            aria-controls="nav-drawer"
          >
            ${icon('menu', 20)}
          </button>
          <div class="topbar__title-wrap">
            <span class="topbar__crumb">${escapeHtml(routeDef.crumb)}</span>
            <span class="fw-700 text-sm">${escapeHtml(routeDef.title)}</span>
          </div>
        </div>

        <div class="topbar__right">
          ${openReg ? badge(`Caja #${openReg.id} abierta`, 'ok', 'checkCircle') : badge('Caja cerrada', 'danger', 'alertOctagon')}
          ${badge(user.role === 'Admin' ? 'Administrador' : 'Empleado', user.role === 'Admin' ? 'info' : 'neutral')}
        </div>
      </header>

      <main class="main-content" id="view-root"></main>
    </div>
  `;

  // Sync mobile drawer navigation body & venue name
  const drawerBody = document.getElementById('drawer-nav-body');
  if (drawerBody) drawerBody.innerHTML = navHtml;
  const drawerVenue = document.getElementById('drawer-venue-name');
  if (drawerVenue) drawerVenue.textContent = state.businessSettings.tradeName.split('—')[0].trim();

  // Bind navigation drawer trigger (drawer itself initialized once in bootstrap)
  const openBtn = document.getElementById('drawer-open');
  drawerController?.attachTrigger(openBtn);

  // Bind navigation links in both desktop sidebar and mobile drawer
  document.querySelectorAll('[data-nav-route]').forEach((a) => {
    a.addEventListener('click', (e) => {
      e.preventDefault();
      navigate(a.dataset.navRoute);
    });
  });

  document.querySelectorAll('[data-logout-btn]').forEach((btn) => {
    btn.addEventListener('click', () => {
      drawerController?.close();
      logout();
      currentRoute = 'login';
      showToast('Cerraste sesión correctamente.', 'ok');
    });
  });

  // Render active view or Unauthorized guard
  const viewRoot = document.getElementById('view-root');
  if (routeDef.adminOnly && user.role !== 'Admin') {
    document.title = 'Acceso denegado | GastroApp';
    renderUnauthorized(viewRoot);
  } else {
    routeDef.render(viewRoot, navigate);
  }

  validationSync?.primeFields(viewRoot);
  if (moveFocusToHeading) {
    document.getElementById('page-heading')?.focus();
  }
}

function bootstrap() {
  validationSync = initValidationSync();
  drawerController = initNavigationDrawer(
    document.getElementById('nav-drawer'),
    document.getElementById('drawer-close')
  );

  // Demo bar interactions
  document.querySelectorAll('[data-demo-role]').forEach((btn) => {
    btn.addEventListener('click', () => {
      const targetRole = btn.dataset.demoRole;
      switchDemoRole(targetRole);
      if (currentRoute === 'login') currentRoute = targetRole === 'Employee' ? 'pos' : 'dashboard';
      showToast(`Vista cambiada a rol ${targetRole === 'Admin' ? 'Administrador' : 'Empleado'}.`, 'ok');
    });
  });

  document.getElementById('demo-scenario')?.addEventListener('change', (e) => {
    const val = e.target.value;
    applyDemoScenario(val);
    const names = {
      normal: 'Operación normal restaurada.',
      'closed-cash': 'Escenario activo: Caja cerrada (el POS bloquea el cobro).',
      'critical-stock': 'Escenario activo: Stock crítico / agotado.',
      'stale-arqueo': 'Escenario activo: Arqueo desactualizado en Caja.',
      empty: 'Escenario activo: Estados vacíos.',
      loading: 'Escenario activo: Estados de carga.',
    };
    showToast(names[val] || 'Escenario actualizado.', 'info');
  });

  document.getElementById('demo-login-btn')?.addEventListener('click', () => {
    navigate('login');
  });

  document.getElementById('demo-reset-btn')?.addEventListener('click', () => {
    resetAllData();
    showToast('Datos ficticios restaurados a su estado inicial.', 'ok');
  });

  window.addEventListener('hashchange', () => {
    currentRoute = getRouteFromHash();
    renderApp(true);
  });

  subscribe(() => renderApp(false));
  renderApp(false);
}

bootstrap();
