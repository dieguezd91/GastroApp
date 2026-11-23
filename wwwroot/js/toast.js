// Popover toast presenter for Shared/Toast.razor (ported from the prototype's showToast).
// The markup is rendered by Blazor; this module only shows it in the top layer and owns the timer.

const timers = new WeakMap();

function clear(el) {
    const timer = timers.get(el);
    if (timer) window.clearTimeout(timer);
    timers.delete(el);
}

// Returns false when the toast is suppressed because a modal dialog is open; the live region
// rendered by Toast.razor still announces the message in that case.
export function present(el, durationMs, dotNetRef, id) {
    if (!el) return false;
    if (document.querySelector('dialog:modal')) return false;

    if (typeof el.showPopover === 'function') {
        try { el.showPopover(); } catch { el.classList.add(':popover-open'); }
    } else {
        el.classList.add(':popover-open');
    }

    const expire = () => dotNetRef.invokeMethodAsync('OnExpired', id).catch(() => { /* circuit gone */ });
    const schedule = () => {
        clear(el);
        if (durationMs > 0) {
            timers.set(el, window.setTimeout(() => {
                if (el.contains(document.activeElement)) return; // keyboard users keep it until focus leaves
                expire();
            }, durationMs));
        }
    };
    el.addEventListener('focusin', () => clear(el));
    el.addEventListener('focusout', schedule);
    schedule();
    return true;
}

export function dismiss(el) {
    if (!el) return;
    clear(el);
    if (typeof el.hidePopover === 'function') {
        try { el.hidePopover(); } catch { /* already hidden */ }
    }
}
