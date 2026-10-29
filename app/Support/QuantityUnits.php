<?php

namespace App\Support;

/**
 * The unit vocabulary for structured NEED quantities.
 *
 * Keys are stored in `resources.quantity_unit`; labels are presentation only.
 * The mobile client mirrors this list in
 * mobile/lib/config/listing_options.dart — keep the two in sync.
 *
 * Quantities are pluralised by value ("1 sack" / "2 sacks"). Abbreviations
 * such as kg, g and L stay invariant, which is how they are written on a
 * market list in Trinidad.
 */
final class QuantityUnits
{
    public const KEYS = [
        'piece',
        'kg',
        'gram',
        'sack',
        'bundle',
        'hour',
        'liter',
        'pack',
        'tray',
        'dozen',
    ];

    private const SINGULAR = [
        'piece' => 'pc',
        'kg' => 'kg',
        'gram' => 'g',
        'sack' => 'sack',
        'bundle' => 'bundle',
        'hour' => 'hour',
        'liter' => 'L',
        'pack' => 'pack',
        'tray' => 'tray',
        'dozen' => 'dozen',
    ];

    private const PLURAL = [
        'piece' => 'pcs',
        'kg' => 'kg',
        'gram' => 'g',
        'sack' => 'sacks',
        'bundle' => 'bundles',
        'hour' => 'hours',
        'liter' => 'L',
        'pack' => 'packs',
        'tray' => 'trays',
        'dozen' => 'dozen',
    ];

    public static function isValid(?string $unit): bool
    {
        return is_string($unit) && in_array($unit, self::KEYS, true);
    }

    /** The label for one unit, pluralised when the amount is not exactly one. */
    public static function label(string $unit, float|int|null $value = 1): string
    {
        $isOne = $value !== null && (float) $value === 1.0;

        return ($isOne ? self::SINGULAR : self::PLURAL)[$unit] ?? $unit;
    }

    /**
     * Compose the legacy display string, e.g. "5 kg", "1 sack", "2.5 hours".
     *
     * This is what gets written back to `resources.quantity` so old clients
     * keep showing the amount after the structured fields are in use.
     */
    public static function format(float|int $value, string $unit): string
    {
        $number = rtrim(rtrim(number_format((float) $value, 2, '.', ''), '0'), '.');

        return $number.' '.self::label($unit, $value);
    }
}
