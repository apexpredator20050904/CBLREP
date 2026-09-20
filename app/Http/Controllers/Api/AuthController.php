<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\AuditLog;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\Rules\Password;

class AuthController extends Controller
{
    /**
     * POST /api/register — community member sign-up (Register.jsx).
     */
    public function register(Request $request)
    {
        $validated = $request->validate([
            'fullName' => ['required', 'string', 'max:255'],
            'email' => ['required', 'string', 'email', 'max:255', 'unique:users,email'],
            'barangay' => ['required', 'string', 'max:255'],
            'password' => ['required', Password::min(8)],
        ]);

        $user = User::create([
            'name' => $validated['fullName'],
            'email' => strtolower($validated['email']),
            'barangay_or_location' => $validated['barangay'],
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
     * POST /api/admin-login — administrator sign-in (AdminLogin.jsx).
     * Fails unless the account holds the admin role; attempts are logged.
     */
    public function adminLogin(Request $request)
    {
        $credentials = $request->validate([
            'email' => ['required', 'email'],
            'password' => ['required', 'string'],
            'adminCode' => ['nullable', 'string'],
        ]);

        $user = User::where('email', strtolower($credentials['email']))->first();

        if (! $user || ! Hash::check($credentials['password'], $user->password) || ! $user->isAdmin()) {
            return response()->json(['message' => 'Invalid administrator credentials.'], 401);
        }

        if ($user->account_status === 'suspended') {
            return response()->json(['message' => 'This administrator account is suspended.'], 403);
        }

        AuditLog::record($request, 'Administrator signed in — '.$user->email, 'user', $user->id);

        return $this->tokenResponse($user, 'cblrep-admin');
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
            'barangay' => ['required', 'string', 'max:255'],
            'document_type' => ['required', 'string', 'max:100'],
            'document' => ['required', 'file', 'mimes:jpg,jpeg,png,pdf', 'max:5120'],
        ]);

        $user = $request->user();
        $path = $request->file('document')->store('verification-documents', 'public');
        $user->update([
            'barangay_or_location' => $validated['barangay'],
            'verification_status' => 'pending',
            'is_verified' => false,
            'verification_document_type' => $validated['document_type'],
            'verification_document_path' => $path,
        ]);

        return response()->json([
            'message' => 'Verification documents submitted for Trinidad review.',
            'user' => $user->fresh()->toFrontendArray(),
        ]);
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
