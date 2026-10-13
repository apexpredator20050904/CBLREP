<?php

use Illuminate\Support\Facades\Route;

Route::get('/', function () {
    return response()->json([
        'app' => 'CBLREP — Community-Based Learning & Resource Exchange Portal',
        'status' => 'ok',
        'database' => config('database.connections.mysql.database'),
    ]);
});
