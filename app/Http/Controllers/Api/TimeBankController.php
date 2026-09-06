<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\TimebankService;
use App\Models\TimebankTransaction;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * Member-facing Time Bank API.
 *
 * Contract (consumed by src/lib/tbApi.js + src/timebank/*):
 *  GET    /api/timebank/services                     -> { services: [...] }
 *  GET    /api/timebank/service/{id}                 -> { service }
 *  POST   /api/timebank/services                     -> { message, service }
 *  GET    /api/timebank/transactions?email=          -> { transactions: [...] }
 *  POST   /api/timebank/transactions                 -> { transaction }
 *  PATCH  /api/timebank/transactions/{id}            -> { ok, awarded, transaction }
 *  GET    /api/timebank/balance?email=               -> { balance, earned, spent, pending }
 *  GET    /api/timebank/stats?email=                 -> { servicesOffered, ... }
 */
class TimeBankController extends Controller
{
    /**
     * Identity always comes from the Sanctum token; the email param the
     * frontend sends is only honored insofar as it matches the token user,
     * so one member can never read or mutate another member's ledger.
     */
    private function resolveActor(Request $request): User
    {
        return $request->user();
    }

    public function services(Request $request)
    {
        $services = TimebankService::query()
            ->orderByDesc('created_at')
            ->get()
            ->map(fn (TimebankService $service) => $service->toServiceArray())
            ->values();

        return response()->json(['services' => $services]);
    }

    public function show(Request $request, $id)
    {
        $service = TimebankService::findOrFail($id);

        return response()->json(['service' => $service->toServiceArray()]);
    }

    public function storeService(Request $request)
    {
        $validated = $request->validate([
            'title' => 'required|string|max:255',
            'description' => 'nullable|string|max:2000',
            'category' => 'nullable|string|max:255',
            'estimated_hours' => 'nullable|numeric|min:0.5|max:24',
            'location' => 'nullable|string|max:255',
            'availability' => 'nullable|string|max:255',
        ]);

        $me = $this->resolveActor($request);

        $service = TimebankService::create([
            'provider_email' => strtolower($me->email),
            'provider_name' => $me->name,
            'title' => $validated['title'],
            'description' => $validated['description'] ?? '',
            'category' => $validated['category'] ?? 'Skills',
            'estimated_hours' => $validated['estimated_hours'] ?? 1,
            'location' => trim((string) ($validated['location'] ?? '')) !== ''
                ? $validated['location']
                : ($me->barangay_or_location ?? ''),
            'availability' => $validated['availability'] ?? '',
            'status' => 'open',
        ]);

        return response()->json([
            'message' => 'Time-Bank service offered successfully.',
            'service' => $service->toServiceArray(),
        ], 201);
    }

    public function transactions(Request $request)
    {
        $me = $this->resolveActor($request);
        $email = strtolower($me->email);

        $transactions = TimebankTransaction::query()
            ->where(function ($q) use ($email) {
                $q->where('provider_email', $email)->orWhere('requester_email', $email);
            })
            ->orderByDesc('created_at')
            ->get()
            ->map(fn (TimebankTransaction $tx) => $tx->toTransactionArray())
            ->values();

        return response()->json(['transactions' => $transactions]);
    }

    public function requestService(Request $request)
    {
        $validated = $request->validate([
            'service_id' => 'required|integer|exists:timebank_services,id',
            'requested_hours' => 'nullable|numeric|min:1|max:24',
        ]);

        $me = $this->resolveActor($request);
        $service = TimebankService::findOrFail($validated['service_id']);

        if (strcasecmp((string) $service->provider_email, (string) $me->email) === 0) {
            return response()->json(['message' => 'You cannot request your own service.'], 422);
        }

        $hours = (float) ($validated['requested_hours'] ?: ($service->estimated_hours ?: 1));

        $transaction = TimebankTransaction::create([
            'service_id' => $service->id,
            'service_title' => $service->title,
            'provider_email' => strtolower((string) $service->provider_email),
            'provider_name' => $service->provider_name,
            'requester_email' => strtolower($me->email),
            'requester_name' => $me->name,
            'barangay' => $service->location,
            'requested_hours' => max(1, $hours),
            'hours_completed' => 0,
            'credits_transferred' => 0,
            'status' => TimebankTransaction::STATUS_PENDING,
            'confirmation_status' => 'pending',
        ]);

        return response()->json([
            'message' => 'Request sent to the provider.',
            'transaction' => $transaction->toTransactionArray(),
        ], 201);
    }

    public function balance(Request $request)
    {
        $me = $this->resolveActor($request);
        $email = strtolower($me->email);

        $earned = (float) TimebankTransaction::where('provider_email', $email)
            ->where('status', TimebankTransaction::STATUS_COMPLETED)
            ->sum('credits_transferred');

        $spent = (float) TimebankTransaction::where('requester_email', $email)
            ->where('status', TimebankTransaction::STATUS_COMPLETED)
            ->sum('credits_transferred');

        // Hours completed by me but not yet confirmed by the requester.
        $pending = (float) TimebankTransaction::where('provider_email', $email)
            ->where('status', TimebankTransaction::STATUS_AWAITING_CONFIRMATION)
            ->sum('hours_completed');

        return response()->json([
            'balance' => round((float) $me->time_bank_credits, 2),
            'earned' => round($earned, 2),
            'spent' => round($spent, 2),
            'pending' => round($pending, 2),
        ]);
    }

    public function stats(Request $request)
    {
        $me = $this->resolveActor($request);
        $email = strtolower($me->email);

        $myTx = fn () => TimebankTransaction::query()
            ->where(function ($q) use ($email) {
                $q->where('provider_email', $email)->orWhere('requester_email', $email);
            });

        return response()->json([
            'servicesOffered' => TimebankService::where('provider_email', $email)->count(),
            'servicesRequested' => TimebankTransaction::where('requester_email', $email)->count(),
            'openServices' => TimebankService::where('status', 'open')->count(),
            'active' => (clone $myTx())
                ->whereIn('status', [
                    TimebankTransaction::STATUS_ACCEPTED,
                    TimebankTransaction::STATUS_IN_PROGRESS,
                    TimebankTransaction::STATUS_AWAITING_CONFIRMATION,
                ])->count(),
            'completed' => (clone $myTx())
                ->where('status', TimebankTransaction::STATUS_COMPLETED)->count(),
        ]);
    }

    /**
     * State machine — Pending → Accepted → In Progress → Awaiting Confirmation → Completed
     * Credits move ONLY on requester "confirm" (mirrors the optimistic client fallback).
     */
    public function updateTransaction(Request $request, $id)
    {
        $validated = $request->validate([
            'action' => 'required|in:accept,in_progress,complete,confirm,cancel',
            'hours_completed' => 'nullable|numeric|min:0.5|max:24',
        ]);

        $action = $validated['action'];
        $me = $this->resolveActor($request);
        $email = strtolower($me->email);

        /** @var TimebankTransaction $transaction */
        $transaction = DB::transaction(function () use ($validated, $action, $email, $id) {

            // lockForUpdate prevents double-credit when two tabs confirm at once.
            $transaction = TimebankTransaction::whereKey($id)->lockForUpdate()->first();
            abort_unless($transaction !== null, 404, 'Transaction not found.');

            $isProvider = strcasecmp((string) $transaction->provider_email, $email) === 0;
            $isRequester = strcasecmp((string) $transaction->requester_email, $email) === 0;

            switch ($action) {
                case 'accept':
                    abort_unless($isProvider && $transaction->status === TimebankTransaction::STATUS_PENDING,
                        422, 'Only the provider can accept a pending request.');
                    $transaction->update(['status' => TimebankTransaction::STATUS_ACCEPTED]);
                    break;

                case 'in_progress':
                    abort_unless($isProvider && $transaction->status === TimebankTransaction::STATUS_ACCEPTED,
                        422, 'Accept the request before starting.');
                    $transaction->update(['status' => TimebankTransaction::STATUS_IN_PROGRESS]);
                    break;

                case 'complete':
                    abort_unless($isProvider && $transaction->status === TimebankTransaction::STATUS_IN_PROGRESS,
                        422, 'Start the service before marking it complete.');
                    $hours = (float) ($validated['hours_completed'] ?? $transaction->requested_hours);
                    $transaction->update([
                        'hours_completed' => $hours,
                        'status' => TimebankTransaction::STATUS_AWAITING_CONFIRMATION,
                    ]);
                    break;

                case 'confirm':
                    abort_unless($isRequester && $transaction->status === TimebankTransaction::STATUS_AWAITING_CONFIRMATION,
                        422, 'Only the requester can confirm completion.');

                    $this->transferCredits(
                        (string) $transaction->provider_email,
                        (string) $transaction->requester_email,
                        (float) $transaction->hours_completed,
                    );

                    $transaction->update([
                        'status' => TimebankTransaction::STATUS_COMPLETED,
                        'confirmation_status' => 'confirmed',
                        'credits_transferred' => $transaction->hours_completed,
                        'completed_at' => now(),
                    ]);
                    break;

                case 'cancel':
                    abort_unless(($isProvider || $isRequester)
                        && $transaction->status !== TimebankTransaction::STATUS_COMPLETED,
                        422, 'Completed transactions can no longer be cancelled.');
                    $transaction->update(['status' => TimebankTransaction::STATUS_CANCELLED]);
                    break;
            }

            return $transaction->fresh();
        });

        return response()->json([
            'ok' => true,
            'awarded' => $action === 'confirm',
            'transaction' => $transaction?->toTransactionArray(),
        ]);
    }

    /**
     * 1 verified hour = 1 credit. Requester pays first (never goes negative).
     */
    private function transferCredits(string $providerEmail, string $requesterEmail, float $hours): void
    {
        if ($hours <= 0) {
            abort(422, 'Completed hours must be greater than zero before confirming.');
        }

        $requester = User::whereRaw('LOWER(email) = ?', [strtolower($requesterEmail)])
            ->lockForUpdate()
            ->first();

        if ($requester && (float) $requester->time_bank_credits < $hours) {
            abort(422, 'Not enough Time Credits to confirm this exchange.');
        }

        User::whereRaw('LOWER(email) = ?', [strtolower($providerEmail)])
            ->increment('time_bank_credits', $hours);

        if ($requester) {
            $requester->decrement('time_bank_credits', $hours);
        }
    }
}
