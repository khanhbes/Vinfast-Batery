import { useLayoutEffect, useRef, type ReactNode } from 'react';
import { createPortal } from 'react-dom';

/** Native modal provides focus trapping, Escape handling and an inert page.
 * Portaling avoids fixed-position clipping inside animated page containers. */
export function ModalSurface({ children, label, onClose, busy = false, drawer = false }: {
  children: ReactNode; label: string; onClose: () => void; busy?: boolean; drawer?: boolean;
}) {
  const dialog = useRef<HTMLDialogElement>(null);
  useLayoutEffect(() => {
    const element = dialog.current;
    const trigger = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    element?.showModal();
    return () => {
      element?.close();
      // React removes the portal node during commit. Restore after that commit,
      // without stealing focus from a different modal opened in the meantime.
      queueMicrotask(() => {
        const dialogs = Array.from(document.querySelectorAll('dialog[open]'));
        const top = dialogs[dialogs.length - 1];
        if (trigger?.isConnected && (!top || top.contains(trigger))) {
          trigger.focus({ preventScroll: true });
        }
      });
    };
  }, []);
  return createPortal(<dialog ref={dialog} aria-label={label} aria-busy={busy}
    className={`ui-dialog ${drawer ? 'dark ui-drawer' : ''}`}
    onCancel={event => { event.preventDefault(); event.stopPropagation(); if (!busy) onClose(); }}
    onClick={event => {
      if (event.target !== event.currentTarget || busy) return;
      const rect = event.currentTarget.getBoundingClientRect();
      if (event.clientX < rect.left || event.clientX > rect.right || event.clientY < rect.top || event.clientY > rect.bottom) onClose();
    }}
  >{children}</dialog>, document.body);
}
