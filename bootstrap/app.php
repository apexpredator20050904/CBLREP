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
        // Register the admin RBAC alias so routes can use ->middleware('admin').
        $middleware->alias(['admin' => \App\Http\Middleware\AdminMiddleware::class]);
    })
    ->withExceptions(function (Exceptions $exceptions) {
        // The React admin client expects JSON for every API failure. Without
        // this, Sanctum redirects unauthenticated API calls to a web route
        // named "login", which this SPA does not define.
        $exceptions->shouldRenderJsonWhen(
            fn (Request $request) => $request->is('api/*') || $request->expectsJson()
        );
    })->create();
