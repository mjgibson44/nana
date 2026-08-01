interface ConfirmDialogProps {
  /** Null when nothing is being asked. */
  message: string | null;
  confirmLabel: string;
  onConfirm: () => void;
  onCancel: () => void;
}

export function ConfirmDialog({
  message,
  confirmLabel,
  onConfirm,
  onCancel,
}: ConfirmDialogProps) {
  if (message === null) return null;

  return (
    <div className="splash-backdrop" onClick={onCancel} role="presentation">
      <div
        className="dialog"
        role="dialog"
        aria-modal="true"
        // Clicking inside shouldn't count as clicking the backdrop away.
        onClick={(e) => e.stopPropagation()}
      >
        <p className="dialog-message">{message}</p>
        <div className="dialog-actions">
          <button type="button" className="btn btn-cancel" onClick={onCancel}>
            Keep playing
          </button>
          <button type="button" className="btn btn-primary" onClick={onConfirm}>
            {confirmLabel}
          </button>
        </div>
      </div>
    </div>
  );
}
