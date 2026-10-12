import { useEffect, useRef } from "react";

/**
 * Revalidates `revalidate` on an interval so the view updates on its own as
 * the backend changes (new listings, status flips, new inquiries…) without a
 * hard browser reload.
 *
 * Two hardening details beyond a bare setInterval:
 *   1. The callback is held in a ref, so the interval is NOT torn down and
 *      rebuilt every render — pages pass inline closures (e.g. the Inquiries
 *      thread poller) and a naive [revalidate] dependency would reset the
 *      timer on every fetch.
 *   2. A visibilitychange listener fires one immediate refresh when the tab
 *      is brought back to the foreground. Background tabs throttle timers, so
 *      without this an operator returning to the console would see a stale
 *      snapshot until the next tick.
 *
 * An in-flight guard stops a slow request from stacking up behind the timer.
 */
export function useAutoRefresh(revalidate, interval = 15000) {
  const saved = useRef(revalidate);

  // Keep the latest callback without re-arming the interval every render.
  useEffect(() => {
    saved.current = revalidate;
  }, [revalidate]);

  useEffect(() => {
    let disposed = false;
    let running = false;

    const run = async () => {
      if (disposed || running) return;
      running = true;
      try {
        await saved.current?.();
      } finally {
        running = false;
      }
    };

    const id = setInterval(run, interval);

    const onVisibility = () => {
      if (document.visibilityState === "visible") run();
    };
    document.addEventListener("visibilitychange", onVisibility);

    return () => {
      disposed = true;
      clearInterval(id);
      document.removeEventListener("visibilitychange", onVisibility);
    };
  }, [interval]);
}
