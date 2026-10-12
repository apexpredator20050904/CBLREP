<?php

use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;
use Illuminate\Http\Request;

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        web: __DIR__.'/../routes/web.php',
        api: __DIR__.'/../routes/api.php',
        commands: __DIR__.'/../routes/console.php',
        health: '/up',
    )
    ->withMiddleware(function (Middleware $middleware) {
        // Register the admin RBAC aliases so routes can use
        // ->middleware('admin') (any admin tier) and
        // ->middleware('super.admin') (Super Administrator only).
        $middleware->alias([
            'admin' => \App\Http\Middleware\AdminMiddleware::class,
            'super.admin' => \App\Http\Middleware\SuperAdminMiddleware::class,
        ]);

        // Laravel 12 installs a default `redirectGuestsTo(fn () => route('login'))`.
        // This project is an API + SPA and defines no route named "login", so any
        // unauthenticated request that did not send `Accept: application/json`
        // (curl, a browser probe, a misconfigured client) crashed with
        // RouteNotFoundException -- a 500 that also leaked absolute file paths and
        // the framework stack trace. Returning null for API paths makes the auth
        // middleware raise a plain AuthenticationException, which the exception
        // handler renders as a clean 401 JSON body.
        $middleware->redirectGuestsTo(
            fn (Request $request) => $request->is('api/*') ? null : '/'
        );
    })
    ->withExceptions(function (Exceptions $exceptions) {
        // The React admin client expects JSON for every API failure. Without
        // this, Sanctum redirects unauthenticated API calls to a web route
        // named "login", which this SPA does not define.
        $exceptions->shouldRenderJsonWhen(
            fn (Request $request) => $request->is('api/*') || $request->expectsJson()
        );
    })->create();
