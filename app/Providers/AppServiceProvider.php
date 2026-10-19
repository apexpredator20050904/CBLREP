<?php

namespace App\Providers;

use Illuminate\Cache\RateLimiting\Limit;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\ServiceProvider;
use Illuminate\Support\Str;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        //
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        $this->configureRateLimiters();
    }

    /**
     * Named limiters for the public auth endpoints.
     *
     * Laravel's inline `throttle:5,1` keys on the request host + IP only, so
     * every route sharing that syntax would drain one bucket. Naming them here
     * gives each endpoint its own budget and lets credential attempts be
     * throttled per e-mail address as well as per IP.
     */
    private function configureRateLimiters(): void
    {
        RateLimiter::for('auth-login', fn (Request $request) => [
            Limit::perMinute(10)->by('ip:'.$request->ip()),
            Limit::perMinute(5)->by('account:'.$request->ip().'|'.Str::lower((string) $request->input('email'))),
        ]);

        RateLimiter::for('auth-register', fn (Request $request) => Limit::perMinute(10)->by('ip:'.$request->ip()));

        RateLimiter::for('password-email', fn (Request $request) => Limit::perMinute(3)->by('reset-mail:'.$request->ip().'|'.Str::lower((string) $request->input('email'))));

        RateLimiter::for('password-reset', fn (Request $request) => Limit::perMinute(10)->by('reset:'.$request->ip()));

        // Analytics CSV/PDF exports re-run the aggregate queries and render a
        // document on every hit, so they are capped per administrator. The
        // request has already passed auth:sanctum by the time this resolves,
        // making the user id a stable, more meaningful key than the IP.
        RateLimiter::for('admin-export', fn (Request $request) => Limit::perMinute(10)->by('export:'.($request->user()?->id ?? $request->ip())));

        // Setup rotates the pending secret, so an authenticated admin could
        // otherwise spin this endpoint and churn QR codes. Capped well below
        // the general admin throttle because enrolment is rare.
        RateLimiter::for('admin-2fa-setup', fn (Request $request) => Limit::perMinute(5)->by('2fa-setup:'.($request->user()?->id ?? $request->ip())));

        // Stage 2 of admin sign-in. Two independent ceilings, because the
        // second one is the one that matters:
        //
        //   - per IP: blunts a single host spraying many challenge tokens
        //   - per challenge token: caps brute force at 10 guesses *per issued
        //     challenge* regardless of source IP, so rotating IPs does not
        //     help an attacker who has captured a valid token
        //
        // The model adds a third layer (5 attempts, then the challenge is
        // destroyed) so the real limit is far stricter than this limiter.
        RateLimiter::for('admin-2fa', fn (Request $request) => [
            Limit::perMinute(20)->by('2fa-ip:'.$request->ip()),
            Limit::perMinute(10)->by('2fa-token:'.hash('sha256', (string) $request->input('challenge_token'))),
        ]);

        // Unauthenticated catalogue reads (the public listings feed). Mobile
        // clients poll this in the background, so the budget is per-IP and
        // generous enough for several app instances on one NAT address, while
        // still stopping a single client from hammering the full scan.
        RateLimiter::for('public-read', fn (Request $request) => [
            Limit::perMinute(120)->by('public-read:'.$request->ip()),
        ]);

        // Community safety reports. Keyed by the member (not the IP), because
        // the request is authenticated by the time the limiter resolves and
        // the member id is the meaningful axis: one account must not be able
        // to bury the moderation queue under hundreds of rows, and members
        // behind a single NAT address must not throttle each other.
        RateLimiter::for('report-create', fn (Request $request) => [
            Limit::perMinute(10)->by('report:'.($request->user()?->id ?? $request->ip())),
        ]);
    }
}
