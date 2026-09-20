<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Exchange;
use Illuminate\Http\Request;

class ExchangeController extends Controller
{
    public function index(Request $request)
    {
        $userId = $request->user()->id;

        $exchanges = Exchange::with(['resource', 'receiver', 'provider'])
            ->where(function ($query) use ($userId) {
                $query->where('receiver_id', $userId)
                    ->orWhere('provider_id', $userId);
            })
            ->latest()
            ->get()
            ->map(function (Exchange $item) use ($userId) {
                $otherUser = $item->receiver_id === $userId ? $item->provider : $item->receiver;

                return [
                    'id' => $item->id,
                    'type' => $item->frontendType(),
                    'item' => $item->resource?->title ?? 'Resource Exchange',
                    'withUser' => $otherUser?->name ?? 'Community Member',
                    'status' => $item->frontendStatus(),
                    'initiated' => $item->created_at?->format('M j, Y') ?? 'Today',
                    'dueCompleted' => $item->status === 'completed'
                        ? $item->updated_at?->format('M j, Y')
                        : ($item->scheduled_return_date?->format('M j, Y') ?? '—'),
                ];
            });

        $userExchanges = Exchange::query()->where(function ($query) use ($userId) {
            $query->where('receiver_id', $userId)->orWhere('provider_id', $userId);
        });

        return response()->json([
            'status' => 'success',
            'metrics' => [
                'timeBankCredits' => (float) $request->user()->time_bank_credits,
                'itemsLentOut' => (clone $userExchanges)->where('provider_id', $userId)
                    ->where('exchange_type', 'lending')
                    ->whereIn('status', ['pending', 'accepted'])
                    ->count(),
                'activeBarters' => (clone $userExchanges)->where('exchange_type', 'barter')
                    ->whereIn('status', ['pending', 'accepted'])
                    ->count(),
                'freecyclesGiven' => Exchange::where('provider_id', $userId)
                    ->where('exchange_type', 'freecycle')
                    ->count(),
            ],
            'data' => $exchanges->values(),
        ]);
    }

    /**
     * PATCH /api/exchanges/{id} — provider/receiver status actions from the
     * mobile My Exchanges screen (accept, complete, cancel).
     */
    public function update(Request $request, $id)
    {
        $validated = $request->validate([
            'status' => ['required', 'in:accepted,completed,cancelled'],
        ]);

        $userId = $request->user()->id;

        $exchange = Exchange::where(function ($query) use ($userId) {
            $query->where('provider_id', $userId)->orWhere('receiver_id', $userId);
        })->findOrFail($id);

        if ($validated['status'] === 'accepted' && $exchange->status !== 'pending') {
            return response()->json([
                'message' => 'Only pending exchanges can be accepted.',
            ], 422);
        }

        $exchange->update(['status' => $validated['status']]);

        $otherUser = $exchange->receiver_id === $userId ? $exchange->provider : $exchange->receiver;

        return response()->json([
            'message' => 'Exchange status updated.',
            'exchange' => [
                'id' => $exchange->id,
                'type' => $exchange->frontendType(),
                'item' => $exchange->resource?->title ?? 'Resource Exchange',
                'withUser' => $otherUser?->name ?? 'Community Member',
                'status' => $exchange->frontendStatus(),
                'initiated' => $exchange->created_at?->format('M j, Y') ?? 'Today',
            ],
        ]);
    }
}
