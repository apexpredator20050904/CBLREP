<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Controllers\Api\AdminTwoFactorController;
use App\Models\AdminTwoFactorChallenge;
use App\Models\AuditLog;
use App\Models\User;
use App\Notifications\ResetPasswordCode;
use App\Support\TotpService;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\Rules\Password;
use Throwable;

class AuthController extends Controller
{
    /** Minutes a mailed reset code stays valid. */
    private const RESET_CODE_TTL = 15;

    /**
     * POST /api/register — community member sign-up (Register.jsx).
     */
    public function register(Request $request)
    {
        $validator = \Illuminate\Support\Facades\Validator::make($request->all(), [
            // Case-insensitive uniqueness on BOTH identity fields, so
            // "John Cruz"/john@x and "john cruz"/JOHN@X can never coexist as
            // two accounts (an identity-mismatch / impersonation vector).
            // The comparison is delegated to Rule::uniqueWithNormalisation
            // below, which lowercases both sides via a raw expression.
            'fullName' => ['required', 'string', 'max:255', $this->uniqueNameRule()],
            'email' => ['required', 'string', 'email', 'max:255', $this->uniqueEmailRule()],
            'barangay' => ['required', 'string', \App\Support\Barangays::rule()],
            'purok_sitio' => ['required', 'string', 'max:60', \App\Support\Puroks::rule()],
            'password' => ['required', Password::min(8)],
        ], [
            'fullName.unique' => 'An account with this full name is already registered.',
            'email.unique' => 'An account with this email is already registered.',
        ]);

        if ($validator->fails()) {
            // Return the field-specific reason directly as the top-level
            // message so the mobile app and React console show a friendly,
            // field-accurate alert instead of a generic summary.
            return response()->json([
                'message' => $validator->errors()->first(),
                'errors' => $validator->errors(),
            ], 422);
        }
        $validated = $validator->validated();

        $user = User::create([
            'name' => $validated['fullName'],
            'email' => strtolower($validated['email']),
            'barangay_or_location' => $validated['barangay'],
            'barangay' => $validated['barangay'],
            'purok_sitio' => $validated['purok_sitio'] ?? null,
            'password' => $validated['password'], // hashed via model cast
            'role' => 'user',
            'is_verified' => false,
        ]);

        return response()->json([
            'message' => 'Account created successfully. You can now sign in.',
            'user' => $user->toFrontendArray(),
        ], 201);
    }

    /**
     * Case- and whitespace-insensitive uniqueness rule for a user's full name.
     *
     * The default `unique:users,name` only catches an exact byte match and
     * leans on the table collation to ignore case. Comparing LOWER(TRIM(...))
     * on both sides makes "John Cruz" and "  john cruz " collide regardless of
     * collation, so two members can never share an identity name.
     */
    private function uniqueNameRule(): \Closure
    {
        return function (string $attribute, mixed $value, \Closure $fail): void {
            $needle = mb_strtolower(trim((string) $value));
            if ($needle === '') {
                return;
            }
            $exists = User::whereRaw('LOWER(TRIM(name)) = ?', [$needle])->exists();
            if ($exists) {
                $fail('An account with this full name is already registered.');
            }
        };
    }

    /** Email counterpart of {@see uniqueNameRule()} — normalised, case-folded. */
    private function uniqueEmailRule(): \Closure
    {
        return function (string $attribute, mixed $value, \Closure $fail): void {
            $needle = strtolower(trim((string) $value));
            if ($needle === '') {
                return;
            }
            $exists = User::whereRaw('LOWER(email) = ?', [$needle])->exists();
            if ($exists) {
                $fail('An account with this email is already registered.');
            }
        };
    }

    /**
     * POST /api/login — member sign-in (Login.jsx). Returns a Sanctum token.
     */
    public function login(Request $request)
    {
        $credentials = $request->validate([
            'email' => ['required', 'email'],
            'password' => ['required', 'string'],
        ]);

        $user = User::where('email', strtolower($credentials['email']))->first();

        if (! $user || ! Hash::check($credentials['password'], $user->password)) {
            return response()->json(['message' => 'Invalid email or password.'], 401);
        }

        if ($user->account_status === 'suspended') {
            return response()->json([
                'message' => 'Your account has been suspended. Please contact an administrator.',
            ], 403);
        }

        return $this->tokenResponse($user, 'cblrep-member');
    }

    /**
     * POST /api/admin-login — administrator sign-in, stage 1 of 2.
     *
     * Validates the primary credentials only, then branches:
     *
     *   - account enrolled   → `requires_2fa` + challenge token; the session
     *     is minted by AdminTwoFactorController::verify() once the
     *     authenticator-app code comes back.
     *   - account not yet enrolled → `requires_enrolment` + a ready-to-render
     *     QR payload (the login-time enrolment step); the session is minted
     *     by enrolConfirm() once a scanned code proves the QR was imported,
     *     or by enrolSkip() if the operator declines for now.
     *
     * Neither branch returns a Sanctum token here — that is what keeps the
     * second factor (and the enrolment step) load-bearing rather than
     * decorative.
     *
     * Every attempt is written to the audit log, including the failures.
     */
    public function adminLogin(Request $request)
    {
        $credentials = $request->validate([
            'email' => ['required', 'email'],
            'password' => ['required', 'string'],
        ]);

        $user = User::where('email', strtolower($credentials['email']))->first();

        if (! $user || ! Hash::check($credentials['password'], $user->password) || ! $user->isAdmin()) {
            AuditLog::record(
                $request,
                'Failed administrator sign-in — '.$credentials['email'],
                'user',
                $user?->id,
            );

            return response()->json(['message' => 'Invalid administrator credentials.'], 401);
        }

        if ($user->account_status === 'suspended') {
            return response()->json(['message' => 'This administrator account is suspended.'], 403);
        }

        // ── Stage 2: authenticator-app second factor ──────────────────
        //
        // `hasEnrolledTwoFactor()` rather than the raw column: a row where the
        // flag is set but the secret or confirmation is missing is a
        // half-finished enrolment, and treating that as "2FA on" would lock
        // the admin out with no way back through the UI.
        if ($user->hasEnrolledTwoFactor()) {
            $issued = $this->twoFactor()->issueChallenge($user, $request);

            // Return the QR code so a browser authenticator extension can
            // scan it and import the TOTP secret. The secret is already
            // enrolled on the account — this is purely a convenience step
            // so the extension can generate codes without manual entry.
            $totp = app(TotpService::class);
            $qrCode = $totp->qrCodeDataUri(
                $totp->provisioningUri($user->two_factor_secret, $user->email)
            );

            AuditLog::record(
                $request,
                'Administrator cleared primary credentials, 2FA issued — '.$user->email,
                'user',
                $user->id,
            );

            return response()->json([
                'requires_2fa' => true,
                'challenge_token' => $issued,
                'qr_code' => $qrCode,
                'secret' => $user->two_factor_secret,
                'issuer' => TotpService::ISSUER,
                'expires_in' => AdminTwoFactorChallenge::TTL_MINUTES * 60,
                'message' => 'Scan the QR code with your authenticator extension, then enter the 6-digit code.',
            ]);
        }

        // ── First sign-in: no authenticator enrolled yet ──────────────
        //
        // The QR step lives HERE, in the login flow: the password has
        // already been proven, so the browser receives a challenge-bound
        // enrolment payload (QR + manual key) instead of a session. Until
        // enrolConfirm() sees a matching code — or enrolSkip() is called —
        // no Sanctum token exists, which is what makes the enrolment step
        // something the operator actually completes rather than a detour
        // they can ignore.
        $enrolment = $this->twoFactor()->startLoginEnrolment($user, $request);

        AuditLog::record(
            $request,
            'Administrator cleared primary credentials, 2FA enrolment offered — '.$user->email,
            'user',
            $user->id,
        );

        return response()->json([
            'requires_enrolment' => true,
            'enrol_token' => $enrolment['enrol_token'],
            'qr_code' => $enrolment['qr_code'],
            'secret' => $enrolment['secret'],
            'issuer' => $enrolment['issuer'],
            'expires_in' => $enrolment['expires_in'],
            'message' => 'Scan the QR code with your authenticator app to finish signing in.',
        ]);
    }

    /**
     * Shared 2FA controller instance.
     *
     * Resolved from the container rather than instantiated with `new`:
     * AdminTwoFactorController takes a TotpService, so `new AdminTwoFactorController`
     * would throw ArgumentCountError and 500 every 2FA sign-in. The container
     * injects the service (and any future dependencies) for us.
     */
    private function twoFactor(): AdminTwoFactorController
    {
        return app(AdminTwoFactorController::class);
    }

    /**
     * GET /api/user — current profile for the Bearer token (Dashboard.jsx).
     */
    public function me(Request $request)
    {
        return response()->json($request->user()->toFrontendArray());
    }

    /**
     * POST /api/logout — revoke the token used for this request.
     */
    public function logout(Request $request)
    {
        $request->user()->currentAccessToken()->delete();

        return response()->json(['message' => 'Signed out successfully.']);
    }

    public function submitVerification(Request $request)
    {
        $validated = $request->validate([
            'barangay' => ['required', 'string', \App\Support\Barangays::rule()],
            'purok_sitio' => ['required', 'string', 'max:60', \App\Support\Puroks::rule()],
            'document_type' => ['required', 'string', 'max:100'],
            'document' => ['required', 'file', 'mimes:jpg,jpeg,png,pdf', 'max:5120'],
        ]);

        $user = $request->user();
        $path = $request->file('document')->store('verification-documents', 'public');
        $user->update([
            'barangay_or_location' => $validated['barangay'],
            'barangay' => $validated['barangay'],
            'purok_sitio' => $validated['purok_sitio'],
            'verification_status' => 'pending',
            'is_verified' => false,
            'verification_document_type' => $validated['document_type'],
            'verification_document_path' => $path,
            // Stamp the review clock and clear any previous rejection note so a
            // re-submission starts the queue fresh.
            'verification_submitted_at' => now(),
            'verification_note' => null,
        ]);

        return response()->json([
            'message' => 'Verification documents submitted for Trinidad review.',
            'user' => $user->fresh()->toFrontendArray(),
        ]);
    }

    public function verificationStatus(Request $request)
    {
        $user = $request->user();
        return response()->json([
            'status' => $user->verification_status,
            'status_label' => $user->verificationStatusLabel(),
            'is_verified' => (bool) $user->is_verified,
            'barangay' => $user->barangay_or_location,
            'purok_sitio' => $user->purok_sitio,
            'document_type' => $user->verification_document_type,
            'note' => $user->verification_note,
            'submitted_at' => $user->verification_submitted_at?->toISOString(),
        ]);
    }

    /**
     * PATCH /api/user — update the signed-in member's own profile.
     * Only an explicit whitelist of columns may change; role and is_verified
     * stay under administrator control.
     */
    public function updateProfile(Request $request)
    {
        $userId = $request->user()->id;
        $validated = $request->validate([
            'name' => ['sometimes', 'string', 'max:255', $this->uniqueNameRule($userId)],
            'fullName' => ['sometimes', 'string', 'max:255', $this->uniqueNameRule($userId)],
            'barangay' => ['sometimes', 'string', \App\Support\Barangays::rule()],
            'barangay_or_location' => ['sometimes', 'string', \App\Support\Barangays::rule()],
            'purok_sitio' => ['sometimes', 'nullable', 'string', 'max:60', \App\Support\Puroks::rule()],
            'current_password' => ['sometimes', 'nullable', 'string'],
            'password' => ['sometimes', 'nullable', 'string', Password::min(8)],
        ]);

        $user = $request->user();
        $payload = [];

        $name = $validated['name'] ?? $validated['fullName'] ?? null;
        if (is_string($name) && trim($name) !== '') {
            $payload['name'] = trim($name);
        }

        $barangay = $validated['barangay'] ?? $validated['barangay_or_location'] ?? null;
        if (is_string($barangay) && trim($barangay) !== '') {
            $payload['barangay_or_location'] = trim($barangay);
            $payload['barangay'] = trim($barangay);
        }

        if (! empty($validated['purok_sitio'])) {
            $payload['purok_sitio'] = trim($validated['purok_sitio']);
        }

        if (! empty($validated['password'])) {
            if (empty($validated['current_password'])
                || ! Hash::check($validated['current_password'], $user->password)) {
                return response()->json(['message' => 'Your current password is incorrect.'], 422);
            }
            $payload['password'] = $validated['password'];

            // Keep this session, drop every other device.
            $user->tokens()->where('id', '!=', $user->currentAccessToken()?->id)->delete();
        }

        if ($payload === []) {
            return response()->json(['message' => 'Nothing to update.'], 422);
        }

        $user->update($payload);

        return response()->json([
            'message' => 'Profile updated successfully.',
            'user' => $user->fresh()->toFrontendArray(),
        ]);
    }

    /**
     * POST /api/forgot-password — mail a single-use 6-digit reset code.
     *
     * Always answers with the same wording so the endpoint cannot be used to
     * enumerate which e-mail addresses belong to members.
     */
    public function forgotPassword(Request $request)
    {
        $validated = $request->validate([
            'email' => ['required', 'string', 'email', 'max:255'],
        ]);

        $email = strtolower(trim($validated['email']));
        $generic = ['message' => 'If that e-mail belongs to a member, a reset code is on its way.'];

        $user = User::where('email', $email)->first();

        if (! $user || $user->account_status === 'suspended') {
            return response()->json($generic);
        }

        $code = str_pad((string) random_int(0, 999999), 6, '0', STR_PAD_LEFT);

        DB::table('password_reset_tokens')->updateOrInsert(
            ['email' => $email],
            ['token' => Hash::make($code), 'created_at' => now()],
        );

        try {
            $user->notify(new ResetPasswordCode($code, $user->name, self::RESET_CODE_TTL));
        } catch (Throwable $exception) {
            report($exception);

            return response()->json([
                'message' => 'We could not send the reset e-mail right now. Please try again shortly.',
            ], 503);
        }

        AuditLog::record($request, 'Password reset code requested — '.$email, 'user', $user->id);

        return response()->json($generic + $this->localDebugPayload($user, $code));
    }

    /**
     * POST /api/reset-password — redeem the mailed code and set a new password.
     */
    public function resetPassword(Request $request)
    {
        $validated = $request->validate([
            'email' => ['required', 'string', 'email', 'max:255'],
            'code' => ['required', 'string', 'max:12'],
            'password' => ['required', 'string', 'confirmed', Password::min(8)],
        ]);

        $email = strtolower(trim($validated['email']));
        $row = DB::table('password_reset_tokens')->where('email', $email)->first();

        // One message for "never requested" and "wrong code" so the endpoint
        // cannot be used to probe which codes exist.
        $invalid = ['message' => 'That reset code is invalid, expired or already used.'];

        if (! $row || ! Hash::check($validated['code'], (string) $row->token)) {
            AuditLog::record($request, 'Password reset rejected — '.$email, 'user', null);

            return response()->json($invalid, 422);
        }

        if (now()->greaterThan(Carbon::parse($row->created_at)->addMinutes(self::RESET_CODE_TTL))) {
            DB::table('password_reset_tokens')->where('email', $email)->delete();

            return response()->json($invalid, 422);
        }

        $user = User::where('email', $email)->first();

        if (! $user) {
            DB::table('password_reset_tokens')->where('email', $email)->delete();

            return response()->json($invalid, 422);
        }

        $user->update(['password' => $validated['password']]); // hashed by the model cast

        // Single-use code, and every existing device session is revoked.
        DB::table('password_reset_tokens')->where('email', $email)->delete();
        $user->tokens()->delete();

        AuditLog::record($request, 'Password reset completed — '.$email, 'user', $user->id);

        return response()->json([
            'message' => 'Password updated. Please sign in with your new password.',
        ]);
    }

    /**
     * Local-only convenience: with MAIL_MAILER=log there is no inbox to read,
     * so a developer build is handed the code inline. Production runs with
     * APP_ENV=production + APP_DEBUG=false, where this always returns [].
     */
    private function localDebugPayload(User $user, string $code): array
    {
        if (! app()->environment('local') || ! config('app.debug')) {
            return [];
        }

        return ['dev_code' => $code, 'dev_email' => $user->email];
    }

    private function tokenResponse(User $user, string $device)
    {
        return response()->json([
            'access_token' => $user->createToken($device)->plainTextToken,
            'token_type' => 'Bearer',
            'user' => $user->toFrontendArray(),
        ]);
    }
}
