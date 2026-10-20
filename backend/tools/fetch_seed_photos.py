#!/usr/bin/env python3
"""
Fetches the stock photos used by the seeded community listings.

The portal ships with a realistic demo dataset (see CommunitySeeder). A feed of
grey placeholders does not look like a community board, so every seeded listing
carries real photographs.

The photos come from Wikimedia Commons, which serves freely-licensed images
over a public API with no key. For each item we search a few phrasings, score
the candidates (does the title mention the item? is it big enough? is it
landscape enough for a 4:3 card? is the licence permissive?) and keep the best
few as the listing's photo gallery.

Every downloaded image is resized and centre-cropped to 800x600 JPEG so the
feed renders a consistent card, and each one is credited in CREDITS.md next to
the file, because most of them are CC BY / CC BY-SA and those licences require
attribution.

    python3 tools/fetch_seed_photos.py                # fetch anything missing
    python3 tools/fetch_seed_photos.py --force        # re-fetch everything
    python3 tools/fetch_seed_photos.py --only rice-cooker

Output: storage/app/public/seed-listings/<slug>-<n>.jpg  (+ CREDITS.md)
"""

from __future__ import annotations

import argparse
import io
import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request
from dataclasses import dataclass, field
from html import unescape

from PIL import Image, ImageOps

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, 'storage', 'app', 'public', 'seed-listings')

API = 'https://commons.wikimedia.org/w/api.php'
UA = 'CBLREP-seeder/1.0 (community portal; dev@cblrep.ph)'

WIDTH, HEIGHT = 800, 600
QUALITY = 80

# Licences we accept. "Attribution" covers the plain CC BY family.
OK_LICENCE = re.compile(r'(^CC BY|CC BY|CC0|Public domain|Attribution)', re.I)

# The catalogue: slug -> the phrasings we try on Commons, in order.
CATALOGUE: dict[str, list[str]] = {
    'rice-cooker': ['rice cooker', 'electric rice cooker appliance'],
    'electric-fan': ['electric fan', 'stand fan appliance'],
    'refrigerator': ['refrigerator fridge', 'domestic refrigerator'],
    'washing-machine': ['washing machine appliance', 'top loading washing machine'],
    'bluetooth-speaker': ['bluetooth speaker portable', 'portable speaker device'],
    'old-smartphone': ['smartphone mobile phone', 'android smartphone device'],
    'laptop': ['laptop computer', 'notebook computer open'],
    'solar-lamp': ['solar lamp light', 'solar powered lamp'],
    'television': ['television set', 'old cathode ray television'],
    'garden-tools': ['garden tools rake spade', 'hand fork rake garden tool'],
    'fertilizer': ['organic compost fertilizer', 'compost heap fertilizer'],
    'rice-seedlings': ['rice seedlings paddy', 'rice seedling nursery'],
    'vegetable-basket': ['fresh vegetables basket', 'harvested vegetables market'],
    'chicken-feed': ['chicken feed poultry', 'layer chicken feed'],
    'bamboo-table': ['bamboo table furniture', 'bamboo furniture chair'],
    'wooden-chair': ['wooden chair furniture', 'chair wooden stool'],
    'school-desk': ['school desk wooden', 'student desk school'],
    'study-lamp': ['desk lamp table lamp', 'led desk lamp study'],
    'textbooks': ['stack of textbooks', 'books pile school'],
    'bicycle': ['bicycle bike', 'mountain bicycle'],
    'basketball': ['basketball ball', 'basketball court'],
    'dumbbells': ['dumbbell weights gym', 'weight lifting dumbbells'],
    'sewing-machine': ['sewing machine household', 'domestic sewing machine'],
    'carpentry-tools': ['carpentry tools hammer chisel', 'hand plane chisel tools'],
    'fishing-net': ['fishing net cast net', 'fish net trap'],
    'cooking-pot': ['cooking pot aluminum', 'clay cooking pot'],
    'water-container': ['water container plastic drum', 'water tank container'],
    'sewing-fabric': ['fabric rolls textile', 'folded fabric textile'],
    'chicken-coop': ['chicken coop hen house', 'poultry house coop'],
    'broom-set': ['broom cleaning set', 'broom and dustpan'],
    'egg-tray': ['egg tray carton', 'chicken eggs carton'],
    'rice-sack': ['rice sack bag', 'sack of rice grain'],
    'map-and-tarpaulin': ['tarpaulin sheet', 'folding table outdoor'],
    'sewing-scissors': ['sewing scissors tailor', 'scissors cutting fabric'],
    'plant-pots': ['plant pots clay', 'terracotta flower pots'],
    'fishing-rod': ['fishing rod tackle', 'fishing rod reel'],
    'battery-lantern': ['battery lantern led', 'rechargeable lantern light'],
    'corn-sheller': ['corn sheller machine', 'maize corn machine'],
    'frying-pan': ['frying pan skillet', 'cast iron pan'],
    'water-pump': ['water pump irrigation', 'hand water pump'],
}


@dataclass
class Candidate:
    title: str
    url: str
    width: int
    height: int
    licence: str
    author: str
    page: str
    score: int = 0
    reason: str = ''


@dataclass
class Picked:
    slug: str
    path: str
    title: str
    licence: str
    author: str
    page: str
    index: int = 1
    sources: list[str] = field(default_factory=list)


def http_json(url: str, timeout: int = 30) -> dict:
    req = urllib.request.Request(url, headers={'User-Agent': UA})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.load(resp)


def strip_html(raw: str) -> str:
    text = re.sub(r'<[^>]+>', '', raw or '')
    return unescape(text).strip()


def search(term: str, limit: int = 12) -> list[Candidate]:
    """Search Commons for images matching [term]."""
    query = urllib.parse.urlencode({
        'action': 'query',
        'format': 'json',
        'generator': 'search',
        'gsrsearch': f'filetype:bitmap {term}',
        'gsrnamespace': '6',
        'gsrlimit': str(limit),
        'prop': 'imageinfo',
        'iiprop': 'url|extmetadata|size',
        'iiurlwidth': '1400',
    })
    try:
        data = http_json(f'{API}?{query}')
    except Exception as exc:  # noqa: BLE001 - a failed search must not abort the run
        print(f'    ! search failed for "{term}": {exc}', file=sys.stderr)
        return []

    out: list[Candidate] = []
    for page in ((data.get('query') or {}).get('pages') or {}).values():
        info = (page.get('imageinfo') or [{}])[0]
        meta = info.get('extmetadata') or {}
        thumb = (info.get('thumburl') or info.get('url') or '').split('?')[0]
        if not thumb:
            continue
        out.append(Candidate(
            title=page.get('title', ''),
            url=thumb,
            width=int(info.get('thumbwidth') or info.get('width') or 0),
            height=int(info.get('thumbheight') or info.get('height') or 0),
            licence=strip_html((meta.get('LicenseShortName') or {}).get('value', '')),
            author=strip_html((meta.get('Artist') or {}).get('value', ''))[:120],
            page=f'https://commons.wikimedia.org/wiki/{urllib.parse.quote(page.get("title", "").replace(" ", "_"))}',
        ))
    return out


def score(candidate: Candidate, keywords: list[str]) -> int:
    """Rank a candidate: does it actually look like the item we asked for?"""
    title = candidate.title.lower()
    points = 0
    why = []

    for word in keywords:
        if word and word in title:
            points += 4
            why.append(f'title~{word}')
            break
    else:
        # The item is not named in the title at all - a much weaker match.
        points -= 1
        why.append('title-miss')

    if candidate.width >= 900:
        points += 2
        why.append('large')
    elif candidate.width >= 600:
        points += 1

    ratio = candidate.width / max(candidate.height, 1)
    if 1.15 <= ratio <= 1.9:
        points += 2
        why.append('landscape')
    elif ratio < 0.9 or ratio > 2.4:
        points -= 2
        why.append('bad-ratio')

    if OK_LICENCE.search(candidate.licence or ''):
        points += 1
        why.append('licence-ok')
    else:
        points -= 3
        why.append('licence-unknown')

    # Diagrams, maps, logos and scans of documents make poor listing photos.
    if re.search(r'\b(map|logo|diagram|chart|poster|seal|coat of arms|plaque)\b', title):
        points -= 5
        why.append('not-a-photo')

    # A listing photo shows the thing a neighbour would swap for. Jokes,
    # clip art, museum exhibits and product renders do not.
    if re.search(
        r'\b(funny|joke|meme|clipart|clip art|cartoon|drawing|illustration|icon|'
        r'symbol|svg|render|sketch|toy|miniature|model kit|diecast|'
        r'poster|sticker|emoji|face|puking|smiling)\b',
        title,
    ):
        points -= 6
        why.append('not-the-item')

    # A PNG on Commons is far more often a logo or a diagram than a photo.
    if title.endswith('.png'):
        points -= 2
        why.append('png')

    candidate.score = points
    candidate.reason = ', '.join(why)
    return points


def download_and_process(url: str, dest: str) -> bool:
    """Fetch one image and write the 800x600 card-ready JPEG."""
    try:
        req = urllib.request.Request(url, headers={'User-Agent': UA})
        with urllib.request.urlopen(req, timeout=60) as resp:
            raw = resp.read()
    except Exception as exc:  # noqa: BLE001
        print(f'    ! download failed: {exc}', file=sys.stderr)
        return False

    try:
        with Image.open(io.BytesIO(raw)) as img:
            img = ImageOps.exif_transpose(img).convert('RGB')
            # Centre-crop to the card's 4:3 shape, then resize.
            img = ImageOps.fit(img, (WIDTH, HEIGHT), method=Image.LANCZOS, centering=(0.5, 0.5))
            img.save(dest, 'JPEG', quality=QUALITY, optimize=True, progressive=True)
    except Exception as exc:  # noqa: BLE001
        print(f'    ! not a usable image: {exc}', file=sys.stderr)
        return False

    return os.path.getsize(dest) > 4_000


def fetch_item(slug: str, terms: list[str], count: int, force: bool) -> list[Picked]:
    """Pick and download up to [count] photos for one listing."""
    keywords = [t.replace(' ', '') for t in terms]
    keywords += [w for t in terms for w in t.split() if len(w) > 3]

    pool: dict[str, Candidate] = {}
    for term in terms:
        for cand in search(term):
            pool.setdefault(cand.url, cand)

    ranked = sorted(pool.values(), key=lambda c: -score(c, keywords))

    picked: list[Picked] = []
    for cand in ranked:
        if len(picked) >= count:
            break
        if cand.score < 3:
            continue
        name = f'{slug}-{len(picked) + 1}.jpg'
        dest = os.path.join(OUT_DIR, name)
        if not force and os.path.exists(dest):
            picked.append(Picked(slug, f'seed-listings/{name}', cand.title, cand.licence, cand.author, cand.page, len(picked) + 1))
            continue
        if not download_and_process(cand.url, dest):
            continue
        picked.append(Picked(slug, f'seed-listings/{name}', cand.title, cand.licence, cand.author, cand.page, len(picked) + 1))

    return picked


def write_credits(picked: list[Picked]) -> None:
    """Write the attribution file the licences require."""
    lines = [
        '# Seed listing photos - attribution',
        '',
        'The photographs used by the seeded community listings (see',
        '`database/seeders/CommunitySeeder.php`) are downloaded from Wikimedia',
        'Commons by `tools/fetch_seed_photos.py`.',
        '',
        'Most are CC BY or CC BY-SA, which require attribution - this file is',
        'that attribution. The images are not covered by the project\'s own',
        'licence; each line below names the original author and licence.',
        '',
    ]
    for p in picked:
        lines.append(f'## {p.path}')
        lines.append('')
        lines.append(f'- **File**: {p.title}')
        lines.append(f'- **Author**: {p.author or "unknown"}')
        lines.append(f'- **Licence**: {p.licence or "see source"}')
        lines.append(f'- **Source**: {p.page}')
        lines.append('')

    with open(os.path.join(OUT_DIR, 'CREDITS.md'), 'w') as handle:
        handle.write('\n'.join(lines))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--force', action='store_true', help='re-download even if the file exists')
    parser.add_argument('--only', help='fetch a single slug')
    parser.add_argument('--count', type=int, default=2, help='photos per listing (default 2)')
    args = parser.parse_args()

    os.makedirs(OUT_DIR, exist_ok=True)

    catalogue = CATALOGUE if not args.only else {args.only: CATALOGUE.get(args.only, [])}
    if not catalogue:
        print(f'Unknown slug "{args.only}"', file=sys.stderr)
        return 1

    all_picked: list[Picked] = []
    failures: list[str] = []

    for index, (slug, terms) in enumerate(catalogue.items(), start=1):
        print(f'[{index}/{len(catalogue)}] {slug} ...', flush=True)
        picked = fetch_item(slug, terms, args.count, args.force)
        if not picked:
            failures.append(slug)
            print(f'    ! no usable photo for {slug}')
            continue
        for p in picked:
            print(f'    + {p.path}  <- {p.title[:60]}  [{p.licence}]')
        all_picked.extend(picked)
        time.sleep(0.2)

    write_credits(all_picked)

    print()
    print(f'photos written : {len(all_picked)}')
    print(f'credits file   : {os.path.join(OUT_DIR, "CREDITS.md")}')
    if failures:
        print(f'NO PHOTO FOR   : {", ".join(failures)}')
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
