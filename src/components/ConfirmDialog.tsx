interface ConfirmDialogProps {
  /** Null when nothing is being asked. */
  message: string | null;
  confirmLabel: string;
  /** The safe way out — also what clicking the backdrop does. Pass null for a
   * one-button notice, where confirming is the only way on. */
  cancelLabel?: string | null;
  onConfirm: () => void;
  onCancel?: () => void;
}

export function ConfirmDialog({
  message,
  confirmLabel,
  cancelLabel = 'Keep playing',
  onConfirm,
  onCancel,
}: ConfirmDialogProps) {
  if (message === null) return null;

  const dismiss = cancelLabel === null ? onConfirm : (onCancel ?? onConfirm);

  return (
    <div className="splash-backdrop" onClick={dismiss} role="presentation">
      <div
        className="dialog"
        role="dialog"
        aria-modal="true"
        // Clicking inside shouldn't count as clicking the backdrop away.
        onClick={(e) => e.stopPropagation()}
      >
        <p className="dialog-message">{message}</p>
        <div className="dialog-actions">
          {cancelLabel !== null && (
            <button type="button" className="btn btn-cancel" onClick={onCancel}>
              {cancelLabel}
            </button>
          )}
          <button type="button" className="btn btn-primary" onClick={onConfirm}>
            {confirmLabel}
          </button>
        </div>
      </div>
    </div>
  );
}
