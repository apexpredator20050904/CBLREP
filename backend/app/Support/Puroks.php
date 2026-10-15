<?php

namespace App\Support;

/**
 * Validation and canonicalisation for the purok/sitio micro-location inside a
 * barangay.
 *
 * Trinidad (municipality) has no cross-barangay purok registry, so the rule
 * is structural: the value must name a purok ("Purok 3", "Purok Poblacion
 * Norte") or a sitio ("Sitio Cadapdapan") and must never carry municipal /
 * provincial scope ("Barangay X, Trinidad, Bohol" would defeat the
 * barangay-scoped design).
 *
 * Members type these by hand, so input is accepted case-insensitively and with
 * Unicode letters (real names such as "Sitio Peña" or "Sitio Sto. Niño"), then
 * rewritten into one canonical form before storage — otherwise "purok 3" and
 * "PUROK  3" would fragment a single purok into several near-identical values.
 * The mobile client mirrors this rule: mobile/lib/config/community.dart
 * (isValidPurokSitio / canonicalizePurokSitio).
 */
class Puroks
{
    /** Trinidad-style designation: "Purok …" / "Sitio …", any case, Unicode letters. */
    private const PATTERN = '/^(Purok|Sitio)\s+[\p{L}\p{N}][\p{L}\p{N} .,\'\-]{0,58}$/iu';

    /** Reject municipal-scope or empty values. */
    private const FORBIDDEN = '/(barangay|trinidad|bohol|municipal|city|province)/i';

    /**
     * Fold a hand-typed value into its canonical stored form:
     *   - trim, and collapse internal whitespace runs (including the
     *     non-breaking spaces phone keyboards emit) to a single space
     *   - restore the "Purok" / "Sitio" designation to its proper casing
     *   - re-insert the space when it was dropped ("Purok3" => "Purok 3")
     *   - Unicode NFC normalisation when the intl extension is available
     *
     * Whatever follows the designation is left exactly as typed: title-casing
     * it would mangle abbreviations and proper nouns ("Sto. Niño", "III",
     * "3-A"). Returns null for null/blank input.
     */
    public static function canonicalize(?string $value): ?string
    {
        if (! is_string($value)) {
            return null;
        }

        $v = $value;
        if (class_exists(\Normalizer::class)) {
            // Best-effort: compose accents so "Pe\u{0301}" and "Pe\u{00E9}" agree.
            $v = \Normalizer::normalize($v, \Normalizer::FORM_C) ?: $v;
        }

        $v = trim(preg_replace('/[\s\x{00A0}\x{202F}]+/u', ' ', $v) ?? $v);

        if ($v === '') {
            return null;
        }

        // Re-attach a dropped separator, preserving the typed casing for now.
        $v = preg_replace('/^(purok|sitio)(?=[\p{L}\p{N}])/iu', '$1 ', $v) ?? $v;

        // Restore the designation's canonical casing.
        $v = preg_replace_callback('/^(purok|sitio)\b/iu', function (array $m): string {
            return ucfirst(strtolower($m[1]));
        }, $v) ?? $v;

        return $v;
    }

    public static function isValid(?string $value): bool
    {
        $v = self::canonicalize($value);
        if ($v === null || mb_strlen($v) < 3 || mb_strlen($v) > 60) {
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
