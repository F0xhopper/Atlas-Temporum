# Seeding — Territories

> Table: `territory_version` · Files: `data/seed/territories/*.geojson`
> Effort: **High (this is the big one)** · Phase: **0 (placeholders) → 1 (real borders)**

Territories are the **headline feature** — "slide through time and watch Britain change" *is*
the territory polygons morphing. They're also ~90% of the seeding effort. So the strategy is:
ship crude placeholders in Phase 0 so the whole app works end-to-end, then invest real effort
in accurate borders in Phase 1. **Never let territory authoring block the rest of the app.**

A `territory_version` row = "polity P controlled *this shape* during `[validFrom, validTo)`".
You create a new version only when borders **meaningfully change** — most years reuse a
version and the map snaps (no polygon morphing; that's a deliberate MVP decision, docs/02 §1).

## Storage: GeoJSON in, PostGIS out — never store raw JSON

Three formats for three jobs (this is the key decision):

| Stage | Format |
|-------|--------|
| Authoring (files) | GeoJSON — diff-able, editable in QGIS/geojson.io |
| Storage (Postgres) | `geometry(MultiPolygon, 4326)` native — GIST-indexed, validatable, simplifiable |
| Serving (to MapLibre) | GeoJSON via `ST_AsGeoJSON` |

The loader reads the file with `ST_GeomFromGeoJSON`, runs `ST_MakeValid` +
`ST_SimplifyPreserveTopology`, and stores native geometry. **Do not** dump the GeoJSON string
into a `text`/`jsonb` column — you'd lose the spatial index, validity checks, and simplification.

## Source — start from an existing historical-GIS dataset

Do **not** draw medieval Britain by hand.

1. **[`aourednik/historical-basemaps`](https://github.com/aourednik/historical-basemaps)** —
   world GeoJSON borders at snapshot years (…1000, 1100, 1200, 1300, 1400, 1492…).
   **CC-BY-SA** (attribute + share-alike). This is your primary source.
2. **Clip** to a Britain bounding box (roughly `[-11, 49.5, 2.2, 61]`) — in QGIS or with
   `mapshaper` / `ogr2ogr`.
3. **Keep** only the polities you model; map each feature to a `politySlug`.
4. **Refine** the moments the snapshots miss: 1066 transition, 1284 Welsh annexation,
   1455–1485 instability. Hand-edit in QGIS or [geojson.io](https://geojson.io).
5. **Simplify** hard (`ST_SimplifyPreserveTopology` or mapshaper) and trim coordinate precision
   to ~5 decimals. Medieval borders were fuzzy — high precision is dishonest and heavy.

Other sources: **OpenHistoricalMap** (ODbL, more granular, more work); **Euratlas** (excellent
but the detailed vectors are commercial — use the free century maps as a visual reference only).
Modern coastline/sea for the basemap: **Natural Earth** (public domain).

## Authoring format

One file per polity (`data/seed/territories/kingdom-of-england.geojson`) is recommended over
one-file-per-year: it matches the `territory_version` model, makes diffs readable ("England's
1284 borders changed"), and lets polities change on independent years. Each feature carries the
temporal/identity metadata in `properties`. See
[`../../data/examples/territories.geojson`](../../data/examples/territories.geojson):

```json
{
  "type": "Feature",
  "properties": {
    "politySlug": "kingdom-of-england",
    "validFrom": 1066,
    "validTo": null,
    "confidence": "approximate",
    "note": "Norman and later England."
  },
  "geometry": { "type": "MultiPolygon", "coordinates": [ /* ... */ ] }
}
```

> A reasonable workflow: import the dataset's **per-year snapshots** first, then reshape into
> per-polity files once. Snapshots are easier to source; per-polity is nicer to maintain.

## Field guidance

| Property | How to set it |
|----------|----------------|
| `politySlug` | Must match a `polity.slug`. The loader resolves it to `polity_id`. |
| `validFrom` | Integer year the borders take effect (inclusive). |
| `validTo` | Integer year they end (exclusive), or `null` for "through 1500". Half-open so adjacent versions don't overlap or gap. |
| `confidence` | `attested \| approximate \| disputed` — be honest; most medieval borders are `approximate`. |
| `note` | Optional caveat ("borders highly uncertain"). |
| geometry | `MultiPolygon`, SRID 4326 (lng/lat). Use MultiPolygon even for single landmasses for schema consistency. |

## Validation

- `politySlug` resolves to a known polity.
- `validFrom` ∈ [1000,1500]; `validTo` null or `> validFrom`.
- Geometry is valid (`ST_IsValid`; loader runs `ST_MakeValid`), SRID 4326, type MultiPolygon.
- **Per polity, intervals shouldn't unintentionally overlap** — overlapping versions for the
  same polity mean two shapes are "valid" at once. The validator should flag overlaps so they're
  deliberate, not accidental.
- Optional sanity: geometry sits within the map bounds bbox.

## Dependencies & order

- **Depends on:** `polity` (by slug). Load polities first.
- Nothing depends on territories, so they can load last — which is exactly why placeholders are
  safe in Phase 0.

## Phasing

- **Phase 0 — placeholders:** crude rectangles for England + Scotland (the example file is
  literally this). The territories layer renders; you build and test the full map+timeline loop.
- **Phase 1 — real borders:** replace placeholders with clipped, simplified
  `historical-basemaps` polygons at the key transition years (1000, 1066, 1086, 1154, 1284,
  1455, 1471, 1485…). Add Wales/earldoms. **Invest your quality effort here** — this is the
  feature the app is judged on.

## Gotchas

- **Snap, don't morph.** Don't try to interpolate/animate polygon shapes between versions —
  it's hard and historically dishonest. The slider snaps to whichever version is valid; a short
  `fill-opacity` cross-fade on change is enough polish (docs/04 §4.2).
- **Authoring is the bottleneck, not code.** Budget time for QGIS/clipping, not for the loader.
- **Simplify aggressively.** Oversized polygons bloat every `/state` response. Simplify in the
  seed step and ship coarser geometry at low zoom if needed.
- **Licence hygiene.** historical-basemaps is CC-BY-SA — record attribution in `data/SOURCES.md`
  and keep derivative geometry share-alike compatible.
- **Don't store GeoJSON as text.** Repeat: native `geometry` column, or you lose spatial
  indexing and validation.
