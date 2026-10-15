<?php

namespace App\Http\Middleware;

use App\Models\AuditLog;
use App\Models\User;
use Closure;
use Illuminate\Http\Request;
use Laravel\Sanctum\PersonalAccessToken;
use Symfony\Component\HttpFoundation\Response;

/**
 * RBAC middleware — ensures only the designated Super Administrator reaches
 * the /api/admin/* route group.
 *
 * Single-account lockdown: only the account matching SUPER_ADMIN_EMAIL
 * may authenticate into the admin panel. All other accounts — including
 * other super_admin or admin role holders — are rejected with 403.
 *
 * Second check — the token must have completed 2FA:
 *
 * An administrator who has enrolled in TOTP must reach the console only via
 * a token minted by AdminTwoFactorController::verify(), which names the token
 * 'cblrep-admin-2fa'. Enforcing that *here* rather than at token minting is
 * deliberate: the member endpoint POST /api/login is a second, legitimate
 * path to a Sanctum token, and it does not run the 2FA dance. A guard that
 * only checked the role would let any enrolled admin walk in through that
 * door and render the second factor decorative. The privilege boundary is the
 * right place to bind "role" to "proved the second factor", because it holds
 * no matter which endpoint produced the token.
 */
class AdminMiddleware
{
    /** Token name minted only after a verified TOTP or recovery code. */
    public const TWO_FACTOR_TOKEN = 'cblrep-admin-2fa';

    /**
     * The single authorised Super Administrator email.
     *
     * Only this account may access the admin panel. No other accounts
     * may be created or authenticated.
     */
    public const SUPER_ADMIN_EMAIL = 'admin@cblrep.ph';

    public function handle(Request $request, Closure $next): Response
    {
        $user = $request->user();

        // Single-account lockdown: only the designated Super Admin may proceed.
        if (! $user || $user->email !== self::SUPER_ADMIN_EMAIL) {
            return response()->json([
                'message' => 'Unauthorized. Only the designated Super Administrator may access this area.',
            ], 403);
        }

        // 2FA enforcement: token must have completed the second factor.
        if ($user->hasEnrolledTwoFactor() && ! $this->tokenPassedTwoFactor($user)) {
            AuditLog::record(
                $request,
                'Blocked admin API access — token never completed 2FA ('.$user->email.')',
                'user',
                $user->id,
            );

            return response()->json([
                'message' => 'Two-factor verification is required. Please sign in again.',
            ], 403);
        }

        return $next($request);
    }

    /**
     * True only when the bearer token in play is one issued by the 2FA
     * verification endpoint.
     *
     * A missing token model (stateful cookie auth, or a guard that has not
     * resolved a PersonalAccessToken) is treated as NOT verified: this API is
     * bearer-only, so anything else here is unexpected, and the safe default
     * is to refuse rather than to assume the factor was satisfied.
     */
    private function tokenPassedTwoFactor(User $user): bool
    {
        $token = $user->currentAccessToken();

        return $token instanceof PersonalAccessToken
            && $token->name === self::TWO_FACTOR_TOKEN;
    }
}
