// Navigation drawer for viewports below 72rem (ported from prototypes/ui-ux/js/utils/a11y.js,
// initNavigationDrawer). A native modal <dialog> holds a scroll-snap sheet; swiping or
// scrolling it away closes the dialog. Imported on demand from MainLayout via JS interop.

const DESKTOP_QUERY = '(min-width: 72rem)';

let active = null;

export function initDrawer(drawer, openButton, closeButton) {
    disposeDrawer();
    if (!drawer || !openButton || !closeButton) return;

    const scroller = drawer.querySelector('.drawer-scroller');
    const sheet = drawer.querySelector('.drawer-sheet');
    if (!scroller || !sheet) return;

    let closeTimer = 0;

    const open = async () => {
        if (drawer.open) return;
        drawer.showModal();
        openButton.setAttribute('aria-expanded', 'true');
        if (!CSS.supports('scroll-initial-target', 'nearest')) {
            scroller.scrollTo({ left: scroller.offsetWidth, behavior: 'instant' });
            await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
        }
        scroller.scrollTo({ left: 0, behavior: 'auto' });
    };

    const finalizeClose = () => {
        if (drawer.open) drawer.close();
        openButton.setAttribute('aria-expanded', 'false');
    };

    // Animate the sheet out by scrolling it off-screen; fall back to a direct close.
    const close = () => {
        if (!drawer.open) return;
        scroller.scrollTo({ left: scroller.offsetWidth, behavior: 'auto' });
        window.clearTimeout(closeTimer);
        closeTimer = window.setTimeout(() => {
            if (drawer.open && scroller.scrollLeft >= sheet.offsetWidth - 4) finalizeClose();
        }, 280);
    };

    const onScroll = () => {
        const ratio = sheet.offsetWidth
            ? Math.max(0, Math.min(1, 1 - scroller.scrollLeft / sheet.offsetWidth))
            : 0;
        drawer.style.setProperty('--drawer-backdrop', String(ratio));
    };
    if (!CSS.supports('animation-timeline: scroll()')) {
        scroller.addEventListener('scroll', onScroll);
    }

    const visibleThreshold = Math.max(0.01, 1 / Math.max(window.innerWidth, 320));
    const observer = new IntersectionObserver((entries) => {
        const entry = entries.at(-1);
        if (entry && drawer.open && entry.intersectionRatio < visibleThreshold) finalizeClose();
    }, { root: drawer, threshold: [visibleThreshold, 1] });
    observer.observe(sheet);

    const onDrawerClick = (event) => {
        // Backdrop click, or activating any link/button inside the sheet (navigation, logout).
        if (!sheet.contains(event.target)) return close();
        if (event.target.closest('a[href], button:not([data-drawer-close])')) finalizeClose();
    };
    const onCancel = (event) => {
        if (event.cancelable) {
            event.preventDefault();
            close();
        }
    };
    const onNativeClose = () => openButton.setAttribute('aria-expanded', 'false');

    const desktop = window.matchMedia(DESKTOP_QUERY);
    const onViewportChange = (event) => {
        if (event.matches) finalizeClose();
    };

    openButton.addEventListener('click', open);
    closeButton.addEventListener('click', close);
    drawer.addEventListener('click', onDrawerClick);
    drawer.addEventListener('cancel', onCancel);
    drawer.addEventListener('close', onNativeClose);
    desktop.addEventListener('change', onViewportChange);

    active = () => {
        window.clearTimeout(closeTimer);
        observer.disconnect();
        scroller.removeEventListener('scroll', onScroll);
        openButton.removeEventListener('click', open);
        closeButton.removeEventListener('click', close);
        drawer.removeEventListener('click', onDrawerClick);
        drawer.removeEventListener('cancel', onCancel);
        drawer.removeEventListener('close', onNativeClose);
        desktop.removeEventListener('change', onViewportChange);
        if (drawer.open) drawer.close();
    };
}

export function disposeDrawer() {
    if (active) {
        active();
        active = null;
    }
}
