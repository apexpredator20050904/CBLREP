// ─────────────────────────────────────────────────────────────
// CBLRE Admin · Imperative confirmation-modal hook
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
import { useEffect, useRef, useState } from "react";

export function useConfirm() {
  const [state, setState] = useState({
    open: false,
    title: "Confirm action",
    message: "",
    confirmLabel: "Confirm",
    cancelLabel: "Cancel",
    destructive: false,
    onConfirm: null,
  });
  const modalRef = useRef(null);
  const open = (opts = {}) =>
    setState((s) => ({
      ...s, open: true,
      title: opts.title ?? s.title,
      message: opts.message ?? s.message,
      confirmLabel: opts.confirmLabel ?? s.confirmLabel,
      cancelLabel: opts.cancelLabel ?? s.cancelLabel,
      destructive: opts.destructive ?? s.destructive,
      onConfirm: opts.onConfirm ?? null,
    }));
  const close = () => setState((s) => ({ ...s, open: false, onConfirm: null }));
  const setConfirm = (opts) => open(opts);
  useEffect(() => {
    const btn = modalRef.current?.querySelector("[data-confirm-btn]");
    if (btn) btn.focus();
    const keydown = (e) => { if (e.key === "Escape") close(); };
    document.addEventListener("keydown", keydown);
    return () => document.removeEventListener("keydown", keydown);
  }, [state.open]);
  return { open, close, setConfirm, state, modalRef };
}
