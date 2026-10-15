// ─────────────────────────────────────────────────────────────
// CBLRE Admin · Reusable confirmation modal + imperative hook
// ─────────────────────────────────────────────────────────────
// Single source of truth for every destructive/irreversible admin
// action. The backend API call is wired to onConfirm and fires
// ONLY after the admin explicitly clicks "Confirm".
// Usage (imperative, from any page):
//   const { open, close, setConfirm } = useConfirm();
//   setConfirm({
//     open: true,
//     title: "Delete account?",
//     message: "Permanently delete ...",
//     confirmLabel: "Delete",
//     destructive: true,
//     onConfirm: async () => { await deleteAccount(id); load(); },
//   });
// ─────────────────────────────────────────────────────────────
import { useEffect, useRef } from "react";

export default function ConfirmModal({
  open, title, message,
  confirmLabel = "Confirm", cancelLabel = "Cancel",
  destructive = false, onConfirm, onClose,
}) {
  const ref = useRef(null);
  useEffect(() => {
    const ann = document.getElementById("confirm-announce");
    if (ann) ann.textContent = title;
  }, [title]);
  const handleConfirm = async () => {
    if (onConfirm) { try { await onConfirm(); } catch (err) { console.error("[ConfirmModal]", err); } }
    if (onClose) onClose();
  };
  const headClass = destructive ? "bg-red-100 text-red-700" : "bg-emerald-100 text-emerald-700";
  const btnClass = destructive ? "bg-red-700 hover:bg-red-800" : "bg-emerald-800 hover:bg-emerald-900";
  if (!open) return null;
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4" role="alertdialog" aria-modal="true" aria-labelledby="confirm-title">
      <div className="absolute inset-0 bg-stone-900/40 backdrop-blur-sm" onClick={onClose ? () => onClose() : undefined} />
      <div ref={ref} className="relative z-10 w-full max-w-md overflow-hidden rounded-2xl border border-stone-200 bg-white shadow-xl">
        <div className="flex items-start gap-3 border-b border-stone-100 px-5 py-4">
          <div
            className={`mt-0.5 flex h-7 w-7 flex-none items-center justify-center rounded-full text-sm font-bold ${headClass}`}
          >
            {destructive ? "!" : "?"}
          </div>
          <div className="flex-1"><h3 id="confirm-title" className="text-base font-bold text-emerald-950">{title}</h3><p className="mt-1 text-sm text-stone-600">{message}</p></div>
        </div>
        <div className="flex justify-end gap-2 border-t border-stone-100 px-5 py-4">
          <button type="button" onClick={onClose ? () => onClose() : undefined} className="rounded-lg border border-stone-300 bg-white px-4 py-2 text-sm font-semibold text-emerald-950 hover:bg-stone-50">{cancelLabel}</button>
          <button data-confirm-btn="true" type="button" onClick={handleConfirm} className={`rounded-lg px-4 py-2 text-sm font-semibold text-white ${btnClass}`}>{confirmLabel}</button>
        </div>
      </div>
      <div id="confirm-announce" className="sr-only" role="status" />
    </div>
  );
}
