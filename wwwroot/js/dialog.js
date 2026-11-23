// Native <dialog> helper for Shared/ModalDialog.razor (ported from the prototype's openModal +
// attachLightDismissFallback). Imported on demand through JS interop; one session per dialog element.

const sessions = new WeakMap();

const BODY_CONTROL = '.modal__body :is(input:not([type="hidden"]), select, textarea, button):not([disabled])';

// Fallback for browsers without `closedby` (e.g. Safari): a press AND release outside the box closes it.
function bindLightDismissFallback(dialog) {
    const isOutside = (event) => {
        const rect = dialog.getBoundingClientRect();
        return event.clientX < rect.left || event.clientX > rect.right
            || event.clientY < rect.top || event.clientY > rect.bottom;
    };
    let pressedOutside = false;
    const onDown = (event) => { pressedOutside = isOutside(event); };
    const onUp = (event) => { if (pressedOutside && isOutside(event)) dialog.close(); };
    dialog.addEventListener('pointerdown', onDown);
    dialog.addEventListener('pointerup', onUp);
    return () => {
        dialog.removeEventListener('pointerdown', onDown);
        dialog.removeEventListener('pointerup', onUp);
    };
}

// Honour [autofocus]; otherwise prefer the first body control over the header's close button.
function ensureInitialFocus(dialog) {
    if (dialog.querySelector('[autofocus]')) return;
    dialog.querySelector(BODY_CONTROL)?.focus();
}

function teardown(dialog) {
    const session = sessions.get(dialog);
    if (!session) return null;
    sessions.delete(dialog);
    dialog.removeEventListener('close', session.onClose);
    session.unbindFallback?.();
    return session;
}

// `generation` identifies each ShowAsync call so .NET can ignore the close of a previous opening.
export function open(dialog, dotNetRef, lightDismiss, generation) {
    if (!dialog) return;
    if (dialog.open) {
        const current = sessions.get(dialog);
        if (current) current.generation = generation; // repeated show request: the open dialog now belongs to it
        return;
    }
    teardown(dialog);

    dialog.returnValue = '';
    dialog.setAttribute('closedby', lightDismiss ? 'any' : 'closerequest');

    const session = { generation, onClose: null, unbindFallback: null };
    const onClose = () => {
        // Reset so a later Esc/backdrop close is never mistaken for the previous action.
        const returnValue = dialog.returnValue || '';
        dialog.returnValue = '';
        teardown(dialog);
        dotNetRef.invokeMethodAsync('OnNativeClosed', session.generation, returnValue).catch(() => { /* circuit gone */ });
    };
    session.onClose = onClose;
    dialog.addEventListener('close', onClose);

    if (lightDismiss && !('closedBy' in HTMLDialogElement.prototype))
        session.unbindFallback = bindLightDismissFallback(dialog);
    sessions.set(dialog, session);

    dialog.showModal();
    ensureInitialFocus(dialog);
}

export function close(dialog, returnValue) {
    if (dialog?.open) dialog.close(returnValue ?? 'cancel');
}

// Detach listeners without notifying .NET (the component is being disposed).
export function dispose(dialog) {
    if (!dialog) return;
    teardown(dialog);
    if (dialog.open) dialog.close();
}
