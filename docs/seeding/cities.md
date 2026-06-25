# Seeding — Cities & Population

> Tables: `city`, `population_sample` · Files: `data/seed/cities.json`, `data/seed/population.json`
> Effort: **Low–Medium** · Phase: **0**

Cities are points that grow/shrink over time (the population animation). A `city` is a stable
identity with a fixed location; `population_sample` rows give its **relative importance** at
sparse years, which the API resolves (and interpolates) for any query year.

## Source

- **Coordinates:** Wikidata (P625) or [GeoNames](https://www.geonames.org). Cities don't move,
  so modern coordinates are correct. CC0 / CC-BY.
- **Relative size (`size_rank`):** **hand-authored.** There is no clean dataset for "medieval
  relative importance 1–5." Set it from historical knowledge (Domesday Book, known medieval
  population estimates, ecclesiastical/commercial significance). This is editorial, and that's
  fine — the brief explicitly says circle size is *relative importance, not real numbers*.

MVP cities: London, York, Norwich, Winchester, Canterbury (+ any city referenced by an event,
e.g. Hastings). Working examples: see [`../../data/examples/`](../../data/examples/).

## Authoring format

`cities.json`:
```json
{
  "slug": "london",
  "name": "London",
  "lng": -0.1276, "lat": 51.5074,
  "foundedYear": null,
  "description": "Principal city and commercial centre of England."
}
```

`population.json` — sparse samples per city (NOT one number on the city):
```json
[
  { "citySlug": "london", "year": 1000, "sizeRank": 3 },
  { "citySlug": "london", "year": 1100, "sizeRank": 4 },
  { "citySlug": "london", "year": 1300, "sizeRank": 5 },
  { "citySlug": "london", "year": 1350, "sizeRank": 4 },
  { "citySlug": "london", "year": 1500, "sizeRank": 5 }
]
```

## Field guidance

| Field | How to set it |
|------|----------------|
| `city.slug` | kebab-case unique; referenced by events. |
| `lng` / `lat` | Fixed point; from Wikidata/GeoNames. |
| `foundedYear` | Optional. If set, the API omits the city before this year (don't show a city that doesn't exist yet). |
| `sample.year` | The sample year. Author **sparsely** — only at points where importance meaningfully changes (founding, growth, post-1348 plague dip, recovery). |
| `sample.sizeRank` | Integer 1–5, **relative** importance. 5 = a leading city (London), 1 = minor. Stored as steps; the API can `lerp` between samples for smooth growth (docs/03 §3.2). |

## Validation

- `city.slug` unique; coordinates within map bounds.
- Every `population.citySlug` resolves to a city.
- `(citySlug, year)` unique (one sample per city per year).
- `sizeRank` ∈ [1,5]; `year` ∈ [1000,1500].

## Dependencies & order

- **City** depends on nothing → can load early (alongside polities/persons).
- **population_sample** depends on `city` → load after cities.
- Events reference cities, so load cities **before** events.

## Gotchas

- **Store samples, not a single population.** The growth animation needs the timeline of
  ranks; a lone number can't animate. Keep samples sparse and let the API interpolate.
- **Relative, not absolute.** Never seed or surface real population counts — `size_rank` is a
  1–5 importance scale by design. This keeps you honest where medieval figures are unreliable.
- **Model the plague.** A London/Norwich dip around 1348–1350 then recovery makes the
  animation tell a story — worth authoring those samples deliberately.
- **Founding year.** Set it where a city genuinely post-dates 1000 so it doesn't appear on the
  map before it existed.
