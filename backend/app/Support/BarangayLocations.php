<?php

namespace App\Support;

/**
 * Barangay anchor coordinates for Trinidad, Bohol — mirrors the Flutter
 * client's barangay registry so listings without stored GPS still resolve to
 * a sensible map pin (the municipal centre is the fallback).
 */
class BarangayLocations
{
    public const CENTER_LAT = 10.0797;
    public const CENTER_LNG = 124.3431;

    private const COORDS = [
        'Poblacion' => [10.0797, 124.3431],
        'Banlasan' => [10.0912, 124.3315],
        'Bongbong' => [10.0664, 124.3562],
        'Catoogan' => [10.0885, 124.3541],
        'Guinobatan' => [10.0711, 124.3302],
        'Hinlayagan Ilaud' => [10.0542, 124.3611],
        'Hinlayagan Ilaya' => [10.0461, 124.3698],
        'Kauswagan' => [10.1023, 124.3389],
        'Kinan-oan' => [10.0589, 124.3233],
        'La Union' => [10.1102, 124.3211],
        'La Victoria' => [10.0638, 124.3371],
        'Mabuhay Cabigohan' => [10.0958, 124.3628],
        'Mahagbu' => [10.0521, 124.3455],
        'Manuel M. Roxas' => [10.0871, 124.3168],
        'San Isidro' => [10.1108, 124.3542],
        'San Vicente' => [10.0703, 124.3634],
        'Santo Tomas' => [10.0944, 124.3462],
        'Soom' => [10.0497, 124.3311],
        'Tagum Norte' => [10.1161, 124.3342],
        'Tagum Sur' => [10.0621, 124.3519],
    ];

    /** [lat, lng] for a location/barangay string; municipal centre fallback. */
    public static function for(?string $location): array
    {
        if ($location) {
            foreach (self::COORDS as $barangay => $coords) {
                if (stripos($location, $barangay) !== false) {
                    return $coords;
                }
            }
        }
        return [self::CENTER_LAT, self::CENTER_LNG];
    }
}
