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
    // Replace or extend the LAN entry when the PC's IP address changes.
    'allowed_origins' => [
        'http://localhost:5173',
        'http://127.0.0.1:5173',
        'http://192.168.1.74:5173',
    ],

    // Match any dev origin served from localhost or a private IPv4 address
    // (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16), on any port. This is what
    // lets a teammate's phone or a second machine hit the API over the LAN
    // without editing this file for every new device.
    'allowed_origins_patterns' => [
        '#^https?://(localhost|127\.0\.0\.1|10\.\d{1,3}\.\d{1,3}\.\d{1,3}|172\.(1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3}|192\.168\.\d{1,3}\.\d{1,3})(:\d+)?$#',
    ],

    'allowed_headers' => ['*'],

    'exposed_headers' => [],

    // Cache preflight responses for a day so the SPA/mobile client does not
    // re-issue an OPTIONS round-trip before every request.
    'max_age' => 86400,

    'supports_credentials' => false,

];