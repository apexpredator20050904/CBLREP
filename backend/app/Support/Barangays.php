<?php

namespace App\Support;

/**
 * The 20 official barangays of Trinidad, Bohol.
 *
 * Single source of truth for every validation rule, analytics report, and
 * admin filter that accepts a barangay value — keep the client registries
 * (frontend/src/config/community.js and mobile/lib/config/community.dart)
 * in sync with this list.
 */
class Barangays
{
    public const ALL = [
        'Banlasan',
        'Bongbong',
        'Catoogan',
        'Guinobatan',
        'Hinlayagan Ilaud',
        'Hinlayagan Ilaya',
        'Kauswagan',
        'Kinan-oan',
        'La Union',
        'La Victoria',
        'Mabuhay Cabigohan',
        'Mahagbu',
        'Manuel M. Roxas',
        'Poblacion',
        'San Isidro',
        'San Vicente',
        'Santo Tomas',
        'Soom',
        'Tagum Norte',
        'Tagum Sur',
    ];

    public static function isValid(?string $barangay): bool
    {
        return is_string($barangay) && in_array(trim($barangay), self::ALL, true);
    }

    /** Laravel `Rule::in(...)` target for request validation. */
    public static function rule(): \Illuminate\Validation\Rules\In
    {
        return \Illuminate\Validation\Rule::in(self::ALL);
    }
}
