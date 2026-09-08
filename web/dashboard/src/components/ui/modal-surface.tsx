import { useEffect, useRef, type ReactNode } from 'react';
import { createPortal } from 'react-dom';

/** Native modal provides focus trapping, Escape handling and an inert page.
 * Portaling avoids fixed-position clipping inside animated page containers. */
export function ModalSurface({ children, label, onClose, busy = false, drawer = false }: {
  children: ReactNode; label: string; onClose: () => void; busy?: boolean; drawer?: boolean;
}) {
  const dialog = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    const element = dialog.current;
    element?.showModal();
    return () => element?.close();
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
