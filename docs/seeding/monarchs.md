# Seeding — Monarchs (Persons + Reigns)

> Tables: `person`, `reign` · Files: `data/seed/persons.json`, `data/seed/reigns.json`
> Effort: **Low** · Phase: **0** · **Recommended to seed first after polities** — highest
> value for least effort.

This powers the top monarch bar: drag the slider and the reigning monarch changes. A `person`
is a stable identity (also reused as event participants); a `reign` is the join "*who* ruled
*what* *when*". One query against Wikidata gives you almost the entire dataset.

> **MVP scope (1000–1216, see [05-seeding.md](../05-seeding.md)).** Seed the ~10 reigns in the
> window: Edward the Confessor → Harold II → William I → William II → Henry I → Stephen →
> Henry II → Richard I → John (plus the Cnut-era kings if you start the slider at 1000). The
> **Anarchy (1135–1154)** is your chance to use `isDisputed: true` (Stephen vs Matilda). Just
> trim the SPARQL results to `reignFrom ≤ 1216`.

## Source — Wikidata SPARQL (do this, it's near-instant)

Wikidata has every English/Scottish monarch with reign start/end dates, dynasty, and epithets
as structured data. Run a SPARQL query at <https://query.wikidata.org>, export CSV/JSON, and
massage into the two files. Sketch of the query (English monarchs):

```sparql
SELECT ?monarch ?monarchLabel ?start ?end ?houseLabel WHERE {
  ?monarch p:P39 ?statement .                    # position held
  ?statement ps:P39 wd:Q18810062 .               # King/Queen of England (use the right QID)
  OPTIONAL { ?statement pq:P580 ?start. }        # start time
  OPTIONAL { ?statement pq:P582 ?end. }          # end time
  OPTIONAL { ?monarch wdt:P53 ?house. }          # noble family / house
  SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
}
ORDER BY ?start
```

Repeat for King/Queen of Scots (different position QID). Verify against Wikipedia's
"List of English/Scottish monarchs" — Wikidata dates can be off or use Julian/regnal quirks.
**Trim to the 1000–1500 window.** Licence: Wikidata is **CC0** (no attribution required, but
credit it anyway in `SOURCES.md`).

## Authoring format

`persons.json` (identity; also used by events):
```json
{
  "slug": "william-i",
  "name": "William I",
  "epithet": "the Conqueror",
  "house": "Normandy",
  "birthYear": 1028,
  "deathYear": 1087,
  "bio": "Duke of Normandy who conquered England in 1066."
}
```

`reigns.json` (the temporal join):
```json
{
  "personSlug": "william-i",
  "politySlug": "kingdom-of-england",
  "title": "King of England",
  "reignFrom": 1066,
  "reignTo": 1087,
  "reignFromDate": "1066-12-25",
  "reignToDate": "1087-09-09",
  "isDisputed": false
}
```

## Field guidance

| Field | How to set it |
|------|----------------|
| `person.slug` | kebab-case unique; reused by `event_participant`. Disambiguate where needed (`john-king-of-england`). |
| `epithet` / `house` | From Wikidata; optional. `house` drives the dynasty display ("Plantagenet", "Lancaster", "York"). |
| `reign.reignFrom/To` | **Integer years** — the filtering key. Half-open: a reign ending 1087 and the next starting 1087 don't overlap. `reignTo` null = beyond 1500. |
| `reignFromDate/ToDate` | Optional precise/fuzzy strings for display only. |
| `title` | "King of England", "King of Scots". |
| `isDisputed` | `true` during contested successions (Anarchy 1135–1153, Wars of the Roses). See gotcha. |

## Validation

- Every `personSlug` / `politySlug` in `reigns.json` resolves to a known slug.
- `reignFrom` ∈ [1000,1500]; `reignTo` null or `> reignFrom`.
- `person.slug` unique.

## Dependencies & order

- **Depends on:** `polity` (by slug), `person` (reign → person).
- Load order: `polity` → `person` → `reign`.

## Gotchas

- **Multiple monarchs in one year is valid.** During disputes the "monarch at year Y" query
  can return >1 reign — model and UI support this (primary + "disputed" badge). Don't
  de-duplicate to force a single ruler; set `isDisputed: true` on the contested reigns.
- **Year vs precise date.** Filtering is by integer year; the precise date is presentational.
  Don't try to filter on `reignFromDate`.
- **Window boundaries.** Monarchs whose reign straddles 1000 or 1500 should be included with
  `reignFrom`/`reignTo` clamped sensibly (or left open with null) so the bar isn't empty at the
  extremes.
