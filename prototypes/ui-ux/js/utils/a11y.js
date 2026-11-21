import { escapeHtml } from './format.js';

let politeRegion = null;
let assertiveRegion = null;
let announceTimer = null;

export function ensureLiveRegions() {
  if (!politeRegion) {
    politeRegion = document.getElementById('live-polite');
    if (!politeRegion) {
      politeRegion = document.createElement('div');
      politeRegion.id = 'live-polite';
      politeRegion.setAttribute('aria-live', 'polite');
      politeRegion.setAttribute('aria-atomic', 'true');
      politeRegion.className = 'visually-hidden';
      document.body.append(politeRegion);
    }
  }
  if (!assertiveRegion) {
    assertiveRegion = document.getElementById('live-assertive');
    if (!assertiveRegion) {
      assertiveRegion = document.createElement('div');
      assertiveRegion.id = 'live-assertive';
      assertiveRegion.setAttribute('aria-live', 'assertive');
      assertiveRegion.setAttribute('aria-atomic', 'true');
      assertiveRegion.className = 'visually-hidden';
      document.body.append(assertiveRegion);
    }
  }
}

export function announce(message, urgency = 'polite') {
  ensureLiveRegions();
  if (typeof document.ariaNotify === 'function') {
    try {
      document.ariaNotify(message, { priority: urgency === 'assertive' ? 'high' : 'normal' });
      return;
    } catch {
      // Fall back to live region
    }
  }
  const region = urgency === 'assertive' ? assertiveRegion : politeRegion;
  region.textContent = '';
  window.setTimeout(() => {
    region.textContent = message;
  }, 60);
}

/**
 * MWG accessible-error-announcement + validate-input-after-interaction:
 * Syncs aria-invalid and dynamic aria-describedby with :user-invalid,
 * plus fallback class when :user-invalid is unavailable.
 */
export function initValidationSync() {
  ensureLiveRegions();
  const supportsUserInvalid = CSS.supports('selector(:user-invalid)');
  const flagged = new WeakSet();
  const announced = new WeakSet();
  const dirtyState = new WeakMap();

  const linkError = (el, shown) => {
    const errorId = el.dataset?.error;
    if (!errorId) return;
    const ids = (el.getAttribute('aria-describedby') || '')
      .split(/\s+/)
      .filter((id) => id && id !== errorId);
    if (shown) ids.push(errorId);
    if (ids.length) el.setAttribute('aria-describedby', ids.join(' '));
    else el.removeAttribute('aria-describedby');
  };

  const announceFieldError = (el) => {
    const error = el.dataset?.error ? document.getElementById(el.dataset.error) : null;
    if (!error) return;
    const labelText = el.labels?.[0]?.textContent?.replace('*', '').trim();
    const prefix = labelText ? `${labelText}: ` : '';
    clearTimeout(announceTimer);
    announceTimer = window.setTimeout(() => {
      announce(prefix + error.textContent.trim(), 'polite');
    }, 450);
  };

  const syncAria = (el, shouldAnnounce = false) => {
    if (!el || !el.matches?.('input, select, textarea')) return;
    const invalid = supportsUserInvalid
      ? el.matches(':user-invalid')
      : el.classList.contains('user-invalid-fallback');
    if (invalid) {
      if (shouldAnnounce && !announced.has(el)) {
        announceFieldError(el);
        announced.add(el);
      }
      el.setAttribute('aria-invalid', 'true');
      linkError(el, true);
      flagged.add(el);
    } else if (flagged.has(el) || el.getAttribute('aria-invalid') !== 'true') {
      el.setAttribute('aria-invalid', 'false');
      linkError(el, false);
      flagged.delete(el);
      announced.delete(el);
    }
  };

  const handleFallback = (el, eventType) => {
    if (supportsUserInvalid || !el?.checkValidity) return;
    if (eventType === 'invalid') {
      dirtyState.set(el, { interacted: true, blurred: true });
      el.classList.toggle('user-invalid-fallback', !el.validity.valid);
      return;
    }
    const state = dirtyState.get(el) || { interacted: false, blurred: false };
    if (eventType === 'input' || eventType === 'change') {
      state.interacted = true;
      dirtyState.set(el, state);
      if (state.blurred) el.classList.toggle('user-invalid-fallback', !el.validity.valid);
    } else if (eventType === 'blur') {
      state.blurred = true;
      dirtyState.set(el, state);
      if (state.interacted) el.classList.toggle('user-invalid-fallback', !el.validity.valid);
    }
  };

  document.addEventListener('blur', (e) => {
    handleFallback(e.target, 'blur');
    syncAria(e.target, true);
  }, true);

  document.addEventListener('input', (e) => {
    handleFallback(e.target, 'input');
    if (e.target.hasAttribute?.('aria-invalid')) syncAria(e.target, false);
  });

  document.addEventListener('change', (e) => {
    handleFallback(e.target, 'change');
    syncAria(e.target, true);
  }, true);

  document.addEventListener('invalid', (e) => {
    handleFallback(e.target, 'invalid');
    announced.add(e.target);
    syncAria(e.target, false);
  }, true);

  document.addEventListener('reset', (e) => {
    window.setTimeout(() => {
      const elements = e.target?.elements || [];
      for (const el of elements) {
        dirtyState.delete(el);
        el.classList?.remove('user-invalid-fallback');
        syncAria(el, false);
      }
    });
  }, true);

  return {
    primeFields(root = document) {
      root.querySelectorAll('input, select, textarea').forEach((el) => {
        if (!el.hasAttribute('aria-invalid')) el.setAttribute('aria-invalid', 'false');
      });
    },
  };
}

/**
 * MWG light-dismiss-a-dialog fallback when closedby is unsupported (e.g. Safari)
 */
export function attachLightDismissFallback(dialog) {
  if ('closedBy' in HTMLDialogElement.prototype) return;
  if (dialog.getAttribute('closedby') !== 'any') return;
  if (dialog.dataset.lightDismissBound) return;
  dialog.dataset.lightDismissBound = '1';

  const isOutside = (e) => {
    const r = dialog.getBoundingClientRect();
    return e.clientX < r.left || e.clientX > r.right || e.clientY < r.top || e.clientY > r.bottom;
  };
  let pressedOutside = false;
  dialog.addEventListener('pointerdown', (e) => {
    pressedOutside = isOutside(e);
  });
  dialog.addEventListener('pointerup', (e) => {
    if (pressedOutside && isOutside(e)) dialog.close();
  });
}

/**
 * MWG navigation-drawer pattern using native <dialog> + scroll-snap + IntersectionObserver
 */
export function initNavigationDrawer(drawer, closeBtn) {
  if (!drawer || !closeBtn) return { open: () => {}, close: () => {}, attachTrigger: () => {} };
  const scroller = drawer.querySelector('.drawer-scroller');
  const sheet = drawer.querySelector('.drawer-sheet');
  let isOpen = false;
  let currentOpenBtn = null;

  const openDrawer = async () => {
    if (drawer.open) return;
    isOpen = true;
    drawer.showModal();
    currentOpenBtn?.setAttribute('aria-expanded', 'true');
    if (!CSS.supports('scroll-initial-target', 'nearest')) {
      scroller.scrollTo({ left: scroller.offsetWidth, behavior: 'instant' });
      await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)));
    }
    scroller.scrollTo({ left: 0, behavior: 'auto' });
  };

  const closeDrawer = () => {
    if (!drawer.open) return;
    scroller.scrollTo({ left: scroller.offsetWidth, behavior: 'auto' });
    window.setTimeout(() => {
      if (drawer.open && scroller.scrollLeft >= sheet.offsetWidth - 4) {
        finalizeClose();
      }
    }, 280);
  };

  const finalizeClose = () => {
    if (!isOpen && !drawer.open) return;
    isOpen = false;
    if (drawer.open) drawer.close();
    currentOpenBtn?.setAttribute('aria-expanded', 'false');
  };

  if (!CSS.supports('animation-timeline: scroll()')) {
    scroller.addEventListener('scroll', () => {
      const ratio = sheet.offsetWidth ? Math.max(0, Math.min(1, 1 - scroller.scrollLeft / sheet.offsetWidth)) : 0;
      drawer.style.setProperty('--drawer-backdrop', String(ratio));
    });
  }

  const visibleThreshold = Math.max(0.01, 1 / Math.max(window.innerWidth, 320));
  const observer = new IntersectionObserver(
    (entries) => {
      const entry = entries.at(-1);
      if (!entry || !drawer.open) return;
      if (entry.intersectionRatio < visibleThreshold) {
        finalizeClose();
      }
    },
    { root: drawer, threshold: [visibleThreshold, 1] }
  );
  observer.observe(sheet);

  closeBtn.addEventListener('click', closeDrawer);
  drawer.addEventListener('click', (e) => {
    if (!sheet.contains(e.target)) closeDrawer();
  });
  drawer.addEventListener('cancel', (e) => {
    if (e.cancelable) {
      e.preventDefault();
      closeDrawer();
    }
  });

  return {
    open: openDrawer,
    close: closeDrawer,
    attachTrigger(openBtn) {
      currentOpenBtn = openBtn;
      openBtn?.addEventListener('click', openDrawer);
    },
  };
}

/**
 * MWG persistent-toast-notifications using native popover="manual" + focus pause + modal suppression
 */
let toastCounter = 0;
export function showToast(message, variant = 'ok', durationMs = 4800) {
  // Suppress visual toast while a modal dialog is open (MWG guideline)
  if (document.querySelector('dialog:modal')) {
    announce(message, variant === 'danger' ? 'assertive' : 'polite');
    return;
  }

  const region = document.getElementById('toast-region');
  if (!region) return;

  // Keep bottom-right top-layer area crisp by replacing previous active toast
  region.querySelectorAll('.toast').forEach((prev) => {
    try { prev.hidePopover?.(); } catch { /* ignore */ }
    prev.remove();
  });

  const id = `toast-${++toastCounter}`;
  const el = document.createElement('div');
  el.id = id;
  el.setAttribute('popover', 'manual');
  el.className = `toast toast--${variant}`;
  el.innerHTML = `
    <span class="toast__text">${escapeHtml(message)}</span>
    <button type="button" class="toast__close" popovertarget="${id}" popovertargetaction="hide" aria-label="Cerrar notificación">Cerrar</button>
  `;
  region.append(el);

  const supportsPopover = Object.hasOwn(HTMLElement.prototype, 'popover');
  if (supportsPopover && typeof el.showPopover === 'function') {
    try {
      el.showPopover();
    } catch {
      el.classList.add(':popover-open');
    }
  } else {
    el.classList.add(':popover-open');
  }

  announce(message, variant === 'danger' ? 'assertive' : 'polite');

  let timer = null;
  const dismiss = () => {
    clearTimeout(timer);
    if (supportsPopover && typeof el.hidePopover === 'function') {
      try { el.hidePopover(); } catch { /* ignore */ }
    }
    el.remove();
  };

  const closeBtn = el.querySelector('.toast__close');
  closeBtn.addEventListener('click', () => {
    const remaining = [...region.querySelectorAll('.toast')].filter((t) => t !== el);
    dismiss();
    if (remaining.length) {
      remaining[0].querySelector('.toast__close')?.focus();
    }
  });

  const scheduleDismiss = () => {
    clearTimeout(timer);
    if (durationMs > 0) {
      timer = window.setTimeout(() => {
        if (el.contains(document.activeElement)) return;
        dismiss();
      }, durationMs);
    }
  };

  el.addEventListener('focusin', () => clearTimeout(timer));
  el.addEventListener('focusout', () => scheduleDismiss());
  scheduleDismiss();
}
