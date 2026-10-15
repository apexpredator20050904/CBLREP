<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\AuditLog;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

/**
 * Admin account & role management (CRUD) — backs the React
 * AdminAccountsPage (/admin/accounts).
 *
 * Route middleware enforces authentication (auth:sanctum) and the admin
 * tier (admin); every handler re-checks the role as defence in depth and
 * writes an immutable audit_logs row for every state change.
 *
 * Privilege rules:
 *   - Only a super_admin can create/delete administrator accounts or
 *     change role assignments (enforced by middleware AND code).
 *   - A regular admin may create/edit *member* accounts only.
 *   - The last super_admin and the acting account itself can never be
 *     deleted or demoted (avoids locking the system out).
 *   - Passwords are always stored hashed (bcrypt) and never echoed back.
 */
class AdminUserController extends Controller
{
    /** Columns the DataTable may sort by (whitelist — never trust input). */
    private const SORTABLE = [
        'id', 'name', 'email', 'role', 'verification_status',
        'account_status', 'barangay_or_location', 'created_at',
    ];

    // ------------------------------------------------------------------
    // READ — GET /admin/accounts (server-side filter + sort + paginate)
    // ------------------------------------------------------------------

    public function index(Request $request)
    {
        $this->guard($request);

        $query = User::query()->withCount('resources');

        // Global search: name, email, barangay.
        if ($q = trim((string) $request->query('q'))) {
            $query->where(function ($w) use ($q) {
                $w->where('name', 'like', "%{$q}%")
                    ->orWhere('email', 'like', "%{$q}%")
                    ->orWhere('barangay_or_location', 'like', "%{$q}%");
            });
        }

        // Column-level filters (DataTable per-column inputs).
        if ($name = trim((string) $request->query('filter_name'))) {
            $query->where('name', 'like', "%{$name}%");
        }
        if ($email = trim((string) $request->query('filter_email'))) {
            $query->where('email', 'like', "%{$email}%");
        }
        if ($role = trim((string) $request->query('filter_role'))) {
            $query->where('role', $role);
        }
        if ($status = trim((string) $request->query('filter_account_status'))) {
            $query->where('account_status', $status);
        }
        if ($verification = trim((string) $request->query('filter_verification_status'))) {
            $query->where('verification_status', $verification);
        }
        if ($barangay = trim((string) $request->query('filter_barangay_or_location'))) {
            $query->where('barangay_or_location', 'like', "%{$barangay}%");
        }
        if ($request->query('filter_student_status') === '1') {
            $query->where('student_status', true);
        }

        // Sorting — whitelist the column, clamp the direction.
        $sortBy = in_array($request->query('sort_by'), self::SORTABLE, true)
            ? $request->query('sort_by')
            : 'created_at';
        $sortDir = strtolower((string) $request->query('sort_dir', 'desc')) === 'asc' ? 'asc' : 'desc';
        $query->orderBy($sortBy, $sortDir);

        // Pagination — page/per_page with sane bounds.
        $perPage = max(5, min((int) $request->query('per_page', 10), 100));
        $paginator = $query->paginate($perPage)->withQueryString();

        $rows = collect($paginator->items())->map(fn (User $u) => $this->accountRow($u))->values();

        // Backwards-compatible `users` key + DataTable-friendly envelope:
        // { data: [...], meta: { current_page, per_page, total, last_page, ... } }
        return response()->json([
            'users' => $rows,
            'data' => $rows,
            'total' => $paginator->total(),
            'meta' => [
                'current_page' => $paginator->currentPage(),
                'per_page' => $paginator->perPage(),
                'total' => $paginator->total(),
                'last_page' => $paginator->lastPage(),
                'from' => $paginator->firstItem(),
                'to' => $paginator->lastItem(),
            ],
        ]);
    }

    // ------------------------------------------------------------------
    // CREATE — POST /admin/accounts
    // ------------------------------------------------------------------

    public function store(Request $request)
    {
        $actor = $this->guard($request);

        $validated = $request->validate([
            // Case-insensitive uniqueness on both identity fields. The closure
            // rules mirror AuthController so an admin cannot create the
            // duplicate the DB unique index would otherwise reject with a raw
            // 500 (and, for updates, so they can keep their own value).
            'name' => ['required', 'string', 'max:255', $this->uniqueNameRule()],
            'email' => ['required', 'email:rfc', 'max:255', $this->uniqueEmailRule()],
            'password' => ['required', 'string', 'min:8', 'max:128'],
            'role' => ['required', Rule::in(User::ROLES)],
            'barangay_or_location' => ['nullable', 'string', \App\Support\Barangays::rule()],
            'purok_sitio' => ['nullable', 'string', 'max:255'],
            'student_status' => ['nullable', 'boolean'],
            'student_school' => ['nullable', 'string', 'max:255'],
        ]);

        // Single-account lockdown: no new admin accounts may be created.
        // The system is restricted to one Super Admin only.
        if (in_array($validated['role'], [User::ROLE_ADMIN, User::ROLE_SUPER_ADMIN], true)) {
            throw ValidationException::withMessages([
                'role' => 'Administrator account creation is disabled. Only the designated Super Admin may access the system.',
            ]);
        }

        $user = User::create([
            'name' => trim($validated['name']),
            'email' => strtolower(trim($validated['email'])),
            // The model's `hashed` cast bcrypt-hashes this on save.
            'password' => $validated['password'],
            'role' => $validated['role'],
            // Residency verification is strictly submission → review: an
            // admin-created account starts `unverified` and can only become
            // `verified` by submitting proof and passing the Verification
            // queue. There is deliberately no is_verified shortcut here.
            'is_verified' => false,
            'verification_status' => 'unverified',
            'account_status' => 'active',
            'barangay_or_location' => $validated['barangay_or_location'] ?? null,
            'barangay' => $validated['barangay_or_location'] ?? null,
            'purok_sitio' => $validated['purok_sitio'] ?? null,
            'student_status' => (bool) ($validated['student_status'] ?? false),
            'student_school' => $validated['student_school'] ?? null,
        ]);

        AuditLog::record(
            $request,
            'Created account '.$user->email.' ('.$user->roleLabel().')',
            'user',
            $user->id,
        );

        return response()->json([
            'message' => 'Account created successfully.',
            'user' => $this->accountRow($user),
        ], 201);
    }

    /**
     * Case/whitespace-insensitive uniqueness for a member name. Mirrors
     * AuthController's rule because the users table now carries a unique
     * index on LOWER(TRIM(name)); failing here yields a friendly 422 instead
     * of a raw constraint violation. `$ignoreId` lets an update keep its own
     * unchanged value.
     */
    private function uniqueNameRule(?int $ignoreId = null): \Closure
    {
        return function (string $attribute, mixed $value, \Closure $fail) use ($ignoreId): void {
            $needle = mb_strtolower(trim((string) $value));
            if ($needle === '') {
                return;
            }
            $query = User::whereRaw('LOWER(TRIM(name)) = ?', [$needle]);
            if ($ignoreId !== null) {
                $query->where('id', '!=', $ignoreId);
            }
            if ($query->exists()) {
                $fail('An account with this full name is already registered.');
            }
        };
    }

    /** Email counterpart of {@see uniqueNameRule()}. */
    private function uniqueEmailRule(?int $ignoreId = null): \Closure
    {
        return function (string $attribute, mixed $value, \Closure $fail) use ($ignoreId): void {
            $needle = strtolower(trim((string) $value));
            if ($needle === '') {
                return;
            }
            $query = User::whereRaw('LOWER(email) = ?', [$needle]);
            if ($ignoreId !== null) {
                $query->where('id', '!=', $ignoreId);
            }
            if ($query->exists()) {
                $fail('An account with this email is already registered.');
            }
        };
    }

    // ------------------------------------------------------------------
    // UPDATE — PATCH /admin/accounts/{id}
    // ------------------------------------------------------------------

    public function update(Request $request, $id)
    {
        $actor = $this->guard($request);

        /** @var User $user */
        $user = User::findOrFail($id);

        $validated = $request->validate([
            'name' => ['sometimes', 'string', 'max:255', $this->uniqueNameRule($user->id)],
            'email' => ['sometimes', 'email:rfc', 'max:255', $this->uniqueEmailRule($user->id)],
            'password' => ['nullable', 'string', 'min:8', 'max:128'],
            'role' => ['sometimes', Rule::in(User::ROLES)],
            'account_status' => ['sometimes', Rule::in(['active', 'suspended'])],
            'barangay_or_location' => ['nullable', 'string', \App\Support\Barangays::rule()],
            'purok_sitio' => ['nullable', 'string', 'max:255'],
            'student_status' => ['nullable', 'boolean'],
            'student_school' => ['nullable', 'string', 'max:255'],
        ]);

        // A regular admin may only manage member accounts.
        if ($user->role !== User::ROLE_USER && ! $actor->isSuperAdmin()) {
            abort(403, 'Only a Super Administrator can edit administrator accounts.');
        }

        // Role changes are super-admin-only and have guard rails.
        if (isset($validated['role']) && $validated['role'] !== $user->role) {
            if (! $actor->isSuperAdmin()) {
                throw ValidationException::withMessages([
                    'role' => 'Only a Super Administrator can change role assignments.',
                ]);
            }
            if ($user->id === $actor->id) {
                throw ValidationException::withMessages([
                    'role' => 'You cannot change your own role.',
                ]);
            }
            if ($user->isSuperAdmin() && ! $this->anotherSuperAdminExists($user->id)) {
                throw ValidationException::withMessages([
                    'role' => 'Cannot demote the last Super Administrator.',
                ]);
            }
        }

        // Suspension guard rails.
        if (($validated['account_status'] ?? null) === 'suspended' && $user->isAdmin()) {
            if (! $actor->isSuperAdmin()) {
                throw ValidationException::withMessages([
                    'account_status' => 'Only a Super Administrator can suspend an administrator.',
                ]);
            }
            if ($user->id === $actor->id) {
                throw ValidationException::withMessages([
                    'account_status' => 'You cannot suspend your own account.',
                ]);
            }
        }

        $changes = [];
        $fillableUpdates = collect($validated)
            ->except(['password', 'role', 'account_status'])
            ->filter(fn ($v, $k) => in_array($k, $user->getFillable(), true) && $v !== null)
            ->all();

        if ($fillableUpdates !== []) {
            $user->fill($fillableUpdates);
            $changes = array_keys($fillableUpdates);
        }

        // Keep the structured barangay column in lockstep with the legacy
        // combined column the admin console edits.
        if (array_key_exists('barangay_or_location', $fillableUpdates)) {
            $user->barangay = $fillableUpdates['barangay_or_location'];
        }

        if (! empty($validated['password'])) {
            $user->password = Hash::make($validated['password']);
            $changes[] = 'password';
            // A password reset revokes every existing session token.
            $user->tokens()->delete();
        }

        if (isset($validated['role']) && $validated['role'] !== $user->role) {
            $changes[] = 'role: '.$user->role.' → '.$validated['role'];
            $user->role = $validated['role'];
        }

        if (isset($validated['account_status']) && $validated['account_status'] !== $user->account_status) {
            $changes[] = 'account_status: '.$validated['account_status'];
            $user->account_status = $validated['account_status'];
            if ($validated['account_status'] === 'suspended') {
                $user->tokens()->delete();
            }
        }

        $user->save();

        AuditLog::record(
            $request,
            'Updated account '.$user->email.($changes ? ' ('.implode(', ', $changes).')' : ''),
            'user',
            $user->id,
        );

        return response()->json([
            'message' => 'Account updated successfully.',
            'user' => $this->accountRow($user->fresh()),
        ]);
    }

    // ------------------------------------------------------------------
    // ROLE — PATCH /admin/accounts/{id}/role (super.admin middleware)
    // ------------------------------------------------------------------

    public function updateRole(Request $request, $id)
    {
        $actor = $this->guard($request);

        $validated = $request->validate([
            'role' => ['required', Rule::in(User::ROLES)],
        ]);

        /** @var User $user */
        $user = User::findOrFail($id);

        // Single-account lockdown: no role changes that would create additional admins.
        if ($validated['role'] !== User::ROLE_USER) {
            throw ValidationException::withMessages([
                'role' => 'Role changes are restricted. Only the designated Super Admin may access the system.',
            ]);
        }
        if ($user->id === $actor->id) {
            throw ValidationException::withMessages(['role' => 'You cannot change your own role.']);
        }
        if ($user->isSuperAdmin() && $validated['role'] !== User::ROLE_SUPER_ADMIN
            && ! $this->anotherSuperAdminExists($user->id)) {
            throw ValidationException::withMessages(['role' => 'Cannot demote the last Super Administrator.']);
        }

        $previous = $user->role;
        $user->role = $validated['role'];
        $user->save();

        AuditLog::record(
            $request,
            'Changed role of '.$user->email.' from '.$previous.' to '.$user->role,
            'user',
            $user->id,
        );

        return response()->json([
            'message' => 'Role updated.',
            'user' => $this->accountRow($user->fresh()),
        ]);
    }

    // ------------------------------------------------------------------
    // DELETE — DELETE /admin/accounts/{id} (super.admin middleware)
    // ------------------------------------------------------------------

    public function destroy(Request $request, $id)
    {
        $actor = $this->guard($request);

        /** @var User $user */
        $user = User::findOrFail($id);

        if ($user->id === $actor->id) {
            abort(422, 'You cannot delete your own account.');
        }
        if ($user->isSuperAdmin() && ! $this->anotherSuperAdminExists($user->id)) {
            abort(422, 'Cannot delete the last Super Administrator.');
        }

        $email = $user->email;
        DB::transaction(function () use ($user) {
            $user->tokens()->delete(); // revoke every session first
            $user->delete();
        });

        AuditLog::record($request, 'Deleted account '.$email, 'user', (int) $id);

        return response()->json(['message' => 'Account deleted successfully.']);
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    /** Returns the acting admin; aborts 403 for non-admin callers. */
    private function guard(Request $request): User
    {
        $user = $request->user();
        abort_unless($user && $user->isAdmin(), 403, 'Unauthorized. Admin access required.');

        return $user;
    }

    private function anotherSuperAdminExists(int $exceptId): bool
    {
        return User::where('role', User::ROLE_SUPER_ADMIN)->where('id', '!=', $exceptId)->exists();
    }

    /** Row shape consumed by the AdminAccountsPage DataTable. */
    private function accountRow(User $u): array
    {
        return [
            'id' => $u->id,
            'name' => $u->name,
            'avatar_url' => $u->avatarUrl(),
            'email' => $u->email,
            'role' => $u->roleLabel(),
            'raw_role' => $u->role,
            'is_super_admin' => $u->isSuperAdmin(),
            'verification_status' => $u->verification_status ?? 'unverified',
            'account_status' => $u->account_status ?? 'active',
            'barangay_or_location' => $u->barangay_or_location,
            'student_status' => (bool) $u->student_status,
            'student_school' => $u->student_school,
            'resources_count' => $u->resources_count ?? 0,
            'date_registered' => $u->created_at?->format('M j, Y'),
            'created_at' => $u->created_at?->toISOString(),
        ];
    }
}
