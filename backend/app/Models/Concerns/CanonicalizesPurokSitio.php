<?php

namespace App\Models\Concerns;

use App\Support\Puroks;

/**
 * Keeps every `purok_sitio` write canonical, wherever it originates.
 *
 * The API rule only decides whether a value is accepted; it does not rewrite
 * it. Funnelling storage through this mutator means "purok  poblacion  norte"
 * and "PUROK Poblacion Norte" land as the same "Purok Poblacion Norte", so the
 * stored value is safe to group, filter and search. Because it is a mutator,
 * any future controller that writes the attribute inherits the behaviour for
 * free instead of having to remember to normalise.
 *
 * Used by User, Resource and Exchange — the three location-bearing models.
 */
trait CanonicalizesPurokSitio
{
    public function setPurokSitioAttribute(mixed $value): void
    {
        $this->attributes['purok_sitio'] = Puroks::canonicalize(is_string($value) ? $value : null);
    }
}
