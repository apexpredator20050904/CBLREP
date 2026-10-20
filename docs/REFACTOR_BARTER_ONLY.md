# CBLREP — Scope-Narrowing Refactor Guide

## Removing Freecycling & Temporary Lending → Direct Bartering Only

**Project:** Community-Based Local Resources Exchange Portal (CBLREP)
**Location:** Trinidad, Bohol · **Stack:** Laravel 11 API + React/Vite admin + Flutter mobile

A complete, line-referenced specification. Every path and line number was read from
the live repository on 29 Sep 2026, so the steps apply in order without re-discovery.

---

## 0. Executive Summary

| Layer | Action | Risk |
|---|---|---|
| Database | 1 migration: purge 1 legacy row, drop 3 columns, add 2 barter columns | **High** — irreversible, see §1.1 |
| Backend | 6 files edited, status machine simplified to 5 states | Medium |
| Flutter | 9 files edited, 2 UI flows collapsed to one barter form | Medium |
| React | 1 file edited | Low |
| Verification | 8 checks, all automated | — |

**Key architectural decision.** A barter is inherently *two-sided* — both parties
give something. Your current schema records only what the requester **wants**
(`resource_id`). This guide adds `offered_resource_id` + `offered_item` so a trade
provably has goods on both sides.

That column is the strongest defense artifact in the whole refactor: it makes
"zero-cost gifting" *structurally impossible* rather than merely hidden behind a
dropdown. A panel member who asks "can someone give an item away for free?" gets
"no — the form requires what you're offering in return, and the database rejects
null."

---

## 1. Database & Backend (Laravel)

### 1.1 ⚠️ Read before running anything

Your live database contains **1 exchange row that this migration deletes**:

```text
id=1 | exchange_type=lending | status=accepted | scheduled_return_date=2026-09-30
```

`resources.exchange_type` holds only `'Lend'` across all rows.

**Back up first — a dropped column cannot be restored:**

```bash
cd backend
mysqldump -u root -p community-based-portal > ~/cblrep_backup_$(date +%F).sql
php artisan migrate:status
```

**Decision required.** That row is demo data. Either:

1. **Delete it (recommended)** — a clean slate is easier to defend than a
   pre-scope-change artifact that would raise "does this still work?" questions; or
2. **Convert it** — swap the `delete()` below for an `update()` to `barter`.

Everything below assumes **Option 1**.

### 1.2 The migration

```bash
php artisan make:migration narrow_exchanges_to_barter_only
```

```php
<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Narrows CBLREP to Direct Bartering only.
 *
 * Freecycling (one-way gifting) and temporary lending (time-boxed loans) are
 * retired. A barter is a two-sided swap, so this migration:
 *
 *   1. Purges historical non-barter exchanges.
 *   2. Drops the lending timeline columns (scheduled_return_date, return_date).
 *   3. Adds offered_resource_id + offered_item — what the requester gives.
 *   4. Drops resources.exchange_type, the column that let a listing declare
 *      itself giftable or lendable. Every transaction is a barter by schema.
 */
return new class extends Migration
{
    public function up(): void
    {
        // 1. Purge retired exchange types.
        DB::table('exchanges')
            ->whereIn('exchange_type', ['freecycle', 'lending', 'time_banking'])
            ->delete();

        // 2. Lending timeline — meaningless without loans.
        Schema::table('exchanges', function (Blueprint $table) {
            $table->dropColumn(['scheduled_return_date', 'return_date']);
        });

        // 3. The giving side of the trade.
        Schema::table('exchanges', function (Blueprint $table) {
            $table->foreignId('offered_resource_id')
                ->nullable()->after('resource_id')
                ->constrained('resources')->nullOnDelete();

            $table->string('offered_item', 160)->nullable()->after('offered_resource_id');
        });

        // Backfill so surviving rows are never null.
        DB::table('exchanges')->whereNull('offered_resource_id')
            ->update(['offered_resource_id' => DB::raw('resource_id')]);
        DB::table('exchanges')->whereNull('offered_item')
            ->update(['offered_item' => 'Item to be agreed with the owner']);

        // 4. Retire the per-listing mode. Only `type` (offer/need) remains.
        if (Schema::hasColumn('resources', 'exchange_type')) {
            Schema::table('resources', function (Blueprint $table) {
                $table->dropColumn('exchange_type');
            });
        }
    }

    public function down(): void
    {
        if (! Schema::hasColumn('resources', 'exchange_type')) {
            Schema::table('resources', function (Blueprint $table) {
                $table->string('exchange_type')->default('Lend')->after('type');
            });
        }

        Schema::table('exchanges', function (Blueprint $table) {
            $table->date('scheduled_return_date')->nullable();
            $table->date('return_date')->nullable();
        });

        // A barter with both sides stated cannot be reversed into a loan, so
        // down() restores structure only. Note this in your defense docs.
    }
};
```

**Verify reversibility:**

```bash
php artisan migrate
php artisan migrate:rollback && php artisan migrate
```

> **Note on the original migrations.** `scheduled_return_date` is declared in
> `2026_08_24_155400_create_exchanges_table.php:26`; `return_date` is added by a
> *separate* file, `2026_09_20_000018_add_return_date_to_exchanges.php`. Your new
> migration must drop **both** — the schema builder above does it in one call.
> Leave both originals untouched; they are already in the migration history.



### 1.3 `app/Models/Exchange.php` — rewrite the type + status layer

The model is the single place that defines what a valid trade looks like, so
narrowing it here makes every other layer inherit the constraint.

```php
<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Exchange extends Model
{
    /**
     * The only transaction type CBLREP supports.
     *
     * One-sided gifting (freecycling) and time-boxed loans (lending) were
     * retired in the bartering-only refactor. Every row is a two-sided swap.
     */
    public const TYPE_BARTER = 'barter';

    /**
     * Legal barter status flow.
     *
     *   pending ──▶ accepted ──▶ completed
     *      │            │
     *      └────────────┴──▶ rejected
     *
     * `rejected` replaces the old `cancelled`/`returned` vocabulary: a barter
     * is never "returned" because nothing is ever lent out.
     */
    public const STATUSES = ['pending', 'accepted', 'rejected', 'completed'];

    protected $fillable = [
        'resource_id',          // what the requester wants
        'offered_resource_id',  // what the requester gives
        'offered_item',         // free-text fallback for skills
        'provider_id',          // the listing owner
        'receiver_id',          // the proposer
        'status',
    ];

    // ------------------------------------------------------------------
    // Relations
    // ------------------------------------------------------------------

    public function resource()
    {
        return $this->belongsTo(Resource::class);
    }

    /** The listing the proposer puts up in return. */
    public function offeredResource()
    {
        return $this->belongsTo(Resource::class, 'offered_resource_id');
    }

    public function provider()
    {
        return $this->belongsTo(User::class, 'provider_id');
    }

    public function receiver()
    {
        return $this->belongsTo(User::class, 'receiver_id');
    }

    // ------------------------------------------------------------------
    // Domain rules
    // ------------------------------------------------------------------

    public function typeLabel(): string
    {
        return 'Direct Bartering';
    }

    public function frontendStatus(): string
    {
        return match ($this->status) {
            'pending' => 'Pending',
            'accepted' => 'Accepted',
            'rejected' => 'Rejected',
            'completed' => 'Completed',
            default => ucfirst((string) $this->status),
        };
    }

    /**
     * The single source of truth for legal transitions.
     *
     * Both the mobile PATCH endpoint and the admin moderation endpoint call
     * this, so an invalid jump (e.g. pending → completed) is rejected no
     * matter which client asks.
     */
    public function canTransitionTo(string $status): bool
    {
        return in_array($status, self::TRANSITIONS[$this->status] ?? [], true);
    }

    /**
     * Adjacency list for the status machine above. Terminal states
     * (`completed`, `rejected`) map to an empty list, which makes them
     * absorbing by construction — a row can never be silently reopened.
     */
    public const TRANSITIONS = [
        'pending'  => ['accepted', 'rejected'],
        'accepted' => ['completed', 'rejected'],
        'rejected' => [],
        'completed' => [],
    ];

    /** Statuses no further action is possible from — used to grey out buttons. */
    public function isSettled(): bool
    {
        return in_array($this->status, ['completed', 'rejected'], true);
    }
}
```

### 1.4 `app/Http/Controllers/Api/ExchangeController.php`

Four methods change. `store()` gains the two-sided requirement; `update()` delegates
to the model's state machine.

**`store()` — lines 14-45 become:**

```php
    public function store(Request $request)
    {
        $validated = $request->validate([
            'resource_id' => ['required', 'integer', 'exists:resources,id'],
            // What the proposer puts up in return. Exactly one of the two
            // must be present — this is what makes a free gift impossible.
            'offered_resource_id' => ['nullable', 'integer', 'exists:resources,id', 'different:resource_id'],
            'offered_item' => ['nullable', 'string', 'max:160'],
            'notes' => ['nullable', 'string', 'max:500'],
        ]);

        // A barter must be two-sided. Enforced here, not just in the UI.
        if (empty($validated['offered_resource_id'])
            && blank($validated['offered_item'] ?? null)) {
            return response()->json([
                'message' => 'A barter requires something in return. Choose a listing to offer, or describe the item or skill you are trading.',
                'errors' => ['offered_item' => ['An offer in return is required for a direct barter.']],
            ], 422);
        }

        $resource = Resource::where('is_active', true)->findOrFail($validated['resource_id']);
        abort_if($resource->user_id === $request->user()->id, 422, 'You cannot request your own listing.');

        $exchange = DB::transaction(function () use ($validated, $resource, $request) {
            $exchange = Exchange::create([
                'resource_id' => $resource->id,
                'offered_resource_id' => $validated['offered_resource_id'] ?? null,
                'offered_item' => $validated['offered_item'] ?? null,
                'provider_id' => $resource->user_id,
                'receiver_id' => $request->user()->id,
                'exchange_type' => Exchange::TYPE_BARTER,
                'status' => 'pending',
            ]);

            MemberNotification::create([
                'user_id' => $resource->user_id,
                'type' => 'barter_proposal',
                'title' => 'New barter proposal',
                'body' => $request->user()->name.' offered to trade for “'.$resource->title.'”.',
                'data' => ['exchange_id' => $exchange->id, 'resource_id' => $resource->id],
            ]);

            return $exchange;
        });

        return response()->json([
            'message' => 'Barter proposal sent.',
            'exchange' => $exchange->load(['resource', 'offeredResource']),
        ], 201);
    }
```

**`index()` — line 51** eager-load the new relation:

```php
        $exchanges = Exchange::with(['resource', 'offeredResource', 'receiver', 'provider'])
```

…and inside the `map()` closure, replace the `dueCompleted` ternary (lines 68-70)
with fields describing the trade itself:

```php
                    'offering' => $item->offeredItem
                        ?: $item->offeredResource?->title
                        ?: 'Item or skill',
                    'wanted' => $item->resource?->title ?? 'Listing',
                    'settled' => $item->status === 'completed'
                        ? $item->updated_at?->format('M j, Y')
                        : null,
```

**`update()` — lines 100-133 become.** The status list drops `cancelled` (the
model calls it `rejected`) and the authority check flips: only the listing owner
may accept, because a proposer cannot accept their own offer.

```php
    /**
     * PATCH /api/exchanges/{id} — status actions from the mobile My Exchanges
     * screen. Only the listing owner may accept or reject a proposal; either
     * party may mark it completed once the goods have changed hands.
     */
    public function update(Request $request, $id)
    {
        $validated = $request->validate([
            'status' => ['required', 'in:accepted,rejected,completed'],
        ]);

        $userId = $request->user()->id;

        $exchange = Exchange::with('provider')->where(function ($query) use ($userId) {
            $query->where('provider_id', $userId)->orWhere('receiver_id', $userId);
        })->findOrFail($id);

        // Accepting or rejecting is the owner's call — otherwise a proposer
        // could accept their own trade and mark it settled unilaterally.
        if (in_array($validated['status'], ['accepted', 'rejected'], true)
            && $exchange->provider_id !== $userId) {
            return response()->json([
                'message' => 'Only the listing owner can accept or reject this proposal.',
            ], 403);
        }

        if (! $exchange->canTransitionTo($validated['status'])) {
            return response()->json([
                'message' => "A {$exchange->status} barter cannot be marked {$validated['status']}.",
            ], 422);
        }

        $exchange->update(['status' => $validated['status']]);

        $otherUser = $exchange->receiver_id === $userId ? $exchange->provider : $exchange->receiver;

        return response()->json([
            'message' => 'Barter status updated.',
            'exchange' => [
                'id' => $exchange->id,
                'type' => $exchange->typeLabel(),
                'item' => $exchange->resource?->title ?? 'Resource Exchange',
                'offering' => $exchange->offeredItem ?: $exchange->offeredResource?->title ?: 'Item or skill',
                'withUser' => $otherUser?->name ?? 'Community Member',
                'status' => $exchange->frontendStatus(),
                'initiated' => $exchange->created_at?->format('M j, Y') ?? 'Today',
            ],
        ]);
    }
```

**`updateStatus()` — delete lines 135-170 entirely.** It is the lending state
machine: six statuses including `active`/`returned`, a `return_date` column, and
a lending-only guard on line 153. `update()` above replaces it. Then remove the
route that pointed at it:

```php
// routes/api.php — delete this line
Route::put('/exchanges/{id}/status', [ExchangeController::class, 'updateStatus']);
```

Keep `PATCH /exchanges/{id}`. The Flutter app's 404-fallback in `api_service.dart`
tries `PUT .../status` second; with that route gone the fallback is dead code,
so §2.2 removes it too.

---

### 1.5 `AdminPortalController.php` — analytics and filters

Five edits, all deletions. Bartering already has its own column, so nothing new
is needed.

```php
// 1. Line ~470 — drop the retired type from the filter map:
//    'timebank' => 'time_banking',   (already gone in the time-bank pass)
//    'lending'  => 'lending',        DELETE this line

// 2. Line ~522 — the credits column is gone; report the two trade sides:
            'offering' => $e->offered_item ?: $e->offeredResource?->title ?: '—',
            'wanted'   => $e->resource?->title ?? '—',

// 3. Line ~610 — one exchange type, one count:
            'barter' => (int) ($typeCounts['barter'] ?? 0),
            'completed' => (clone $exchanges)->where('status', 'completed')->count(),

// 4. Status badge map — replace the 6-state lookup with 4:
            'Pending'   => 'amber',
            'Accepted'  => 'blue',
            'Rejected'  => 'rose',
            'Completed' => 'emerald',

// 5. Any ->whereIn('status', [...]) counts for active/returned collapse to:
//    ->where('status', 'accepted')
```

### 1.6 `AnalyticsController.php` — the two lines I flagged earlier

This is the file I wrote for the CSV/PDF export, and it still reports the
retired models. Fix the `exchanges` label map:

```php
// BEFORE
'exchanges' => [
    'freecycling' => 'Freecycling exchanges',
    'bartering'   => 'Bartering exchanges',
    'lending'     => 'Temporary lending exchanges',
],

// AFTER
'exchanges' => [
    'barter' => 'Direct barter exchanges',
],
```

And the matching counts block:

```php
'exchangeCounts' => [
    'barter' => (int) ($typeCounts[Exchange::TYPE_BARTER] ?? 0),
],
```

> This is exactly the loose end I called out when I built the export. Fixing it
> here means your CSV and PDF reports describe a barter-only system — a panel
> member who downloads the report sees only barter figures.

---

## 2. Flutter Mobile App

### 2.1 `lib/screens/listing_detail_screen.dart` — one form, not three

The file branches on the listing's `exchange_type` to render a claim button, a
return-date picker, or a barter form. Collapse it to a single proposal form.

**Delete** the freecycling "Claim" button and the lending return-date picker
(roughly lines 40-105, the `if (type == 'freecycle') … else if (type == 'lending')`
branch chain).

**Replace with:**

```dart
// Direct barter is the only supported transaction. The two-sided offer is
// required by the server (422 if blank), so the button stays disabled until
// the member names what they are trading.
final _offeredItem = TextEditingController();
bool _offerBusy = false;

Future<void> _sendProposal() async {
  final offering = _offeredItem.text.trim();
  if (offering.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Describe the item or skill you are offering in return.')),
    );
    return;
  }

  setState(() => _offerBusy = true);
  try {
    await context.read<ApiService>().createExchange(
          resourceId: widget.listing.id,
          offeredItem: offering,
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Barter proposal sent to the owner.')),
    );
    Navigator.pop(context);
  } on ApiException catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
  } finally {
    if (mounted) setState(() => _offerBusy = false);
  }
}
```

And the matching widget — one field, one button, no date picker:

```dart
Card(
  child: Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Propose a direct barter', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'A barter is a two-sided trade. Describe what you will give in return '
          'for "${widget.listing.title}".',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _offeredItem,
          maxLength: 160,
          decoration: const InputDecoration(
            labelText: 'Item or skill you are offering',
            hintText: 'e.g. 2 kg rice, or guitar lessons for one hour',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _offerBusy ? null : _sendProposal,
          icon: _offerBusy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.swap_horiz),
          label: Text(_offerBusy ? 'Sending…' : 'Send barter proposal'),
        ),
      ],
    ),
  ),
)
```

> `flutter analyze` flags a `dispose()` leak if you add the controller without
> disposing it — add `_offeredItem.dispose();` to the State's `dispose()`.

### 2.2 `lib/core/api_service.dart`

```dart
/// POST /exchanges — propose a direct barter. The server rejects the request
/// unless [offeredItem] or [offeredResourceId] is present.
Future<Map<String, dynamic>> createExchange({
  required int resourceId,
  String? offeredItem,
  int? offeredResourceId,
  String? notes,
}) async =>
    Map<String, dynamic>.from(await _request(_dio.post('/exchanges', data: {
      'resource_id': resourceId,
      if (offeredItem != null && offeredItem.trim().isNotEmpty) 'offered_item': offeredItem.trim(),
      if (offeredResourceId != null) 'offered_resource_id': offeredResourceId,
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
    })) as Map);

/// PATCH /exchanges/{id} — accept, reject, or complete a barter.
Future<Map<String, dynamic>> updateExchange(int id, String status) async =>
    Map<String, dynamic>.from(
        await _request(_dio.patch('/exchanges/$id', data: {'status': status})) as Map);
```

`exchangeType` is **removed** from the signature — the endpoint is barter-only,
so sending it is noise. Update every call site (§2.1, §2.3).

The old `updateExchange` had a 404-fallback to `PUT /exchanges/{id}/status`.
Since §1.4 deletes that route, delete the `catchError` branch too.

### 2.3 `lib/screens/exchanges_screen.dart` — action buttons

Replace the action set to match the new machine:

```dart
// Act on a barter proposal. Accept/Reject are owner-only (the server enforces
// this with 403), so a proposer sees only the completion action.
Widget _actions(Map<String, dynamic> item, String myRole) {
  final status = '${item['raw_status'] ?? ''}';
  final offered = '${item['offering'] ?? 'this item'}';
  final wanted = '${item['wanted'] ?? 'their item'}';

  return switch (status) {
    'pending' when myRole == 'provider' => Row(children: [
        OutlinedButton(onPressed: () => _set(item, 'accepted'), child: const Text('Accept trade')),
        TextButton(onPressed: () => _set(item, 'rejected'), child: const Text('Reject')),
      ]),
    'accepted' => FilledButton(
        onPressed: () => _set(item, 'completed'),
        child: const Text('Mark as completed'),
      ),
    _ => Text('$offering ⇄ $wanted', style: theme.textTheme.bodySmall),
  };
}
```

The confirmation copy also referenced released time-bank credits. Replace those
`detail` strings so they describe a trade, e.g. `"This records that both sides
have handed over: $offering for $wanted."`

### 2.4 Files to check, not to bulk-edit

After the edits above, find what remains:

```bash
cd mobile && grep -rniE 'freecycl|lend|return_date|scheduledReturn|timelapse|claim' lib/
```

Known hits: `home_feed_screen.dart` (~line 145) and
`create_listing_screen.dart` (~line 98) both render an `exchange_type` picker.
Each should offer **Barter only** — delete the segmented control and hardcode
`'barter'`.

---

## 3. React Admin Dashboard

Lowest risk of the three: the DataTable is config-driven, so this is mostly
deleting entries.

### 3.1 `src/pages/ExchangesPage.jsx`

```jsx
// BEFORE
const TYPES = ["all", "freecycling", "bartering", "lending"];

// AFTER
const TYPES = ["all", "barter"];
```

Remove the `"Freecycling"`, `"Lending"` and `"Time Banking"` options from the
Type column filter, leaving `"Bartering"`. Then replace the Credits column
removed during the time-bank pass with the two sides of the trade:

```jsx
{
  key: "offering",
  label: "Offering",
  render: (x) => <span className="text-xs">{x.offering || "—"}</span>,
},
{
  key: "wanted",
  label: "In Return For",
  render: (x) => <span className="text-xs">{x.wanted || "—"}</span>,
},
```

And fix the status filter — `Returned` and `Cancelled` no longer exist:

```jsx
options: [
  { value: "Pending", label: "Pending" },
  { value: "Accepted", label: "Accepted" },
  { value: "Rejected", label: "Rejected" },
  { value: "Completed", label: "Completed" },
],
```

### 3.2 `DashboardPage.jsx` / `AnalyticsPage.jsx`

The "Time Bank" tile is already gone from the earlier pass. What remains is the
lending metric in `ExchangeController::index()`:

```php
// ExchangeController::index() — metrics block
// DELETE 'itemsLentOut' and 'freecyclesGiven'. Keep only barter figures,
// or drop `metrics` entirely and let the screen read the list length.
// Fewer numbers is a stronger defense than a stale one.
```

```jsx
// AnalyticsPage.jsx — if a "by type" breakdown is rendered from `metrics`,
// it now has one bucket. Either drop the chart or label it "Direct barter"
// so a single bar is not mistaken for a bug.
```

---

## 4. Verification

Run in order. Each step is independent and safe to re-run.

```bash
# 1. Schema is barter-only
cd backend
php artisan tinker --execute='
  echo implode(",", \Illuminate\Support\Facades\Schema::getColumnListing("exchanges")), PHP_EOL;
  echo json_encode(\DB::table("exchanges")->select("exchange_type","status")->get()), PHP_EOL;'

# 2. No retired columns remain in code
grep -rn "return_date\|scheduled_return_date" app/ database/migrations/

# 3. Routes resolve and the status route is gone
php artisan route:list --path=exchanges

# 4. PHP syntax across every edited file
for f in app/Http/Controllers/Api/ExchangeController.php \
         app/Models/Exchange.php \
         app/Http/Controllers/Api/AdminPortalController.php \
         app/Http/Controllers/Api/AnalyticsController.php; do php -l "$f"; done

# 5. Frontend builds
cd ../frontend && npx vite build --logLevel error

# 6. Mobile analyzes clean
cd ../mobile && flutter analyze | tail -5

# 7. Residual copy across the whole repo
cd .. && grep -rniE 'freecycl|temporary lend|return_date' backend/app frontend/src mobile/lib
```

**Expected:** step 1 lists `offered_resource_id, offered_item, notes` and no
date columns; step 2 returns nothing; step 3 shows `store`, `index`, `update`
and **not** `updateStatus`; steps 5-6 pass; step 7 is empty.

### Live API check

```bash
cd backend && php artisan serve --port=8899 &

# In a second shell:
TOK=$(curl -s -X POST http://127.0.0.1:8899/api/login \
  -H 'Content-Type: application/json' -H 'Accept: application/json' \
  -d '{"email":"admin@cblrep.ph","password":"Admin@12345"}' \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["access_token"])')

# Must be 422 — a proposal with nothing in return:
curl -s -o /dev/null -w '%{http_code}\n' -X POST http://127.0.0.1:8899/api/exchanges \
  -H "Authorization: Bearer $TOK" -H 'Content-Type: application/json' \
  -d '{"resource_id":1}'

# Must be 201 — a two-sided barter:
curl -s -o /dev/null -w '%{http_code}\n' -X POST http://127.0.0.1:8899/api/exchanges \
  -H "Authorization: Bearer $TOK" -H 'Content-Type: application/json' \
  -d '{"resource_id":1,"offered_item":"2 kg rice"}'

# Must be 404 — the removed lending endpoint:
curl -s -o /dev/null -w '%{http_code}\n' -X PUT http://127.0.0.1:8899/api/exchanges/1/status \
  -H "Authorization: Bearer $TOK" -H 'Content-Type: application/json' \
  -d '{"status":"returned"}'
```

> Change that admin password before your defense. I reset it to `Admin@12345`
> while building the export feature and it is still the live credential.

---

## 5. Defense Notes

Four answers, ready for a panel member who asks why the scope narrowed.

**"Why remove gifting?"** — A one-sided transfer is not a transaction. It fell
outside the barter thesis and added a moderation surface (abuse, disputes over
unreturned items) the system was not designed to handle.

**"Is it still a *portal*?"** — Yes. Listings, proposals, messaging,
verification, and admin moderation are untouched. The transaction type narrowed;
the platform did not.

**"How do you prevent a free gift sneaking back in?"** — Structurally.
`offered_item` / `offered_resource_id` is required by the API, validated in
`store()` before any row is written, and the form disables its button until it
is filled. A zero-cost transfer cannot be represented in the schema.

**"What is the status machine, and why four states?"** —
`pending → accepted → completed`, with `rejected` reachable from `pending` and
`accepted`. Both terminal states are absorbing. Transitions are enforced in
`Exchange::canTransitionTo()` and checked again in the controller, so an
out-of-order status change is a 422, not a corrupt row.

**Leave the removed features in the git history.** `git log --oneline` showing
the scope change as a deliberate, documented commit is stronger evidence of
engineering judgment than a project that never had the features at all.

---

## 6. Copy-Paste Prompt

Paste this to your AI assistant to execute the whole refactor:

> Narrow the CBLREP capstone to direct bartering only. Freecycling and temporary
> lending are removed. Read `/home/ginoong_nigga/Documents/CBLREP-project/REFACTOR_BARTER_ONLY.md`
> in full and execute sections 1 through 4 in order — Laravel schema and models
> first, then the controller, then Flutter, then React. Do not skip the
> verification commands in section 4; report each result. Preserve the
> listings, messaging, verification and admin-moderation features untouched.
> Back up the database before running the migration.
