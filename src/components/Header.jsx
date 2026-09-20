// ─────────────────────────────────────────────────────────────
// CBLRE Admin · Header (Tailwind)
// ─────────────────────────────────────────────────────────────
// Top bar shown on every /admin/* page: current section title, admin
// identity chip, and sign-out. Logout revokes the Sanctum token via the
// AuthContext, then RequireAdmin bounces the session to /login.
// ─────────────────────────────────────────────────────────────
import { useAuth } from "../context/AuthContext";

function initialsOf(name) {
  return String(name || "A")
    .split(" ")
    .map((p) => p[0])
    .join("")
    .slice(0, 2)
    .toUpperCase();
}

export default function Header({ title }) {
  const { user, logout } = useAuth();
  const name = user?.fullName || user?.name || "Administrator";

  return (
    <header className="mb-6 flex flex-wrap items-center justify-between gap-3">
      <div className="flex items-center gap-2 text-sm">
        <span className="font-bold text-emerald-800">{title || "Admin"}</span>
        <span className="text-stone-300">•</span>
        <span className="text-stone-500">Trinidad, Bohol</span>
      </div>

      <div className="flex items-center gap-3">
        <div className="flex items-center gap-2">
          <div className="flex h-9 w-9 items-center justify-center rounded-full bg-emerald-800 text-xs font-bold text-white">
            {initialsOf(name)}
          </div>
          <div className="leading-tight">
            <p className="text-sm font-semibold text-emerald-950">{name}</p>
            <p className="text-xs text-stone-500">{user?.email || "System Administrator"}</p>
          </div>
        </div>
        <button
          type="button"
          onClick={logout}
          className="rounded-lg border border-stone-300 bg-white px-3 py-1.5 text-sm font-semibold text-emerald-950 hover:bg-emerald-50"
        >
          Sign out
        </button>
      </div>
    </header>
  );
}
