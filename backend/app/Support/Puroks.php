<?php

namespace App\Support;

/**
 * Validation for the purok/sitio micro-location inside a barangay.
 *
 * Trinidad (municipality) has no cross-barangay purok registry, so the rule
 * is structural: the value must name a purok ("Purok 3", "Purok Poblacion
 * Norte") or a sitio ("Sitio Cadapdapan") and must never carry municipal /
 * provincial scope ("Barangay X, Trinidad, Bohol" would defeat the
 * barangay-scoped design). Keep client hints in sync:
 * mobile/lib/config/community.dart and frontend/src/config/community.js.
 */
class Puroks
{
    /** Trinidad-style designation: "Purok …" / "Sitio …". */
    private const PATTERN = '/^(Purok|Sitio)\s+[A-Za-z0-9][A-Za-z0-9 .,\'-]{0,49}$/u';

    /** Reject municipal-scope or empty values. */
    private const FORBIDDEN = '/(barangay|trinidad|bohol|municipal|city|province)/i';

    public static function isValid(?string $value): bool
    {
        if (! is_string($value)) {
            return false;
        }
        $v = trim($value);
        if (mb_strlen($v) < 3 || mb_strlen($v) > 60) {
            return false;
        }

        return preg_match(self::PATTERN, $v) === 1 && preg_match(self::FORBIDDEN, $v) !== 1;
    }

    /** Laravel validation rule usable inline in validate() calls. */
    public static function rule(): \Closure
    {
        return function (string $attribute, mixed $value, \Closure $fail) {
            if (! self::isValid(is_string($value) ? $value : null)) {
                $fail('The :attribute must be a purok or sitio name (e.g. "Purok 3" or "Sitio Cadapdapan").');
            }
        };
    }
}
