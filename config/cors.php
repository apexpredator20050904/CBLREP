<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Cross-Origin Resource Sharing (CORS) Configuration
    |--------------------------------------------------------------------------
    |
    | This app is consumed by a React SPA (Vite dev server on :5173) and a
    | Flutter mobile client, usually while developing over a local Wi-Fi
    | network. The entries below therefore allow the local machine and the
    | private-LAN ranges in addition to any explicitly listed dev origin.
    |
    | Auth uses Sanctum *bearer tokens* (Authorization header) rather than
    | cookies, so `supports_credentials` stays false. Browsers refuse to pair
    | the wildcard/pattern matching below with credentialed requests anyway.
    |
    | To learn more: https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS
    |
    */

    'paths' => ['api/*', 'sanctum/csrf-cookie'],

    // Any HTTP verb the API exposes (GET, POST, PATCH, PUT, DELETE, OPTIONS).
    'allowed_methods' => ['*'],

    // Explicit origins for the Vite dev server / preview on this machine.
    // Private-LAN and loopback origins are already covered by the pattern
    // below, so only the dev-server defaults are listed here.
    'allowed_origins' => [
        'http://localhost:5173',
        'http://127.0.0.1:5173',
    ],

    // Match any dev origin served from localhost or a private IPv4 address
    // (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16), on any port. This is what
    // lets a teammate's phone or a second machine hit the API over the LAN
    // without editing this file for every new device.
    //
    // The ngrok entries below cover the public HTTPS tunnel used for the
    // capstone defense: the React admin console is loaded from a Vercel/local
    // origin but calls the API through `*.ngrok-free.app`. Only the admin
    // console is subject to CORS — the Flutter client sends no Origin header.
    'allowed_origins_patterns' => [
        '#^https?://(localhost|127\.0\.0\.1|10\.\d{1,3}\.\d{1,3}\.\d{1,3}|172\.(1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3}|192\.168\.\d{1,3}\.\d{1,3})(:\d+)?$#',
        // ngrok free/paid tunnel hostnames (the subdomain changes per session).
        '#^https://[a-z0-9-]+\.ngrok-free\.app$#',
        '#^https://[a-z0-9-]+\.ngrok-free\.dev$#',
        '#^https://[a-z0-9-]+\.ngrok\.app$#',
        '#^https://[a-z0-9-]+\.ngrok\.io$#',
    ],

    'allowed_headers' => ['*'],

    'exposed_headers' => [],

    // Cache preflight responses for a day so the SPA/mobile client does not
    // re-issue an OPTIONS round-trip before every request.
    'max_age' => 86400,

    'supports_credentials' => false,

];