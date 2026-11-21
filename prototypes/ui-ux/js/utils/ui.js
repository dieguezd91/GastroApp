import { escapeHtml } from './format.js';
import { icon } from './icons.js';
import { attachLightDismissFallback } from './a11y.js';

export function badge(label, variant = 'neutral', iconName = null) {
  const ic = iconName ? icon(iconName, 14) : '';
  return `<span class="badge badge--${variant}">${ic}<span>${escapeHtml(label)}</span></span>`;
}

export function banner({ variant = 'info', title, body, actionHtml = '', role = null }) {
  const iconMap = {
    ok: 'checkCircle',
    warn: 'alertTriangle',
    danger: 'alertOctagon',
    info: 'info',
    proposal: 'sparkles',
  };
  const roleAttr = role ? ` role="${role}"` : (variant === 'danger' ? ' role="alert"' : '');
  return `
    <div class="banner banner--${variant}"${roleAttr}>
      <div class="banner__body">
        <span class="banner__icon">${icon(iconMap[variant] || 'info', 20)}</span>
        <div>
          ${title ? `<p class="banner__title">${escapeHtml(title)}</p>` : ''}
          ${body ? `<p>${body}</p>` : ''}
        </div>
      </div>
      ${actionHtml ? `<div class="flex-wrap-gap">${actionHtml}</div>` : ''}
    </div>
  `;
}

export function proposalBanner(moduleCode, detail) {
  return banner({
    variant: 'proposal',
    title: `Propuesta de evolución (${moduleCode}) — No implementado en el backend actual`,
    body: escapeHtml(detail),
  });
}

export function kpiCard({ label, value, meta = '', badgeHtml = '' }) {
  return `
    <article class="kpi-card">
      <div class="kpi-card__label">
        <span>${escapeHtml(label)}</span>
        ${badgeHtml}
      </div>
      <p class="kpi-card__value tnum">${escapeHtml(value)}</p>
      ${meta ? `<p class="kpi-card__meta">${escapeHtml(meta)}</p>` : ''}
    </article>
  `;
}

export function emptyState({ iconName = 'info', title, description, actionHtml = '' }) {
  return `
    <div class="empty-state">
      <div class="empty-state__icon">${icon(iconName, 24)}</div>
      <div class="stack stack--sm">
        <h3>${escapeHtml(title)}</h3>
        <p class="text-sm text-secondary">${escapeHtml(description)}</p>
      </div>
      ${actionHtml ? `<div class="mt-2">${actionHtml}</div>` : ''}
    </div>
  `;
}

export function loadingSkeleton(cards = 3) {
  const items = Array.from({ length: cards }, () => `
    <div class="skeleton-card" aria-hidden="true">
      <div class="skeleton-bar" style="inline-size: 38%"></div>
      <div class="skeleton-bar" style="inline-size: 62%; block-size: 1.75rem"></div>
      <div class="skeleton-bar" style="inline-size: 84%"></div>
    </div>
  `).join('');
  return `
    <div role="status" aria-label="Cargando contenido">
      <p class="visually-hidden">Cargando datos de la pantalla…</p>
      <div class="grid-kpi">${items}</div>
    </div>
  `;
}

/**
 * Native <dialog> modal manager following MWG dialog guidelines:
 * - No role="dialog" / aria-modal (native showModal handles it)
 * - Uses aria-labelledby pointing to heading
 * - Resets dialog.returnValue = '' on close
 * - Supports closedby="any" + fallback for non-destructive / review modals
 */
export function openModal({
  title,
  subtitle = '',
  bodyHtml,
  footerHtml = '',
  size = 'md',
  lightDismiss = true,
  onMount = null,
  onClose = null,
}) {
  const dialog = document.getElementById('app-modal');
  if (!dialog) return null;

  dialog.className = size === 'lg' ? 'modal modal--lg' : 'modal';
  if (lightDismiss) {
    dialog.setAttribute('closedby', 'any');
  } else {
    dialog.setAttribute('closedby', 'closerequest');
  }

  dialog.innerHTML = `
    <div class="modal__header">
      <div>
        <h2 id="app-modal-title">${escapeHtml(title)}</h2>
        ${subtitle ? `<p class="card__desc">${escapeHtml(subtitle)}</p>` : ''}
      </div>
      <button type="button" class="btn btn--ghost btn--icon" data-modal-close aria-label="Cerrar diálogo">
        ${icon('close', 18)}
      </button>
    </div>
    <div class="modal__body">${bodyHtml}</div>
    ${footerHtml ? `<div class="modal__footer">${footerHtml}</div>` : ''}
  `;

  dialog.setAttribute('aria-labelledby', 'app-modal-title');
  attachLightDismissFallback(dialog);

  const handleClose = () => {
    const val = dialog.returnValue || '';
    dialog.returnValue = '';
    dialog.removeEventListener('close', handleClose);
    if (onClose) onClose(val);
  };
  dialog.addEventListener('close', handleClose);

  dialog.querySelectorAll('[data-modal-close]').forEach((btn) => {
    btn.addEventListener('click', () => dialog.close('cancel'));
  });

  if (onMount) onMount(dialog);
  if (!dialog.open) dialog.showModal();
  return dialog;
}

/**
 * Destructive confirmation modal: places autofocus on the safe Cancel action (MWG rule).
 */
export function openConfirmModal({
  title,
  message,
  confirmLabel = 'Confirmar',
  confirmVariant = 'danger',
  requireReason = false,
  reasonLabel = 'Motivo (obligatorio)',
  onConfirm,
}) {
  return openModal({
    title,
    lightDismiss: false,
    bodyHtml: `
      <form id="confirm-modal-form" class="stack" novalidate>
        <p class="text-sm">${escapeHtml(message)}</p>
        ${requireReason ? `
          <div class="field">
            <label class="field__label" for="confirm-reason">${escapeHtml(reasonLabel)} <span class="field__req" aria-hidden="true">*</span></label>
            <textarea id="confirm-reason" name="reason" class="textarea" required minlength="3" data-error="confirm-reason-err" placeholder="Ej.: Error de carga en el pedido"></textarea>
            <span id="confirm-reason-err" class="field__error">${icon('alertOctagon', 14)} Ingresá un motivo válido (mínimo 3 caracteres).</span>
          </div>
        ` : ''}
        <div id="confirm-inline-err"></div>
      </form>
    `,
    footerHtml: `
      <button type="button" class="btn" data-modal-close autofocus>Cancelar</button>
      <button type="submit" form="confirm-modal-form" class="btn btn--${confirmVariant}">${escapeHtml(confirmLabel)}</button>
    `,
    onMount(dialog) {
      const form = dialog.querySelector('#confirm-modal-form');
      const errSlot = dialog.querySelector('#confirm-inline-err');
      form.addEventListener('submit', (e) => {
        e.preventDefault();
        errSlot.innerHTML = '';
        let result;
        if (requireReason) {
          const reasonEl = form.querySelector('#confirm-reason');
          const reason = reasonEl.value.trim();
          if (reason.length < 3) {
            reasonEl.setAttribute('aria-invalid', 'true');
            reasonEl.classList.add('user-invalid-fallback');
            reasonEl.focus();
            return;
          }
          result = onConfirm(reason);
        } else {
          result = onConfirm();
        }
        if (typeof result === 'string' && result) {
          errSlot.innerHTML = banner({ variant: 'danger', body: escapeHtml(result) });
          return;
        }
        if (result !== false) dialog.close('confirm');
      });
    },
  });
}
